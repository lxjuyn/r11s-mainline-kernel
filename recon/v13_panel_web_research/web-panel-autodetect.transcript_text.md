All research
 was
 performed against the local
 upstream
 tree at /home
/lxj
/claude/r
11/linux (
Linux 7.
2.0-
rc5, i
.e. current main
line) plus web
 sources. Every quoted
 snippet below was verified
 by
 direct read of the
 file
 at that path.



# (a)
 Upstream
 drivers that read a
 DCS panel ID



Important negative result first
: **there
 is no `m
ipi_dsi_d
cs_get_panel_id
()` helper in upstream
** (
verified by grep of
 `
include/drm/
`, `include/video
/mipi_display.h
`, `drivers/g
pu/drm/d
rm_mipi_d
si.c`). Drivers
 use `m
ipi_dsi_d
cs_read()` /
 `mipi_d
si_dcs_read
_multi()` directly with
 either `MIPI
_D
CS_GET_DISPLAY_ID
` (0x
04) or
 the one-byte 
0xDA/0
xDB/0xDC
 reads. **Of
 the 13
6 files in `
drivers/gpu/d
rm/panel/
`, only ~8
 do
 any DSI read
 at all**, and
 only one merged driver
 actually selects a
 variant table from the
 ID.

##
 1
. panel-samsung
-s6e8
aa0 — THE
 canonical
 runtime variant selection driver

`drivers/g
pu/d
rm/panel/
panel-samsung-s
6e8aa
0.c`

URLs: https
://github
.com/torval
ds/linux/blob/master
/drivers/gpu/d
rm/panel/
panel-samsung-s
6e8aa
0.c — code
browser: https://
codebrowser.dev/linux
/linux/drivers/gpu
/drm/panel
/panel-samsung
-s6e8
aa0.c.html


- Single compatible
 `"samsung,s
6e8aa
0"`; variant
 tables
 keyed by ID:

```c

struct s6e
8aa0_variant
 { u8 version
; const
 s6e8
aa0_gamma_table
 *gamma_tables;
 };
static const
 struct s6e
8aa0_variant
 s6e8
aa0_variants
[] = {

    { .version
 =
 32,
  .gamma_tables
 = s6e
8aa0_gamma
_tables_v32
 },
    {
 .version = 
96, 
 .gamma_tables =
 s6e8
aa0_gamma_tables
_v96 },

    { .
version = 1
42, .
gamma_tables = s
6e8aa
0_gamma_tables_v
142 },

    { .
version = 2
10, .
gamma_tables = s
6e8aa
0_gamma_tables_v
142 },

};
```

- ID read
 (vendor cmd 
0xd1
, 3 bytes
) with strict failure
 policy:

```c
static
 void s6e
8aa0_read
_mtp_id(struct
 s6e8
aa0 *ctx
)
{

    u8 id
[3]; int
 ret, i;

    ret =
 s6e8
aa0_dcs
_read(ctx, 
0xd1,
 id, ARRAY_SIZE
(id));
   
 if (ret 
< 0 || ret
 < ARRAY_SIZE(id
) || id[
0] == 
0x00
) {
       
 dev_err(ctx->
dev, "read
 id failed\n");

        ctx->
error = -E
IO; return;

    }

    for (
i = 0
; i < ARRAY
_SIZE(s6e
8aa0_var
iants); ++i
)
        if
 (id[1
] == s6
e8aa0
_variants[i].
version) break;

    if (
i >= ARRAY_SIZE
(s6e8
aa0_variants
)) {
       
 dev_err(ctx->
dev, "unsupported
 display version %d
\n", id[
1]);
       
 ctx->error =
 -EINVAL; return
;      /* unknown
 ID
 = hard failure */

    }

    ctx->
variant = &s
6e8aa
0_variants[i
]; ctx->version
 = id
[1]; ctx
->id = id
[2];

}
```

- Called in `
prepare()` (
not probe): `
s6e8
aa0_prepare()`
 → `s6
e8aa0
_power_on()` (
regulator_bulk_enable
 vdd3/v
ci
, power_on_delay
, reset
 toggle, reset_delay
) → `
s6e8
aa0_set_sequence
()` → `s
6e8aa
0_read_mtp
_id()`
 → `s6
e8aa
0_panel_init()
`. On error,
 `prepare()` unw
inds via `s
6e
8aa0_un
prepare()`. Mode
/resolution still come
 from DT (`of
_get_videom
ode` + power
-on-delay/reset-delay
/init-delay, width
/height-mm),
 not from the ID
. Sets `ctx
->panel
.prepare_prev_first =
 true;` (
needs host pre-enabled
 before
 LP commands).


## 
2. panel-s
amsung-s6e
63m0
 — ID read with
 graceful fallback for unknown
 ID
