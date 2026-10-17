All research was performed against the local upstream tree at /home/<user>/claude/r11/linux (Linux 7.2.0-rc5, i.e. current mainline) plus web sources. Every quoted snippet below was verified by direct read of the file at that path.

# (a) Upstream drivers that read a DCS panel ID

Important negative result first: **there is no `mipi_dsi_dcs_get_panel_id()` helper in upstream** (verified by grep of `include/drm/`, `include/video/mipi_display.h`, `drivers/gpu/drm/drm_mipi_dsi.c`). Drivers use `mipi_dsi_dcs_read()` / `mipi_dsi_dcs_read_multi()` directly with either `MIPI_DCS_GET_DISPLAY_ID` (0x04) or the one-byte 0xDA/0xDB/0xDC reads. **Of the 136 files in `drivers/gpu/drm/panel/`, only ~8 do any DSI read at all**, and only one merged driver actually selects a variant table from the ID.

## 1. panel-samsung-s6e8aa0 — THE canonical runtime variant selection driver
`drivers/gpu/drm/panel/panel-samsung-s6e8aa0.c`
URLs: https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-samsung-s6e8aa0.c — codebrowser: https://codebrowser.dev/linux/linux/drivers/gpu/drm/panel/panel-samsung-s6e8aa0.c.html

- Single compatible `"samsung,s6e8aa0"`; variant tables keyed by ID:
```c
struct s6e8aa0_variant { u8 version; const s6e8aa0_gamma_table *gamma_tables; };
static const struct s6e8aa0_variant s6e8aa0_variants[] = {
    { .version = 32,  .gamma_tables = s6e8aa0_gamma_tables_v32 },
    { .version = 96,  .gamma_tables = s6e8aa0_gamma_tables_v96 },
    { .version = 142, .gamma_tables = s6e8aa0_gamma_tables_v142 },
    { .version = 210, .gamma_tables = s6e8aa0_gamma_tables_v142 },
};
```
- ID read (vendor cmd 0xd1, 3 bytes) with strict failure policy:
```c
static void s6e8aa0_read_mtp_id(struct s6e8aa0 *ctx)
{
    u8 id[3]; int ret, i;
    ret = s6e8aa0_dcs_read(ctx, 0xd1, id, ARRAY_SIZE(id));
    if (ret < 0 || ret < ARRAY_SIZE(id) || id[0] == 0x00) {
        dev_err(ctx->dev, "read id failed\n");
        ctx->error = -EIO; return;
    }
    for (i = 0; i < ARRAY_SIZE(s6e8aa0_variants); ++i)
        if (id[1] == s6e8aa0_variants[i].version) break;
    if (i >= ARRAY_SIZE(s6e8aa0_variants)) {
        dev_err(ctx->dev, "unsupported display version %d\n", id[1]);
        ctx->error = -EINVAL; return;      /* unknown ID = hard failure */
    }
    ctx->variant = &s6e8aa0_variants[i]; ctx->version = id[1]; ctx->id = id[2];
}
```
- Called in `prepare()` (not probe): `s6e8aa0_prepare()` → `s6e8aa0_power_on()` (regulator_bulk_enable vdd3/vci, power_on_delay, reset toggle, reset_delay) → `s6e8aa0_set_sequence()` → `s6e8aa0_read_mtp_id()` → `s6e8aa0_panel_init()`. On error, `prepare()` unwinds via `s6e8aa0_unprepare()`. Mode/resolution still come from DT (`of_get_videomode` + power-on-delay/reset-delay/init-delay, width/height-mm), not from the ID. Sets `ctx->panel.prepare_prev_first = true;` (needs host pre-enabled before LP commands).

## 2. panel-samsung-s6e63m0 — ID read with graceful fallback for unknown ID
`drivers/gpu/drm/panel/panel-samsung-s6e63m0.c` (frontends `panel-samsung-s6e63m0-dsi.c`, `-spi.c`; URL: https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-samsung-s6e63m0.c)

- `prepare()` → power_on → unlock keys (`MCS_LEVEL_2_KEY`/`MCS_MTP_KEY` = 0x5a 0x5a) → `s6e63m0_check_lcd_type()` reading MCS_READ_ID1/2/3 (transport-agnostic callbacks, i.e. works over SPI or DSI):
```c
switch (id2) {
case S6E63M0_LCD_ID_VALUE_M2: ...; ctx->elvss_pulse = id3; break;
case S6E63M0_LCD_ID_VALUE_SM2: case S6E63M0_LCD_ID_VALUE_SM2_1: ...; break;
default:
    dev_info(ctx->dev, "unknown LCD panel type %02x\n", id2);
    ctx->elvss_pulse = 0x16;   /* default, do NOT fail */
    break;
}
ctx->lcd_type = id2;
```
Read transport error → returns error → `prepare()` fails. Unknown-but-valid ID → continue with default parameters.

