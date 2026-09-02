// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung SOFEG01_S 1080x2160 command-mode AMOLED panel (OPPO R11s / 17011).
 *
 * Init/timing data transcribed 1:1 from the stock OPPO 4.4 device tree:
 *   android_kernel_oppo_sdm660_source_d9391f88aa90/arch/arm64/boot/dts/
 *     vendor/qcom/dsi-panel-oppo17011samsung_sofeg01_1080p_cmd.dtsi
 * (node qcom,mdss_dsi_oppo17011samsung_sofeg01_s_1080p_cmd; panel-version
 * "SOFEG01_S", manufacture "samsung1024"), cross-checked against the stock
 * R11s DTB forensics in recon/R11S_PANEL_FORENSICS_20260829.md.
 *
 * Key facts from the stock panel node:
 *   - 1080x2160, 68x136 mm, 60 Hz, 24 bpp, burst mode, 4 lanes, DSI cmd mode
 *   - porches: HFP=112 HBP=96 HPW=20, VFP=20 VBP=4 VPW=2
 *   - reset sequence: high 5 ms, low 2 ms, high 12 ms
 *   - init-delay-us = 5000 (LP11 pre-init delay), lp11-init
 *   - DCS backlight, 16-bit (bl-dcs-16bit), min 1 / max 1023
 *   - ESD: DCS read 0x0a, expected value 0x9e
 *   - TE via TE pin, DCS tear-on command 0x35 0x00
 *
 * This is NOT the R11T S6E3FA3 panel (1080x1920): command set, resolution,
 * physical size, backlight depth and ESD signature all differ.
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

#define SOFEG01_BL_MAX		1023

struct sofeg01 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	struct regulator_bulk_data *supplies;
	enum drm_panel_orientation orientation;
};

static const struct regulator_bulk_data sofeg01_supplies[] = {
	{ .supply = "vddio" },
	{ .supply = "vdd" },
	{ .supply = "oledb" },
};

static inline struct sofeg01 *to_sofeg01(struct drm_panel *panel)
{
	return container_of(panel, struct sofeg01, panel);
}

static void sofeg01_reset(struct sofeg01 *ctx)
{
	/*
	 * Stock qcom,mdss-dsi-reset-sequence = <1 5>, <0 2>, <1 12>;
	 * leave reset high (run state).
	 */
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(2000, 3000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(12000, 13000);
}

static int sofeg01_dcs_write(struct sofeg01 *ctx, u8 type,
			     const u8 *data, size_t len, unsigned int delay_ms)
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

#define SOFEG01_DCS_WRITE(ctx, type, delay_ms, seq...) ({ \
	const u8 d[] = { seq }; \
	sofeg01_dcs_write(ctx, type, d, ARRAY_SIZE(d), delay_ms); \
})