`
drivers/gpu/d
rm/panel/
panel-samsung-s
6e63
m0.c`
 (frontends `
panel-samsung-s
6e63
m0-dsi
.c`, `-spi
.c`; URL
: https://github
.com/torval
ds/linux/blob/master
/drivers/gpu/d
rm/panel/
panel-samsung-s
6e63
m0.c)


- `prepare
()` → power_on
 → unlock keys
 (`MCS_LEVEL
_2
_KEY`/`
MCS
_MTP_KEY`
 = 0x
5
a 0x
5a) →
 `s6e
63m0
_check_lcd_type()`
 reading MCS_READ_ID
1/
2/3 (
transport-agnostic callbacks
, i.e.
 works
 over SPI or D
SI):

```c

switch (id2
) {
case
 S6E6
3M0_LCD
_ID_VALUE_M2
: ...; ctx
->elvss
_pulse = id3
; break;

case S6E
63M0
_LCD_ID_VALUE_SM
2: case S
6E6
3M0_LCD
_ID_VALUE_SM2
_1: ...
; break;

default:
   
 dev_info(ctx->
dev, "unknown
 LCD panel type %
02x\n
", id2);

    ctx->
elvss_pulse =
 0x1
6;   /*
 default, do NOT
 fail */

    break;

}
ctx
->lcd_type =
 id2;

```
Read transport
 error → returns error
 →
 `prepare()` fails
.
 Unknown-but-valid ID
 → continue
 with default parameters.


## 
3. panel-n
ovatek-
nt355
60 — modern
 `*_multi`
 API
 ID read (Sony
 panels
)
`drivers
/gpu/drm
/panel/panel
-novatek
-nt35
560.c
`
- Config
-per-compatible table (
Sony ACX4
24AKP
 480
x8
64 vs AC
X42
4AKM 
480x
854):

```c

struct nt35
5
60_config {
 const struct drm_display
_mode *vid_mode
;
                        const
 struct drm
_display_mode *cmd
_mode; };

static const struct of
_device_id nt3
5560
_of_match[] =
 {
    {
 .compatible = "
sony,ac
x424
akp", .
data = &son
y_acx4
24akp
_data },
   
 { .compatible =
 "sony,
acx42
4akm",
 .data = &
sony_acx
424ak
m_data },

};
```

- ID read uses
 modern API, called
 in
 `nt35
560_prepare
()` right after `
nt355
60_power_on
()` (regulator
 "vddi
" + reset):

```c

mipi_dsi
_dcs_read_multi
(dsi_ctx,
 NT355
60_DCS
_READ_ID1,
 &vendor, 
1);
m
ipi_dsi_d
cs_read_multi(d
si_ctx, NT
3556
0_DCS_READ
_ID2, &
version, 1
);
mipi
_dsi_dcs
_read_multi(dsi
_ctx, NT3
5560
_DCS_READ_ID
3, &panel
, 1);

if (vendor
 == 0x
00) {
 dsi_ctx->
accum_err = -
ENODEV; return
; }  /*
 all
-zero = not present
 */
val
 = (vendor <
< 8) |
 panel;
switch
 (val) {
 case DISPLAY_SONY
_ACX42
4AKP_ID
1...: log
; default: "
unknown vendor"; }

```

Unknown ID here is
 only logged (
informational), because
 variant selection is done
 by DT compatible instead
. This is the
 closest merged
 analog to "two
 panels
, same driver"
 — resolved via two
 compatibles, one per
 panel, with the
 ID read serving as
 sanity
-check.

##
 4
. panel-nov
atek-nt
3551
0 — 0
xDA/0xDB
/0xDC reads
, per-panel config
 tables

`drivers/g
pu/drm/
panel/panel-n
ovatek-
nt355
10.c`

```c

#define MCS
_CMD_READ_ID1
 0xDA

#define MCS_CMD_READ
_ID2 0
xDB
#define MCS
_CMD_READ_ID3
 0xDC

ret = mipi
_dsi_dcs
_read(dsi,
 MCS_CMD_READ_ID
1, &id
1, 1
); /* id2
,
 id3 same */

dev
_info(nt->dev
, "MTP
 ID manufacturer: %
02x version
: %02
x driver: %
02x\n
", ...);

```
Called inside
 `nt35
510_power
_on()` (reg
ulators + reset toggle
 +
 MTP read-param
/setting prelude
), i
.e. DSI
 traffic
 only after power-up
; the return value
 is ignored
 (logging only).
 Per
-panel variant data (
full mode + gamma
 + power tables)
 is selected by `
of_device
_id .data`:
 `hydis,h
va4
0wv1
`, `frida
,
frd40
0b25
025`,
 all under driver compatible
 `"
novatek,
nt355
10"`.
 This is the upstream
-idiomatic "
one controller, N
 panels, one file
" structure (document
ed struct `nt
3551
0_config`: width
/
height mm, `
drm_display_mode`,
 mode_flags, av
dd[], bt*
ctr[], gamma tables
).