## 3. panel-novatek-nt35560 — modern `*_multi` API ID read (Sony panels)
`drivers/gpu/drm/panel/panel-novatek-nt35560.c`
- Config-per-compatible table (Sony ACX424AKP 480x864 vs ACX424AKM 480x854):
```c
struct nt35560_config { const struct drm_display_mode *vid_mode;
                        const struct drm_display_mode *cmd_mode; };
static const struct of_device_id nt35560_of_match[] = {
    { .compatible = "sony,acx424akp", .data = &sony_acx424akp_data },
    { .compatible = "sony,acx424akm", .data = &sony_acx424akm_data },
};
```
- ID read uses modern API, called in `nt35560_prepare()` right after `nt35560_power_on()` (regulator "vddi" + reset):
```c
mipi_dsi_dcs_read_multi(dsi_ctx, NT35560_DCS_READ_ID1, &vendor, 1);
mipi_dsi_dcs_read_multi(dsi_ctx, NT35560_DCS_READ_ID2, &version, 1);
mipi_dsi_dcs_read_multi(dsi_ctx, NT35560_DCS_READ_ID3, &panel, 1);
if (vendor == 0x00) { dsi_ctx->accum_err = -ENODEV; return; }  /* all-zero = not present */
val = (vendor << 8) | panel;
switch (val) { case DISPLAY_SONY_ACX424AKP_ID1...: log; default: "unknown vendor"; }
```
Unknown ID here is only logged (informational), because variant selection is done by DT compatible instead. This is the closest merged analog to "two panels, same driver" — resolved via two compatibles, one per panel, with the ID read serving as sanity-check.

## 4. panel-novatek-nt35510 — 0xDA/0xDB/0xDC reads, per-panel config tables
`drivers/gpu/drm/panel/panel-novatek-nt35510.c`
```c
#define MCS_CMD_READ_ID1 0xDA
#define MCS_CMD_READ_ID2 0xDB
#define MCS_CMD_READ_ID3 0xDC
ret = mipi_dsi_dcs_read(dsi, MCS_CMD_READ_ID1, &id1, 1); /* id2, id3 same */
dev_info(nt->dev, "MTP ID manufacturer: %02x version: %02x driver: %02x\n", ...);
```
Called inside `nt35510_power_on()` (regulators + reset toggle + MTP read-param/setting prelude), i.e. DSI traffic only after power-up; the return value is ignored (logging only). Per-panel variant data (full mode + gamma + power tables) is selected by `of_device_id .data`: `hydis,hva40wv1`, `frida,frd400b25025`, all under driver compatible `"novatek,nt35510"`. This is the upstream-idiomatic "one controller, N panels, one file" structure (documented struct `nt35510_config`: width/height mm, `drm_display_mode`, mode_flags, avdd[], bt*ctr[], gamma tables).

## 5. panel-dsi-cm — generic command-mode multi-panel driver
`drivers/gpu/drm/panel/panel-dsi-cm.c`; binding: `Documentation/devicetree/bindings/display/panel/panel-dsi-cm.yaml`
- Reads DCS_GET_ID1/2/3 in `dsicm_power_on()` after hw reset + sleep-out; exposed via sysfs `hw_revision`, not used to choose variant. Resolution/te_support come from per-compatible `struct dsic_panel_data` match data:
```c
static const struct of_device_id dsicm_of_match[] = {
    { .compatible = "tpo,taal", .data = &taal_data },          /* 864x480 */
    { .compatible = "nokia,himalaya", .data = &himalaya_data }, /* 480x864 */
    { .compatible = "motorola,droid4-panel", .data = &droid4_data }, /* 540x960 */
};
```
- Probe: `devm_drm_panel_alloc` → `dsicm_probe_of` → `dsicm_hw_reset()` at probe (!), backlight, `drm_panel_add()` then `mipi_dsi_attach()` with cleanup `err_dsi_attach: drm_panel_remove(...)`.

## 6. Others with reads (not variant-selection)
- `panel-sitronix-st7789v.c`: reads `MIPI_DCS_GET_DISPLAY_ID` (0x04) in `st7789v_check_id()` from `prepare()`; mismatch → `dev_warn("Unrecognized panel IDs")`, non-fatal; skipped if SPI_NO_RX.
- `panel-edp.c`: eDP panel-id detection via EDID (`drm_edid_get_panel_id()`), not DSI — a different mechanism, not applicable to MIPI DSI.
- `panel-samsung-s6e3ha8/ha2/ld9040`, `panel-novatek-nt35532/36672a`, phone-era drivers (nt35597, sofef00, hx8394, etc.): **zero ID reads**; they do not autodetect.

