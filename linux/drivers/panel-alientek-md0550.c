// SPDX-License-Identifier: GPL-2.0-only
/*
 * Alientek ATK-MD0550 1080p MIPI module (Himax HX8399).
 * Panel timings and DCS commands are from the Alientek RK3588 v1.2 SDK's
 * rk3588-atk-lcds.dtsi, ATK_LCD_TYPE_MIPI_TX0_5P5_1080X1920.
 */
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/seq_file.h>

#include <drm/drm_connector.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <video/mipi_display.h>

struct md0550 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset;
	struct regulator *power;
	struct mutex lock; /* Serializes diagnostics with panel power transitions. */
	struct dentry *debugfs;
	bool enabled;
};

static inline struct md0550 *to_md0550(struct drm_panel *panel)
{
	return container_of(panel, struct md0550, panel);
}

/* Reading the DSI error counter clears it; this is an on-demand diagnostic. */
static int md0550_status_show(struct seq_file *s, void *unused)
{
	struct md0550 *priv = s->private;
	static const struct {
		const char *name;
		u8 command;
		u8 length;
	} queries[] = {
		{ "display-id", MIPI_DCS_GET_DISPLAY_ID, 3 },
		{ "power", MIPI_DCS_GET_POWER_MODE, 1 },
		{ "pixel-format", MIPI_DCS_GET_PIXEL_FORMAT, 1 },
		{ "self-diagnostic", MIPI_DCS_GET_DIAGNOSTIC_RESULT, 1 },
		{ "status", MIPI_DCS_GET_DISPLAY_STATUS, 4 },
		{ "red", MIPI_DCS_GET_RED_CHANNEL, 1 },
		{ "green", MIPI_DCS_GET_GREEN_CHANNEL, 1 },
		{ "blue", MIPI_DCS_GET_BLUE_CHANNEL, 1 },
		{ "scanline-1", MIPI_DCS_GET_SCANLINE, 2 },
		{ "scanline-2", MIPI_DCS_GET_SCANLINE, 2 },
		{ "dsi-errors-1", MIPI_DCS_GET_ERROR_COUNT_ON_DSI, 1 },
		{ "dsi-errors-2", MIPI_DCS_GET_ERROR_COUNT_ON_DSI, 1 },
	};
	u8 data[4];
	unsigned int i;
	ssize_t ret;

	mutex_lock(&priv->lock);
	if (!priv->enabled) {
		ret = -ENODEV;
		goto out;
	}

	/* The HX8399 resets its maximum return packet size to one byte. */
	ret = mipi_dsi_set_maximum_return_packet_size(priv->dsi, sizeof(data));
	if (ret < 0)
		goto out;

	for (i = 0; i < ARRAY_SIZE(queries); i++) {
		memset(data, 0, sizeof(data));
		ret = mipi_dsi_dcs_read(priv->dsi, queries[i].command,
					data, queries[i].length);
		if (ret != queries[i].length) {
			if (ret >= 0)
				ret = -EIO;
			goto out;
		}
		seq_printf(s, "%s: %*ph\n", queries[i].name,
			   queries[i].length, data);
		usleep_range(5000, 6000);
	}
	ret = 0;
out:
	mutex_unlock(&priv->lock);
	return ret;
}
DEFINE_SHOW_ATTRIBUTE(md0550_status);