static int sofeg01_on(struct sofeg01 *ctx)
{
	struct device *dev = &ctx->dsi->dev;
	u8 power_mode;
	int ret;

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/*
	 * Stock on-command sequence (dtsi qcom,mdss-dsi-on-command, all in
	 * dsi_lp_mode). MDSS wait fields are pre-command delays.
	 */

	/* 05 01 00 00 14 00 02 11 00: sleep out, 20 ms wait */
	msleep(20);
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				MIPI_DCS_EXIT_SLEEP_MODE);
	if (ret)
		return ret;

	/* 15 01 00 00 01 00 02 35 00: TE on (v-blank only) */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE_PARAM, 1,
				MIPI_DCS_SET_TEAR_ON,
				MIPI_DSI_DCS_TEAR_MODE_VBLANK);
	if (ret)
		return ret;

	/*
	 * Stock requires DCS long packets even for two-byte vendor writes
	 * (all vendor entries below use type 0x39 in the stock blob).
	 */

	/* FC 5A 5A: unlock */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xfc, 0x5a, 0x5a);
	if (ret)
		return ret;
	/* E8 64 08 0C */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xe8, 0x64, 0x08, 0x0c);
	if (ret)
		return ret;
	/* FC A5 A5: lock */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xfc, 0xa5, 0xa5);
	if (ret)
		return ret;

	/* F0 5A 5A: unlock MTP/gamma key */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xf0, 0x5a, 0x5a);
	if (ret)
		return ret;
	/* B0 01 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xb0, 0x01);
	if (ret)
		return ret;
	/* ED 04 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xed, 0x04);
	if (ret)
		return ret;
	/* F0 A5 A5: lock */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xf0, 0xa5, 0xa5);
	if (ret)
		return ret;

	/* F0 5A 5A: unlock again for ACL/LBR block */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xf0, 0x5a, 0x5a);
	if (ret)
		return ret;
	/* BC 01 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xbc, 0x01);
	if (ret)
		return ret;
	/* B0 01 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xb0, 0x01);
	if (ret)
		return ret;
	/* BC 12 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xbc, 0x12);
	if (ret)
		return ret;
	/* B0 2C */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xb0, 0x2c);
	if (ret)
		return ret;
	/* BC + 21-byte gamma/ACL data blob */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xbc,
				0xb4, 0x03, 0x05, 0x05, 0xff, 0x02, 0x00,
				0x00, 0xff, 0x00, 0xff, 0xff, 0xf0, 0x00,
				0xf0, 0xe0, 0xce, 0x0f, 0xff, 0xfa, 0xff);
	if (ret)
		return ret;
	/* B0 42 / BC 03: LBR/Skin Enable (stock annotated pair) */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xb0, 0x42);
	if (ret)
		return ret;
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xbc, 0x03);
	if (ret)
		return ret;
	/* B0 4B / BC 49 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xb0, 0x4b);
	if (ret)
		return ret;
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xbc, 0x49);
	if (ret)
		return ret;
	/* F0 A5 A5: final lock */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				0xf0, 0xa5, 0xa5);
	if (ret)
		return ret;

	/* 53 20: write CTRL display (backlight on, dimming on) */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE_PARAM, 1,
				MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x20);
	if (ret)
		return ret;
	/* 51 00 00: 16-bit DCS brightness = 0 */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_LONG_WRITE, 1,
				MIPI_DCS_SET_DISPLAY_BRIGHTNESS, 0x00, 0x00);
	if (ret)
		return ret;
	/* 55 00: CABC off */
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE_PARAM, 1,
				MIPI_DCS_WRITE_POWER_SAVE, 0x00);
	if (ret)
		return ret;

	/* 05 01 00 00 78 00 02 29 00: display on after 120 ms */
	msleep(120);
	ret = SOFEG01_DCS_WRITE(ctx, MIPI_DSI_DCS_SHORT_WRITE, 0,
				MIPI_DCS_SET_DISPLAY_ON);
	if (ret)
		return ret;

	/* Stock ESD check: DCS read 0x0a, expected 0x9e */
	ret = mipi_dsi_dcs_read(ctx->dsi, 0x0a, &power_mode, 1);
	if (ret < 0)
		dev_warn(dev, "failed to read power mode: %d\n", ret);
	else if (power_mode != 0x9e)
		dev_warn(dev, "power mode: 0x%02x (expected 0x9e)\n",
			 power_mode);
	else
		dev_info(dev, "power mode: 0x%02x (expected 0x9e) OK\n",
			 power_mode);

	return 0;
}

static int sofeg01_off(struct sofeg01 *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	/* Stock off-command state = dsi_hs_mode (no LPM). */
	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	/* Stock: display off with 40 ms pre-delay, sleep in after 120 ms. */
	mipi_dsi_msleep(&dsi_ctx, 40);
	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 120);
	mipi_dsi_dcs_enter_sleep_mode_multi(&dsi_ctx);

	return dsi_ctx.accum_err;
}

static int sofeg01_prepare(struct drm_panel *panel)
{
	struct sofeg01 *ctx = to_sofeg01(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(sofeg01_supplies), ctx->supplies);
	if (ret)
		return ret;

	/*
	 * Stock lp11-init + init-delay-us = 5000: prepare_prev_first puts the
	 * host in LP11 before this delay.
	 */
	usleep_range(5000, 6000);
	sofeg01_reset(ctx);

	ret = sofeg01_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		gpiod_set_value_cansleep(ctx->reset_gpio, 0);
		regulator_bulk_disable(ARRAY_SIZE(sofeg01_supplies), ctx->supplies);
		return ret;
	}

	return 0;
}

static int sofeg01_unprepare(struct drm_panel *panel)
{
	struct sofeg01 *ctx = to_sofeg01(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = sofeg01_off(ctx);
	if (ret < 0)
		dev_err(dev, "Failed to un-initialize panel: %d\n", ret);

	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	regulator_bulk_disable(ARRAY_SIZE(sofeg01_supplies), ctx->supplies);

	return 0;
}

/*
 * Stock porch: HFP=112 HBP=96 HPW=20, VFP=20 VBP=4 VPW=2 @ 60 Hz,
 * physical size 68x136 mm.
 */
static const struct drm_display_mode sofeg01_mode = {
	.clock = (1080 + 112 + 20 + 96) * (2160 + 20 + 2 + 4) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 112,
	.hsync_end = 1080 + 112 + 20,
	.htotal = 1080 + 112 + 20 + 96,
	.vdisplay = 2160,
	.vsync_start = 2160 + 20,
	.vsync_end = 2160 + 20 + 2,
	.vtotal = 2160 + 20 + 2 + 4,
	.width_mm = 68,
	.height_mm = 136,
	.type = DRM_MODE_TYPE_DRIVER,
};

static int sofeg01_get_modes(struct drm_panel *panel,
			     struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &sofeg01_mode);
}

