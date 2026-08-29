// SPDX-License-Identifier: GPL-2.0-only
/*
 * sdm660-oppo-r11s.c -- OPPO R11s ASoC machine driver (mainline port)
 *
 * The OPPO R11s ships a downstream audio stack driven by
 * techpack/audio/asoc/sdm660-common.c + sdm660-internal.c
 * (compatible "qcom,sdm660-asoc-snd", model "sdm660-snd-card-mtp").
 * Its routing is fixed by the DT properties:
 *
 *   oppo,headphone-pa = "akm"    -> AK4376 headphone DAC on PRIMARY MI2S
 *   oppo,speaker-pa   = "maxim"  -> MAX98927L speaker PA on SECONDARY MI2S
 *
 * This driver reproduces exactly the two backend DAI links the downstream
 * sdm660-internal.c builds for those properties (see ak4376_be_dai_link /
 * maxim_be_dai_links there), but wires them to the mainline qdsp6 ASoC
 * components instead of the downstream msm-pcm/q6 stack:
 *
 *   FE:  MultiMedia1 (q6asm-dai) --- q6adm routing
 *   BE1: PRI_MI2S_RX (q6afe-dai)  -> ak4375/ak4376 ("ak4375-hifi")
 *   BE2: SEC_MI2S_RX (q6afe-dai)  -> max98927    ("max98927-aif1")
 *
 * All component nodes are located by their mainline compatible strings so
 * the driver does not depend on specific DT node names; it becomes fully
 * functional once the DTB carries the mainline apr/q6 subtree
 * ("qcom,q6asm-dais", "qcom,q6afe-dais", "qcom,q6adm-routing").  Until
 * then probe defers, which is the expected behavior for the current
 * (downstream-binding) DTB.
 *
 * Reference: android_kernel_oppo_sdm660_source techpack/audio/asoc/
 *            sdm660-common.c, sdm660-internal.c
 */

#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <sound/soc.h>

/*
 * The DTB sound node uses the downstream machine compatible.  Match it so
 * this driver takes over card creation without any DTB rewrite; also
 * accept a mainline-style compatible in case the DT is modernized later.
 */
static const struct of_device_id r11s_snd_of_match[] = {
	{ .compatible = "qcom,sdm660-asoc-snd" },
	{ .compatible = "qcom,oppo-r11s-sndcard" },
	{ }
};
MODULE_DEVICE_TABLE(of, r11s_snd_of_match);

/*
 * Find the first enabled device-tree node matching any of the given
 * mainline compatibles.  Used to bind DAI link endpoints by compatible
 * string rather than by fragile node-name/dev_name strings.
 */
static struct device_node *r11s_find_node(const char * const compatibles[])
{
	struct device_node *np = NULL;
	const char * const *c;

	for (c = compatibles; *c; c++) {
		np = of_find_compatible_node(NULL, NULL, *c);
		if (np)
			return np;
	}

	return NULL;
}

static const char * const fe_cpu_compat[] = { "qcom,q6asm-dais", NULL };
static const char * const be_cpu_compat[] = { "qcom,q6afe-dais", NULL };
static const char * const plat_compat[]   = { "qcom,q6adm-routing",
					      "qcom,q6adm", NULL };
static const char * const hp_codec_compat[] = {
	"asahi-kasei,ak4375", "asahi-kasei,ak4376",
	/* legacy downstream binding found in the R11s DTB */
	"akm,ak4376", NULL
};
static const char * const spk_codec_compat[] = {
	"maxim,max98927",
	/* legacy downstream binding found in the R11s DTB */
	"maxim,max98927L", NULL
};

/* Frontend: userspace PCM -> q6asm session 1 (MultiMedia1) */
SND_SOC_DAILINK_DEFS(r11s_mm1,
	DAILINK_COMP_ARRAY(COMP_EMPTY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));

/* Backend: PRI_MI2S_RX -> AK4376 headphone DAC (downstream: ak4376-AIF1) */
SND_SOC_DAILINK_DEFS(r11s_hp,
	DAILINK_COMP_ARRAY(COMP_EMPTY()),
	DAILINK_COMP_ARRAY(COMP_CODEC(NULL, "ak4375-hifi")),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));

