// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung AMS596W401 1080x2280 command-mode AMOLED panel
 * (OPPO R11s / 17011 secondary manufacturing variant).
 *
 * Init/timing data transcribed 1:1 from the stock OPPO 4.4 device tree:
 *   android_kernel_oppo_sdm660_source_d9391f88aa90/arch/arm64/boot/dts/
 *     vendor/qcom/dsi-panel-oppo17011samsung_ams596w401_1080_2280_cmd.dtsi
 * (node qcom,mdss_dsi_oppo17011samsung_ams596w401_1080_2280_cmd;
 * panel-version "SOFEG01_S-QC01", manufacture "samsung1024").
 *
 * Why this driver exists (v9 "full panel set" scope): the stock 17011
 * kernel build compiles in exactly two R11s panel tables - sofeg01_s
 * (primary, shipped on the device whose DTB was forensed) and this
 * ams596w401 variant (stock 17011.dtsi #include chain; the factory boot
 * kernel is DT-data-driven MDSS so panel names live in the ABL-supplied
 * DTB, not in kernel .rodata - see v9 factory-boot reverse engineering).
 *
 * Key facts from the stock panel node (line numbers of the dtsi above):
 *   - 1080x2280, 68x144 mm, 60 Hz, 24 bpp, burst mode, 4 lanes, cmd mode
 *   - porches: HFP=80 HBP=52 HPW=20, VFP=20 VBP=16 VPW=4   (L31-37)
 *   - reset sequence: high 5 ms, low 2 ms, high 12 ms       (L102)
 *   - init-delay-us = 5000 (LP11 pre-init delay), lp11-init (L100-101)
 *   - DCS backlight, 16-bit (bl-dcs-16bit), min 1 / max 1023 (L93-99)
 *   - ESD: DCS read 0x0a, expected value 0x9C (not 0x9e!)   (L108-110)
 *   - TE via TE pin, DCS tear-on command 0x35 0x00          (L87-90)
 *
 * Probe failures are graceful (dev_err_probe / -EPROBE_DEFER friendly):
 * if this variant is not the mounted panel, or the DSI host is already
 * bound to the primary sofeg01_s panel, attach simply fails with an
 * error and boot continues. Never blocks boot.
 */

#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

#define AMS596W401_BL_MAX	1023

struct ams596w401 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	struct regulator_bulk_data *supplies;
	enum drm_panel_orientation orientation;
};

static const struct regulator_bulk_data ams596w401_supplies[] = {
	{ .supply = "vddio" },
	{ .supply = "vdd" },
	{ .supply = "oledb" },
};

static inline struct ams596w401 *to_ams596w401(struct drm_panel *panel)
{
	return container_of(panel, struct ams596w401, panel);
}

static void ams596w401_reset(struct ams596w401 *ctx)
{
	/*
	 * Stock qcom,mdss-dsi-reset-sequence = <1 5>, <0 2>, <1 12>;
	 * leave reset high (run state). Same physical reset wiring as
	 * the primary sofeg01_s panel (same reset GPIO on the board).
	 */
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(2000, 3000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(12000, 13000);
}

static int ams596w401_dcs_write(struct ams596w401 *ctx, u8 type,
				const u8 *data, size_t len,
				unsigned int delay_ms)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct mipi_dsi_msg msg = {
		.channel = dsi->channel,
		.type = type,
		.flags = dsi->mode_flags & MIPI_DSI_MODE_LPM ?
			 MIPI_DSI_MSG_USE_LPM : 0,
		.tx_len = len,
		.tx_buf = data,
	};
	ssize_t ret;

	if (!dsi->host->ops || !dsi->host->ops->transfer)
		return -ENOSYS;

	ret = dsi->host->ops->transfer(dsi->host, &msg);
	if (ret < 0)
		return ret;

	if (delay_ms)
		msleep(delay_ms);

	return 0;
}

#define AMS596W401_DCS_WRITE(ctx, type, delay_ms, seq...) ({ \
	const u8 d[] = { seq }; \
	ams596w401_dcs_write(ctx, type, d, ARRAY_SIZE(d), delay_ms); \
})