static void md0550_init_sequence(struct mipi_dsi_multi_context *ctx)
{
	mipi_dsi_dcs_write_seq_multi(ctx, 0xb9, 0xff, 0x83, 0x99);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd2, 0x77);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xcc, 0x04);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xb1, 0x02, 0x04, 0x74, 0x94, 0x01, 0x32, 0x33,
				     0x11, 0x11, 0xab, 0x4d, 0x56, 0x73, 0x02, 0x02);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xb2, 0x00, 0x80, 0x80, 0xae, 0x05, 0x07, 0x5a,
				     0x11, 0x00, 0x00, 0x10, 0x1e, 0x70, 0x03, 0xd4);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xb4, 0x00, 0xff, 0x02, 0xc0, 0x02, 0xc0, 0x00,
				     0x00, 0x08, 0x00, 0x04, 0x06, 0x00, 0x32, 0x04,
				     0x0a, 0x08, 0x21, 0x03, 0x01, 0x00, 0x0f, 0xb8,
				     0x8b, 0x02, 0xc0, 0x02, 0xc0, 0x00, 0x00, 0x08,
				     0x00, 0x04, 0x06, 0x00, 0x32, 0x04, 0x0a, 0x08,
				     0x01, 0x00, 0x0f, 0xb8, 0x01);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06,
				     0x00, 0x00, 0x10, 0x04, 0x00, 0x04, 0x00, 0x00,
				     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
				     0x01, 0x00, 0x05, 0x05, 0x07, 0x00, 0x00, 0x00,
				     0x05, 0x40);
	mipi_dsi_msleep(ctx, 5);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd5, 0x18, 0x18, 0x19, 0x19, 0x18, 0x18, 0x21,
				     0x20, 0x01, 0x00, 0x07, 0x06, 0x05, 0x04, 0x03,
				     0x02, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x2f,
				     0x2f, 0x30, 0x30, 0x31, 0x31, 0x18, 0x18, 0x18,
				     0x18);
	mipi_dsi_msleep(ctx, 5);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd6, 0x18, 0x18, 0x19, 0x19, 0x40, 0x40, 0x20,
				     0x21, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00,
				     0x01, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x2f,
				     0x2f, 0x30, 0x30, 0x31, 0x31, 0x40, 0x40, 0x40,
				     0x40);
	mipi_dsi_msleep(ctx, 5);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd8, 0xa2, 0xaa, 0x02, 0xa0, 0xa2, 0xa8, 0x02,
				     0xa0, 0xb0, 0x00, 0x00, 0x00, 0xb0, 0x00, 0x00,
				     0x00);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xbd, 0x01);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd8, 0xb0, 0x00, 0x00, 0x00, 0xb0, 0x00, 0x00,
				     0x00, 0xe2, 0xaa, 0x03, 0xf0, 0xe2, 0xaa, 0x03,
				     0xf0);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xbd, 0x02);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xd8, 0xe2, 0xaa, 0x03, 0xf0, 0xe2, 0xaa, 0x03,
				     0xf0);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xbd, 0x00);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xb6, 0x8d, 0x8d);
	mipi_dsi_dcs_write_seq_multi(ctx, 0xe0, 0x00, 0x0e, 0x19, 0x13, 0x2e, 0x39, 0x48,
				     0x44, 0x4d, 0x57, 0x5f, 0x66, 0x6c, 0x76, 0x7f,
				     0x85, 0x8a, 0x95, 0x9a, 0xa4, 0x9b, 0xab, 0xb0,
				     0x5c, 0x58, 0x64, 0x77, 0x00, 0x0e, 0x19, 0x13,
				     0x2e, 0x39, 0x48, 0x44, 0x4d, 0x57, 0x5f, 0x66,
				     0x6c, 0x76, 0x7f, 0x85, 0x8a, 0x95, 0x9a, 0xa4,
				     0x9b, 0xab, 0xb0, 0x5c, 0x58, 0x64, 0x77);
	mipi_dsi_msleep(ctx, 5);
	mipi_dsi_dcs_exit_sleep_mode_multi(ctx);
	mipi_dsi_msleep(ctx, 200);
	mipi_dsi_dcs_set_display_on_multi(ctx);
	mipi_dsi_msleep(ctx, 255);
}

static int md0550_prepare(struct drm_panel *panel)
{
	struct md0550 *priv = to_md0550(panel);
	int ret;

	ret = regulator_enable(priv->power);
	if (ret)
		return ret;

	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(priv->reset, 1);
	msleep(100);
	gpiod_set_value_cansleep(priv->reset, 0);
	msleep(80);

	return 0;
}

static int md0550_enable(struct drm_panel *panel)
{
	struct md0550 *priv = to_md0550(panel);
	struct mipi_dsi_multi_context ctx = { .dsi = priv->dsi };

	/* HX8399 accepts initialization while the upstream bridge streams video. */
	mutex_lock(&priv->lock);
	md0550_init_sequence(&ctx);
	priv->enabled = !ctx.accum_err;
	mutex_unlock(&priv->lock);

	return ctx.accum_err;
}