/* Backend: SEC_MI2S_RX -> MAX98927L speaker PA (downstream: max98927-aif1) */
SND_SOC_DAILINK_DEFS(r11s_spk,
	DAILINK_COMP_ARRAY(COMP_EMPTY()),
	DAILINK_COMP_ARRAY(COMP_CODEC(NULL, "max98927-aif1")),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));

static struct snd_soc_dai_link r11s_dai_links[] = {
	{
		/* FE: userspace PCM -> q6asm session 1 */
		.name = "MultiMedia1 Playback",
		.stream_name = "MultiMedia1",
		.dynamic = 1,
		.playback_only = 1,
		.ignore_pmdown_time = 1,
		SND_SOC_DAILINK_REG(r11s_mm1),
	},
	{
		/* BE: PRI_MI2S_RX -> AK4376 headphone DAC */
		.name = "Headphone Playback",
		.stream_name = "PRI_MI2S_RX",
		.no_pcm = 1,
		.playback_only = 1,
		.ignore_suspend = 1,
		SND_SOC_DAILINK_REG(r11s_hp),
	},
	{
		/* BE: SEC_MI2S_RX -> MAX98927L speaker PA */
		.name = "Speaker Playback",
		.stream_name = "SEC_MI2S_RX",
		.no_pcm = 1,
		.playback_only = 1,
		.ignore_suspend = 1,
		SND_SOC_DAILINK_REG(r11s_spk),
	},
};

/*
 * Fill the DAI link component placeholders with the of_nodes found by
 * compatible.  Returns -EPROBE_DEFER while the q6/codec subtree is absent
 * so card registration is retried once the DT is complete.
 */
static int r11s_bind_links(struct snd_soc_card *card)
{
	struct device_node *fe_cpu, *be_cpu, *plat, *hp, *spk;

	fe_cpu = r11s_find_node(fe_cpu_compat);
	be_cpu = r11s_find_node(be_cpu_compat);
	plat   = r11s_find_node(plat_compat);
	hp     = r11s_find_node(hp_codec_compat);
	spk    = r11s_find_node(spk_codec_compat);

	if (!fe_cpu || !be_cpu || !plat || !hp || !spk) {
		dev_err_probe(card->dev, -EPROBE_DEFER,
			      "audio components not described in DT yet (fe=%d be=%d plat=%d hp=%d spk=%d)\n",
			      !!fe_cpu, !!be_cpu, !!plat, !!hp, !!spk);
		of_node_put(fe_cpu);
		of_node_put(be_cpu);
		of_node_put(plat);
		of_node_put(hp);
		of_node_put(spk);
		return -EPROBE_DEFER;
	}

	r11s_dai_links[0].cpus->of_node = fe_cpu;
	r11s_dai_links[0].cpus->dai_name = "MultiMedia1";
	r11s_dai_links[0].platforms->of_node = plat;

	r11s_dai_links[1].cpus->of_node = be_cpu;
	r11s_dai_links[1].cpus->dai_name = "PRI_MI2S_RX";
	r11s_dai_links[1].platforms->of_node = plat;
	r11s_dai_links[1].codecs->of_node = hp;

	r11s_dai_links[2].cpus->of_node = be_cpu;
	r11s_dai_links[2].cpus->dai_name = "SEC_MI2S_RX";
	r11s_dai_links[2].platforms->of_node = plat;
	r11s_dai_links[2].codecs->of_node = spk;

	return 0;
}

static int r11s_snd_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct snd_soc_card *card;
	int ret;

	card = devm_kzalloc(dev, sizeof(*card), GFP_KERNEL);
	if (!card)
		return -ENOMEM;

	card->dev = dev;
	card->owner = THIS_MODULE;
	card->dai_link = r11s_dai_links;
	card->num_links = ARRAY_SIZE(r11s_dai_links);

	/* downstream DTB says qcom,model = "sdm660-snd-card-mtp" */
	if (of_property_read_string(dev->of_node, "qcom,model", &card->name))
		card->name = "oppo-r11s";

	ret = r11s_bind_links(card);
	if (ret)
		return ret;

	return devm_snd_soc_register_card(dev, card);
}

static struct platform_driver r11s_snd_driver = {
	.probe = r11s_snd_probe,
	.driver = {
		.name = "sdm660-oppo-r11s-snd",
		.of_match_table = r11s_snd_of_match,
	},
};
module_platform_driver(r11s_snd_driver);

MODULE_DESCRIPTION("OPPO R11s ASoC machine driver (mainline port)");
MODULE_LICENSE("GPL");