static int ams596w401_on(struct ams596w401 *ctx)
{
	struct device *dev = &ctx->dsi->dev;
	u8 power_mode;
	int ret;

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/*
	 * Stock on-command sequence (dtsi qcom,mdss-dsi-on-command, all
	 * dsi_lp_mode). MDSS header "wait" field is a pre-command delay.
	 */

	/* 05 01 00 00 0A 00 02 11 00: sleep out, 10 ms wait */
	msleep(10);
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				   MIPI_DCS_EXIT_SLEEP_MODE);
	if (ret)
		return ret;

	/* 15 01 00 00 01 00 02 35 00: TE on (v-blank only) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE_PARAM, 1,
				   MIPI_DCS_SET_TEAR_ON,
				   MIPI_DSI_DCS_TEAR_MODE_VBLANK);
	if (ret)
		return ret;

	/*
	 * Stock uses DCS long packets (type 0x39) for all vendor writes,
	 * including two-byte ones; transcribe the same way.
	 */

	/* F0 5A 5A: unlock */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xf0, 0x5a, 0x5a);
	if (ret)
		return ret;
	/* B0 07 */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x07);
	if (ret)
		return ret;
	/* B6 12 */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb6, 0x12);
	if (ret)
		return ret;

	/* 53 20: write CTRL display (backlight on, dimming on) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x20);
	if (ret)
		return ret;
	/* 38 00: stock vendor command (image function), transcribed as-is */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0x38, 0x00);
	if (ret)
		return ret;
	/* 51 00 00: 16-bit DCS brightness = 0 */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
				   0x00, 0x00);
	if (ret)
		return ret;
	/* F7 03: stock vendor command, transcribed as-is */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xf7, 0x03);
	if (ret)
		return ret;
	/*
	 * E2 00 85: seed/CRC control. Stock comment:
	 * 0x41 = Seed on + CRC off; 0x85 = Seed on + CRC on.
	 */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2, 0x00, 0x85);
	if (ret)
		return ret;
	/* B0 2C: select CRC LUT register page (stock comment) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x2c);
	if (ret)
		return ret;
	/* E2 + 22-byte gamma/CRC-LUT data blob, transcribed byte-for-byte */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2,
				   0xb0, 0x03, 0x05, 0x04, 0xff, 0x00,
				   0x00, 0x00, 0xff, 0x00, 0xff, 0xff,
				   0xf2, 0x00, 0xf2, 0xe4, 0xdb, 0x14,
				   0xfc, 0xfd, 0xff);
	if (ret)
		return ret;
	/* B0 49: LBR Enable (stock comment) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x49);
	if (ret)
		return ret;
	/* E2 00: LBR off (stock comment: 0x00 = off, 0x01 = on) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2, 0x00);
	if (ret)
		return ret;
	/* B0 4A */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x4a);
	if (ret)
		return ret;
	/* E2 00: stock comment: 0xFF = 255(max), 0x00 = 0(min) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2, 0x00);
	if (ret)
		return ret;
	/* B0 4B: SKIN Enable (stock comment) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x4b);
	if (ret)
		return ret;
	/* E2 01: Skin on (stock comment: 0x00 = off, 0x01 = on) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2, 0x01);
	if (ret)
		return ret;
	/* B0 4D */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x4d);
	if (ret)
		return ret;
	/* E2 49: stock comment: 0x01 = 128(max), 0x80 = 1(min) */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xe2, 0x49);
	if (ret)
		return ret;

	/* F0 A5 A5: final lock, 120 ms wait before (stock 0x78) */
	msleep(120);
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xf0, 0xa5, 0xa5);
	if (ret)
		return ret;

	/* 05 01 00 00 05 00 02 29 00: display on after 5 ms */
	msleep(5);
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				   MIPI_DCS_SET_DISPLAY_ON);
	if (ret)
		return ret;

	/* Stock ESD check: DCS read 0x0a, expected 0x9C (this variant). */
	ret = mipi_dsi_dcs_read(ctx->dsi, 0x0a, &power_mode, 1);
	if (ret < 0)
		dev_warn(dev, "failed to read power mode: %d\n", ret);
	else if (power_mode != 0x9c)
		dev_warn(dev, "power mode: 0x%02x (expected 0x9c)\n",
			 power_mode);
	else
		dev_info(dev, "power mode: 0x%02x (expected 0x9c) OK\n",
			 power_mode);

	return 0;
}