## 
5. panel-d
si-cm —
 generic command-mode multi
-panel driver
`
drivers/gpu/d
rm/panel/
panel-dsi-c
m.c`; binding
:
 `Documentation/devic
etree/bindings
/display/panel/
panel-dsi-c
m.yaml`

- Reads DCS
_GET_ID1
/2/3
 in `dsic
m_power_on()`
 after hw reset +
 sleep-out
; exposed via sys
fs `
hw_revision`, not
 used to choose variant
. Resolution
/te_support come
 from per-compatible `
struct dsic_panel
_data` match data
:

```c
static
 const struct of_device
_id dsicm
_of_match[] =
 {
    {
 .compatible = "
tpo,taal
", .data =
 &taal
_data },          /*
 86
4x48
0 */
   
 { .compatible =
 "nokia,h
imalaya", .
data = &h
imalaya_data },
 /* 48
0
x864
 */
    {
 .compatible = "
motorola,droid
4-panel", .
data = &d
roid4_data },
 /* 54
0x96
0 */
};

```
-
 Probe: `dev
m_d
rm_panel_alloc`
 → `dsic
m_probe_of
` → `ds
icm
_hw_reset()` at
 probe (!), backlight
,
 `drm_panel_add
()`
 then `mipi
_dsi_attach()`
 with cleanup `err
_dsi_attach:
 drm_panel_remove(...)
`.

## 
6. Others with
 reads (not variant
-selection)
-
 `
panel-sitron
ix-st77
89v.c
`: reads `MI
PI_D
CS_GET_DISPLAY_ID
` (0x
04) in
 `st77
89v_check
_id()` from `
prepare()`;
 mismatch → `dev
_warn("Unrecognized
 panel IDs
")`, non-f
atal;
 skipped if SPI_NO
_RX.

- `panel-ed
p.c`: e
DP panel-id detection
 via EDID
 (`drm_edid
_get_panel_id()`
), not DSI
 —
 a different mechanism,
 not applicable to MI
PI DSI.

- `panel
-samsung-s6
e
3ha8/
ha2/ld
9040
`, `panel-n
ovatek-
nt355
3
2/36
672
a`, phone-era
 drivers (nt3
5
597,
 sofef00
,
 hx839
4, etc.):
 **zero ID reads
**;
 they do not autod
etect.

#
 (b)
 Structural idioms for
 a NEW merged panel
 driver


1. **Single
 file, single driver
, per-
variant desc tables selected
 by `of_device
_id .data`.
** The dominant upstream
 pattern for "same
 driver, several panels
" is one
 compatible string per panel
 variant,
 each mapping to a
 `const
 struct xxx_panel_desc
` with `{ mode
, init_sequence/init
_func, mode_flags
, format, lanes
, width
/height_mm }
`.
 Examples: `panel
-himax-hx
8394
.c` (6
 compatibles → 6
 des
cs), `panel
-samsung-s6
d
7aa0.c
` (3 panels
 on S6D
7AA
0 controller; `
init
_func`/`
off_func` +
 `panel_type`
 enum +
 per-panel `drm
_display
_mode` + `
mode_flags`
), `panel-bo
e-th10
1mb31
ig002
-28a
.c` (2
 compatibles, per-panel
 `init`
 callback + delays),
 `panel-bo
e-himax8
279d
.c`, `panel
-m
otorola-mot
.c`.
2
. **Runtime ID
-based selection exists upstream
 in exactly one merged
 driver
: panel-samsung
-s6
e8aa0
** (hard-f
ail on unknown
 ID: `-EINVAL
`; hard-fail
 on read
 failure: `-E
IO`). The soft
-fail variants (
log
-only): s6
e6
3m0 (
default params), nt
35
560/st
7789
v (warn only
). Modern new drivers
 should prefer the `
mipi
_dsi_multi_context
` + `m
ipi_dsi_d
cs_read_multi()`
 style (as in
 nt355
60) over
 the legacy `ctx
->error` accumulation
.
3.
 **
Power-up before ID
 read is universal**:
 every driver that reads
 an
 ID does it in
 `drm
_panel_funcs.prepare`
 — regulator_bulk_enable
 → reset toggle
 + delay → (
optional unlock/key commands
) → ID
 read → init sequence
. None reads IDs
 at `probe()`
;
 DSI LP transfers
 at
 probe are unreliable because
 the host may not
 be attached/pre
pared and the panel
 may be
 unpowered (on
 Qualcomm, also the
 continuous-clock / cmd
-mode requirement).