static enum drm_panel_orientation sofeg01_get_orientation(struct drm_panel *panel)
{
	struct sofeg01 *ctx = to_sofeg01(panel);

	return ctx->orientation;
}

static const struct drm_panel_funcs sofeg01_panel_funcs = {
	.prepare = sofeg01_prepare,
	.unprepare = sofeg01_unprepare,
	.get_modes = sofeg01_get_modes,
	.get_orientation = sofeg01_get_orientation,
};

static int sofeg01_bl_update_status(struct backlight_device *bl)
{
	struct sofeg01 *ctx = bl_get_data(bl);
	u32 brightness = backlight_get_brightness(bl);
	u8 payload[3] = {
		MIPI_DCS_SET_DISPLAY_BRIGHTNESS,
		brightness >> 8,
		brightness & 0xff,
	};

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/* Stock backlight is 16-bit DCS (qcom,mdss-dsi-bl-dcs-16bit). */
	return sofeg01_dcs_write(ctx, MIPI_DSI_DCS_LONG_WRITE, payload,
				 sizeof(payload), 0);
}

static const struct backlight_ops sofeg01_bl_ops = {
	.update_status = sofeg01_bl_update_status,
};

static struct backlight_device *sofeg01_create_backlight(struct sofeg01 *ctx)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	struct device *dev = &dsi->dev;
	const struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.brightness = 512,
		.max_brightness = SOFEG01_BL_MAX,
	};

	return devm_backlight_device_register(dev, dev_name(dev), dev, ctx,
					      &sofeg01_bl_ops, &props);
}

/*
 * R11s panel auto-detect passthrough: the ABL names the attached panel in
 * mdss_mdp.panel= (downstream LK contract; the string is visible on any
 * stock boot's cmdline).  Only the named panel may attach — if a second
 * panel attached as well, its mipi_dsi_attach() would overwrite the DSI
 * host's virtual-channel configuration and break the selected one.  With
 * no ABL hint, default to the VC0 panel (panel@0).
 */
static bool sofeg01_cmdline_selected(struct mipi_dsi_device *dsi)
{
	const char *p = strstr(saved_command_line, "mdss_mdp.panel=");
	const char *val, *end;
	const char *token = "sofeg01";

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

static int sofeg01_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct sofeg01 *ctx;
	int ret;

	if (!sofeg01_cmdline_selected(dsi)) {
		dev_info(dev,
			 "not the ABL-selected panel (mdss_mdp.panel=), skipping\n");
		return -ENODEV;
	}
	dev_info(dev, "R11s panel autodetect: selected by ABL cmdline\n");

	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	ret = devm_regulator_bulk_get_const(dev, ARRAY_SIZE(sofeg01_supplies),
					    sofeg01_supplies, &ctx->supplies);
	if (ret) {
		/*
		 * devm_regulator_bulk_get_const() stops at the first failing
		 * supply, so log the errno of every rail individually to make
		 * on-device supply debugging unambiguous.
		 */
		for (int i = 0; i < ARRAY_SIZE(sofeg01_supplies); i++) {
			struct regulator *r;

			r = regulator_get(dev, sofeg01_supplies[i].supply);
			dev_warn(dev, "supply %s: %ld\n",
				 sofeg01_supplies[i].supply,
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

	drm_panel_init(&ctx->panel, dev, &sofeg01_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);
	ctx->panel.prepare_prev_first = true;

	ctx->panel.backlight = sofeg01_create_backlight(ctx);
	if (IS_ERR(ctx->panel.backlight))
		return dev_err_probe(dev, PTR_ERR(ctx->panel.backlight),
				     "Failed to create backlight\n");

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		drm_panel_remove(&ctx->panel);
		return dev_err_probe(dev, ret, "Failed to attach to DSI host\n");
	}

	return 0;
}

static void sofeg01_remove(struct mipi_dsi_device *dsi)
{
	struct sofeg01 *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n", ret);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id sofeg01_of_match[] = {
	{ .compatible = "samsung,sofeg01-s" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, sofeg01_of_match);

static struct mipi_dsi_driver sofeg01_driver = {
	.probe = sofeg01_probe,
	.remove = sofeg01_remove,
	.driver = {
		.name = "panel-samsung-sofeg01-s",
		.of_match_table = sofeg01_of_match,
	},
};
module_mipi_dsi_driver(sofeg01_driver);

MODULE_DESCRIPTION("DRM driver for Samsung SOFEG01_S 1080x2160 command mode DSI panel (OPPO R11s)");
MODULE_LICENSE("GPL");