static int ams596w401_off(struct ams596w401 *ctx)
{
	struct device *dev = &ctx->dsi->dev;
	int ret;

	/* Stock off-command state = dsi_hs_mode (no LPM). */
	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	/*
	 * Stock off-command sequence: unlock, B0 07, B6 22, lock,
	 * display off (40 ms pre-wait), sleep in (120 ms pre-wait).
	 */
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xf0, 0x5a, 0x5a);
	if (ret)
		return ret;
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb0, 0x07);
	if (ret)
		return ret;
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xb6, 0x22);
	if (ret)
		return ret;
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				   0xf0, 0xa5, 0xa5);
	if (ret)
		return ret;

	msleep(40);
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				   MIPI_DCS_SET_DISPLAY_OFF);
	if (ret)
		return ret;

	msleep(120);
	ret = AMS596W401_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				   MIPI_DCS_ENTER_SLEEP_MODE);
	if (ret)
		dev_warn(dev, "sleep-in failed: %d\n", ret);

	return 0;
}

static int ams596w401_prepare(struct drm_panel *panel)
{
	struct ams596w401 *ctx = to_ams596w401(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(ams596w401_supplies),
				    ctx->supplies);
	if (ret)
		return ret;

	/*
	 * Stock lp11-init + init-delay-us = 5000: prepare_prev_first puts
	 * the host in LP11 before this delay.
	 */
	usleep_range(5000, 6000);
	ams596w401_reset(ctx);

	ret = ams596w401_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		gpiod_set_value_cansleep(ctx->reset_gpio, 0);
		regulator_bulk_disable(ARRAY_SIZE(ams596w401_supplies),
				       ctx->supplies);
		return ret;
	}

	return 0;
}

static int ams596w401_unprepare(struct drm_panel *panel)
{
	struct ams596w401 *ctx = to_ams596w401(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = ams596w401_off(ctx);
	if (ret < 0)
		dev_err(dev, "Failed to un-initialize panel: %d\n", ret);

	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	regulator_bulk_disable(ARRAY_SIZE(ams596w401_supplies), ctx->supplies);

	return 0;
}

/*
 * Stock porch: HFP=80 HBP=52 HPW=20, VFP=20 VBP=16 VPW=4 @ 60 Hz,
 * physical size 68x144 mm (dtsi physical-width/height dimensions).
 */
static const struct drm_display_mode ams596w401_mode = {
	.clock = (1080 + 80 + 20 + 52) * (2280 + 20 + 4 + 16) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 80,
	.hsync_end = 1080 + 80 + 20,
	.htotal = 1080 + 80 + 20 + 52,
	.vdisplay = 2280,
	.vsync_start = 2280 + 20,
	.vsync_end = 2280 + 20 + 4,
	.vtotal = 2280 + 20 + 4 + 16,
	.width_mm = 68,
	.height_mm = 144,
	.type = DRM_MODE_TYPE_DRIVER,
};

static int ams596w401_get_modes(struct drm_panel *panel,
				struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector,
						    &ams596w401_mode);
}

static enum drm_panel_orientation
ams596w401_get_orientation(struct drm_panel *panel)
{
	struct ams596w401 *ctx = to_ams596w401(panel);

	return ctx->orientation;
}

static const struct drm_panel_funcs ams596w401_panel_funcs = {
	.prepare = ams596w401_prepare,
	.unprepare = ams596w401_unprepare,
	.get_modes = ams596w401_get_modes,
	.get_orientation = ams596w401_get_orientation,
};

static int ams596w401_bl_update_status(struct backlight_device *bl)
{
	struct ams596w401 *ctx = bl_get_data(bl);
	u32 brightness = backlight_get_brightness(bl);
	u8 payload[3] = {
		MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
		brightness >> 8,
		brightness & 0xff,
	};

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/* Stock backlight is 16-bit DCS (qcom,mdss-dsi-bl-dcs-16bit). */
	return ams596w401_dcs_write(ctx, MIPI_DSI_DCS_LONG_WRITE, payload,
				    sizeof(payload), 0);
}

static const struct backlight_ops ams596w401_bl_ops = {
	.update_status = ams596w401_bl_update_status,
};

static struct backlight_device *
ams596w401_create_backlight(struct ams596w401 *ctx)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct device *dev = &dsi->dev;
	const struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.brightness = 512,
		.max_brightness = AMS596W401_BL_MAX,
	};

	return devm_backlight_device_register(dev, dev_name(dev), dev, ctx,
					      &ams596w401_bl_ops, &props);
}