4. **m
ipi_dsi_attach
 ordering**: probe ends
 with `drm_panel
_add(&panel)`
 followed by `m
ipi
_dsi_attach(d
si)` (new
er drivers: `
devm_m
ipi_dsi_attach
(dev, dsi
)`), with `
drm_panel_remove
()` rollback on attach
 failure. All D
SI command
 traffic happens only later
 via the panel callbacks
,
 never in probe.
 If
 init/ID-read
 needs the DSI
 host powered
 before `prepare`
 runs, set `
panel.prepare_prev_first
 = true` (
s6e8
aa0 does;
 il
itek-ili9
88
1c introduced `
prepare_upstream
_first`, now renamed
 `prepare_prev_first
` — see rasp
berrypi/linux
#496
9 discussion).

5.
 **Mode source stays
 DT/match data
**:
 even s6e
8aa
0 takes its display
 timing from the dev
icetree `
display-timings
`, not from the
 ID
. A resolution-d
iffer
ing variant therefore needs
 the
 mode recorded per variant
 in
 the driver table (
or DT
 override), because `
get_modes` must
 report it before prepare
() ever runs.


#
 (c) Qualcomm
-specific "two panels
 share
 rails + reset,
 differ in resolution"


No such pattern
 exists in upstream `
drivers/gpu/d
rm/panel/
`. In the downstream
 Qualcomm world this is
 handled by the
 vendor `msm
-d
si-panel` d
tsi mechanism (`
qcom,
mdss-dsi
-panel-status`, panel
-select GPIO
 / "qcom
,panel
-detect"), which
 is explicitly non-up
stream and
 not acceptable to maintain
ers. Upstream
 Qualcomm
 phone ports (post
marketOS/Line
age msm89
16
/sdm66
0 style) instead
 use one
 compatible per panel and
 DT-based selection;
 the DCS 
0xDA/0
xDB/
0xDC ID read
 idiom appears only
 in the controllers
 above. Practical upstream
-precedent for
 the R11
s case (two
 possible
 panels, same regulators
/reset, different resolution
)
 is therefore a hybrid
: the
 **panel-samsung
-s6
d7aa0
 /
 hx839
4
 desc-table skeleton**
 combined
 with the **s
6e8aa
0 runtime ID read
**
 to pick the table
 — i.e.
 a new
 driver that keeps a
 single compatible, reads
 
0xDA/0
xDB/
0xDC (or
 vendor 0x
0
4) in `
prepare()`
 after power/reset via
 `mipi_d
si_dcs_read
_multi()`, maps
 the ID to a
 per-variant desc
 (mode + init
),
 and fails `prepare
()` with `-
ENODEV`/
`
-EINVAL` if
 the ID matches no
 known variant or reads
 all-zero (per
 nt355
60's `
vendor == 0
x00`
 check).

Key
 URLs:
-
 https://github.com
/torvalds
/linux/blob/master/drivers
/gpu/drm
/panel/panel
-samsung-s6
e8aa0
.c
- https
://github.com/t
orvalds/linux
/blob/master/drivers/g
pu/drm/
panel/panel-s
amsung-s6e
63m0
.c
- https
://github.com/t
orvalds/linux
/blob/master/drivers/g
pu/drm/
panel/panel-n
ovatek-
nt355
60.c

- https://github
.com/torval
ds/linux/blob/master
/drivers/gpu/d
rm/panel/
panel-novate
k-nt3
5510
.c
- https
://github.com/t
orvalds/linux
/blob/master/drivers/g
pu/drm/
panel/panel-d
si-cm.c

- https://
github.com/tor
valds/linux/blob
/master/drivers/gpu
/drm/panel
/panel-sit
ronix-st7
789v
.c
- https
://github.com/t
orvalds/linux
/blob/master/drivers/g
pu/drm/
panel/panel-s
amsung-s6d
7aa0.c

- https://
github.com/tor
valds/linux/blob
/master/drivers/gpu
/drm/panel
/panel-himax
-hx83
94.c

- https://github
.com/torval
ds/linux/blob/master
/drivers/gpu/d
rm/panel/
panel-boe-th
101mb
31ig0
02-2
8a.c

- https://github
.com/torval
ds/linux/blob/master
/Documentation/devic
et
ree/bindings/display
/panel/panel
-dsi-cm
.yaml
- rasp
berrypi/linux
 PR #49
6
9 (prepare_up
stream_first → prepare
_prev_first context
): https://github
.com/raspb
errypi/linux/issues
/496
9

All paths
 verified against the
 local mainline checkout
 at /
home/lxj
/claude/r
11/linux (
v7.2
.
0-rc5
); the same files
 exist
 in torvalds
/linux master
.