static int md0550_disable(struct drm_panel *panel)
{
	struct md0550 *priv = to_md0550(panel);
	struct mipi_dsi_multi_context ctx = { .dsi = priv->dsi };

	mutex_lock(&priv->lock);
	priv->enabled = false;
	mipi_dsi_dcs_set_display_off_multi(&ctx);
	mipi_dsi_msleep(&ctx, 50);
	mipi_dsi_dcs_enter_sleep_mode_multi(&ctx);
	mipi_dsi_msleep(&ctx, 200);
	mutex_unlock(&priv->lock);

	return ctx.accum_err;
}

static int md0550_unprepare(struct drm_panel *panel)
{
	struct md0550 *priv = to_md0550(panel);
	int ret;

	gpiod_set_value_cansleep(priv->reset, 1);
	ret = regulator_disable(priv->power);
	usleep_range(10000, 11000);

	return ret;
}

static const struct drm_display_mode md0550_mode = {
	/* Keep the DSI timing ratios matched to this board's realizable dclk. */
	.clock = 118800,
	.hdisplay = 1080,
	.hsync_start = 1080 + 10,
	.hsync_end = 1080 + 10 + 6,
	.htotal = 1080 + 10 + 6 + 32,
	.vdisplay = 1920,
	.vsync_start = 1920 + 20,
	.vsync_end = 1920 + 20 + 6,
	.vtotal = 1920 + 20 + 6 + 10,
	.flags = DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC,
};

static int md0550_get_modes(struct drm_panel *panel,
			    struct drm_connector *connector)
{
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &md0550_mode);
	if (!mode)
		return -ENOMEM;

	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_set_name(mode);
	drm_mode_probed_add(connector, mode);
	connector->display_info.bpc = 8;

	return 1;
}

static const struct drm_panel_funcs md0550_funcs = {
	.prepare = md0550_prepare,
	.enable = md0550_enable,
	.disable = md0550_disable,
	.unprepare = md0550_unprepare,
	.get_modes = md0550_get_modes,
};

static int md0550_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct md0550 *priv;
	int ret;

	priv = devm_drm_panel_alloc(dev, struct md0550, panel,
				    &md0550_funcs, DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(priv))
		return PTR_ERR(priv);

	priv->dsi = dsi;
	mutex_init(&priv->lock);
	mipi_dsi_set_drvdata(dsi, priv);
	priv->power = devm_regulator_get(dev, "power");
	if (IS_ERR(priv->power))
		return dev_err_probe(dev, PTR_ERR(priv->power),
				     "failed to get module power\n");

	priv->reset = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(priv->reset))
		return dev_err_probe(dev, PTR_ERR(priv->reset),
				     "failed to get reset GPIO\n");

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	/* HX8399 requires EoT: disabling it causes persistent DSI sink errors. */
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST;
	priv->panel.prepare_prev_first = true;
	ret = drm_panel_of_backlight(&priv->panel);
	if (ret)
		return ret;

	drm_panel_add(&priv->panel);
	ret = mipi_dsi_attach(dsi);
	if (ret) {
		drm_panel_remove(&priv->panel);
		return dev_err_probe(dev, ret, "failed to attach DSI\n");
	}

	priv->debugfs = debugfs_create_dir(dev_name(dev), NULL);
	debugfs_create_file("status", 0400, priv->debugfs, priv,
			    &md0550_status_fops);

	return 0;
}

static void md0550_remove(struct mipi_dsi_device *dsi)
{
	struct md0550 *priv = mipi_dsi_get_drvdata(dsi);
	int ret;

	/* The DRM master owns disable/unprepare while host clocks are running. */
	debugfs_remove_recursive(priv->debugfs);
	/* Host unregister may already have detached this peripheral. */
	if (dsi->attached) {
		ret = mipi_dsi_detach(dsi);
		if (ret)
			dev_err(&dsi->dev, "failed to detach DSI: %d\n", ret);
	}
	drm_panel_remove(&priv->panel);
}

static const struct of_device_id md0550_of_match[] = {
	{ .compatible = "alientek,atk-md0550-1080p" },
	{ }
};
MODULE_DEVICE_TABLE(of, md0550_of_match);

static struct mipi_dsi_driver md0550_driver = {
	.probe = md0550_probe,
	.remove = md0550_remove,
	.driver = {
		.name = "panel-alientek-md0550",
		.of_match_table = md0550_of_match,
	},
};
module_mipi_dsi_driver(md0550_driver);

MODULE_DESCRIPTION("Alientek ATK-MD0550 1080p MIPI panel");
MODULE_LICENSE("GPL");