/*
 * R11s panel auto-detect passthrough: see the comment above
 * sofeg01_cmdline_selected() in panel-samsung-sofeg01-s.c for the rationale
 * (only the ABL-named panel may attach, or the DSI host's virtual-channel
 * configuration gets clobbered).  With no ABL hint this VC1 panel never
 * attaches (the default is the VC0 panel@0).
 */
static bool ams596w401_cmdline_selected(struct mipi_dsi_device *dsi)
{
	const char *p = strstr(saved_command_line, "mdss_mdp.panel=");
	const char *val, *end;
	const char *token = "ams596";

	if (!p)
		return dsi->channel == 0;

	val = p + strlen("mdss_mdp.panel=");
	end = strchr(val, ' ');
	if (!end)
		end = val + strlen(val);

	for (; val + strlen(token) <= end; val++)
		if (!strncmp(val, token, strlen(token)))
			return true;

	return false;
}

static int ams596w401_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct ams596w401 *ctx;
	int ret;

	if (!ams596w401_cmdline_selected(dsi)) {
		dev_info(dev,
			 "not the ABL-selected panel (mdss_mdp.panel=), skipping\n");
		return -ENODEV;
	}
	dev_info(dev, "R11s panel autodetect: selected by ABL cmdline\n");

	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	ret = devm_regulator_bulk_get_const(dev,
					    ARRAY_SIZE(ams596w401_supplies),
					    ams596w401_supplies,
					    &ctx->supplies);
	if (ret) {
		/*
		 * devm_regulator_bulk_get_const() stops at the first failing
		 * supply, so log the errno of every rail individually to make
		 * on-device supply debugging unambiguous.
		 */
		for (int i = 0; i < ARRAY_SIZE(ams596w401_supplies); i++) {
			struct regulator *r;

			r = regulator_get(dev, ams596w401_supplies[i].supply);
			dev_warn(dev, "supply %s: %ld\n",
				 ams596w401_supplies[i].supply,
				 IS_ERR(r) ? PTR_ERR(r) : 0);
			if (!IS_ERR(r))
				regulator_put(r);
		}
		return dev_err_probe(dev, ret, "Failed to get regulators\n");
	}

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	ret = of_drm_get_panel_orientation(dev->of_node, &ctx->orientation);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get orientation\n");

	/* Stock: 4 lanes, 24 bpp, burst mode, DSI command mode. */
	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	/*
	 * Stock is dsi_cmd_mode. Keep non-continuous clock + LPM.
	 * Do not set MIPI_DSI_MODE_VIDEO.
	 */
	dsi->mode_flags = MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_LPM;

	drm_panel_init(&ctx->panel, dev, &ams596w401_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);
	ctx->panel.prepare_prev_first = true;

	ctx->panel.backlight = ams596w401_create_backlight(ctx);
	if (IS_ERR(ctx->panel.backlight))
		return dev_err_probe(dev, PTR_ERR(ctx->panel.backlight),
				     "Failed to create backlight\n");

	drm_panel_add(&ctx->panel);

	/*
	 * Graceful-failure contract: on this board the primary sofeg01_s
	 * panel normally owns the DSI host. If attach fails (host already
	 * bound / component_add -EEXIST / hardware absent), report and
	 * unwind - never panic, never block boot.
	 */
	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		drm_panel_remove(&ctx->panel);
		return dev_err_probe(dev, ret, "Failed to attach to DSI host\n");
	}

	return 0;
}

static void ams596w401_remove(struct mipi_dsi_device *dsi)
{
	struct ams596w401 *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n",
			ret);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id ams596w401_of_match[] = {
	{ .compatible = "samsung,ams596w401" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ams596w401_of_match);

static struct mipi_dsi_driver ams596w401_driver = {
	.probe = ams596w401_probe,
	.remove = ams596w401_remove,
	.driver = {
		.name = "panel-samsung-ams596w401",
		.of_match_table = ams596w401_of_match,
	},
};
module_mipi_dsi_driver(ams596w401_driver);

MODULE_DESCRIPTION("DRM driver for Samsung AMS596W401 1080x2280 command mode DSI panel (OPPO R11s 17011 variant)");
MODULE_LICENSE("GPL");