# (b) Structural idioms for a NEW merged panel driver

1. **Single file, single driver, per-variant desc tables selected by `of_device_id .data`.** The dominant upstream pattern for "same driver, several panels" is one compatible string per panel variant, each mapping to a `const struct xxx_panel_desc` with `{ mode, init_sequence/init_func, mode_flags, format, lanes, width/height_mm }`. Examples: `panel-himax-hx8394.c` (6 compatibles → 6 descs), `panel-samsung-s6d7aa0.c` (3 panels on S6D7AA0 controller; `init_func`/`off_func` + `panel_type` enum + per-panel `drm_display_mode` + `mode_flags`), `panel-boe-th101mb31ig002-28a.c` (2 compatibles, per-panel `init` callback + delays), `panel-boe-himax8279d.c`, `panel-motorola-mot.c`.
2. **Runtime ID-based selection exists upstream in exactly one merged driver: panel-samsung-s6e8aa0** (hard-fail on unknown ID: `-EINVAL`; hard-fail on read failure: `-EIO`). The soft-fail variants (log-only): s6e63m0 (default params), nt35560/st7789v (warn only). Modern new drivers should prefer the `mipi_dsi_multi_context` + `mipi_dsi_dcs_read_multi()` style (as in nt35560) over the legacy `ctx->error` accumulation.
3. **Power-up before ID read is universal**: every driver that reads an ID does it in `drm_panel_funcs.prepare` — regulator_bulk_enable → reset toggle + delay → (optional unlock/key commands) → ID read → init sequence. None reads IDs at `probe()`; DSI LP transfers at probe are unreliable because the host may not be attached/prepared and the panel may be unpowered (on Qualcomm, also the continuous-clock / cmd-mode requirement).
4. **mipi_dsi_attach ordering**: probe ends with `drm_panel_add(&panel)` followed by `mipi_dsi_attach(dsi)` (newer drivers: `devm_mipi_dsi_attach(dev, dsi)`), with `drm_panel_remove()` rollback on attach failure. All DSI command traffic happens only later via the panel callbacks, never in probe. If init/ID-read needs the DSI host powered before `prepare` runs, set `panel.prepare_prev_first = true` (s6e8aa0 does; ilitek-ili9881c introduced `prepare_upstream_first`, now renamed `prepare_prev_first` — see raspberrypi/linux#4969 discussion).
5. **Mode source stays DT/match data**: even s6e8aa0 takes its display timing from the devicetree `display-timings`, not from the ID. A resolution-differing variant therefore needs the mode recorded per variant in the driver table (or DT override), because `get_modes` must report it before prepare() ever runs.

# (c) Qualcomm-specific "two panels share rails + reset, differ in resolution"

No such pattern exists in upstream `drivers/gpu/drm/panel/`. In the downstream Qualcomm world this is handled by the vendor `msm-dsi-panel` dtsi mechanism (`qcom,mdss-dsi-panel-status`, panel-select GPIO / "qcom,panel-detect"), which is explicitly non-upstream and not acceptable to maintainers. Upstream Qualcomm phone ports (postmarketOS/Lineage msm8916/sdm660 style) instead use one compatible per panel and DT-based selection; the DCS 0xDA/0xDB/0xDC ID read idiom appears only in the controllers above. Practical upstream-precedent for the R11s case (two possible panels, same regulators/reset, different resolution) is therefore a hybrid: the **panel-samsung-s6d7aa0 / hx8394 desc-table skeleton** combined with the **s6e8aa0 runtime ID read** to pick the table — i.e. a new driver that keeps a single compatible, reads 0xDA/0xDB/0xDC (or vendor 0x04) in `prepare()` after power/reset via `mipi_dsi_dcs_read_multi()`, maps the ID to a per-variant desc (mode + init), and fails `prepare()` with `-ENODEV`/`-EINVAL` if the ID matches no known variant or reads all-zero (per nt35560's `vendor == 0x00` check).

Key URLs:
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-samsung-s6e8aa0.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-samsung-s6e63m0.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-novatek-nt35560.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-novatek-nt35510.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-dsi-cm.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-sitronix-st7789v.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-samsung-s6d7aa0.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-himax-hx8394.c
- https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-boe-th101mb31ig002-28a.c
- https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/display/panel/panel-dsi-cm.yaml
- raspberrypi/linux PR #4969 (prepare_upstream_first → prepare_prev_first context): https://github.com/raspberrypi/linux/issues/4969

All paths verified against the local mainline checkout at /home/<user>/claude/r11/linux (v7.2.0-rc5); the same files exist in torvalds/linux master.