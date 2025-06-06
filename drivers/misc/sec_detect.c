// SPDX-License-Identifier: GPL-2.0-only
/*
 * Author: @Flopster101
 * Based on AkiraNoSushi's work for the Mi439 project.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include <linux/sec_detect.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/string.h>
#ifdef CONFIG_SEC_DETECT_SYSFS
#include <linux/kobject.h>
#include <linux/sysfs.h>
#endif

const char *const device_names[] = {
	[SEC_R9S] = "Galaxy S21 FE",
	[SEC_O1S] = "Galaxy S21",
	[SEC_P3S] = "Galaxy S21 Ultra",
	[SEC_T2S] = "Galaxy S21+",
};

static int g_sec_current_device = DEVICE_UNKNOWN;
static char g_sec_current_device_name[32] = "Unknown";
static bool g_sec_template_feature = false;
static bool g_sec_uses_s2mpb02 = false;
static bool g_sec_uses_ktd2692 = false;
static bool g_sec_support_mask_layer = false;
static bool g_sec_support_tig = false;
static bool g_sec_support_hmd = false;
static bool g_sec_uses_ssp_unbound = false;
static bool g_sec_uses_ssp_r9s = false;
static bool g_sec_support_ddi_flash = false;
static bool g_sec_support_gm2_flash = false;
static bool g_sec_support_poc_spi = false;

// Helper functions for each g_sec_ variable
enum SEC_devices sec_get_current_device(void) { return g_sec_current_device; }
EXPORT_SYMBOL_GPL(sec_get_current_device);

bool sec_feat_template_feature(void) { return g_sec_template_feature; }
EXPORT_SYMBOL_GPL(sec_feat_template_feature);

bool sec_feat_uses_s2mpb02(void) { return g_sec_uses_s2mpb02; }
EXPORT_SYMBOL_GPL(sec_feat_uses_s2mpb02);

bool sec_feat_uses_ktd2692(void) { return g_sec_uses_ktd2692; }
EXPORT_SYMBOL_GPL(sec_feat_uses_ktd2692);

bool sec_feat_support_mask_layer(void) { return g_sec_support_mask_layer; }
EXPORT_SYMBOL_GPL(sec_feat_support_mask_layer);

bool sec_feat_support_tig(void) { return g_sec_support_tig; }
EXPORT_SYMBOL_GPL(sec_feat_support_tig);

bool sec_feat_support_hmd(void) { return g_sec_support_hmd; }
EXPORT_SYMBOL_GPL(sec_feat_support_hmd);

bool sec_feat_uses_ssp_unbound(void) { return g_sec_uses_ssp_unbound; }
EXPORT_SYMBOL_GPL(sec_feat_uses_ssp_unbound);

bool sec_feat_uses_ssp_r9s(void) { return g_sec_uses_ssp_r9s; }
EXPORT_SYMBOL_GPL(sec_feat_uses_ssp_r9s);

bool sec_feat_support_ddi_flash(void) { return g_sec_support_ddi_flash; }
EXPORT_SYMBOL_GPL(sec_feat_support_ddi_flash);

bool sec_feat_support_gm2_flash(void) { return g_sec_support_gm2_flash; }
EXPORT_SYMBOL_GPL(sec_feat_support_gm2_flash);

bool sec_feat_support_poc_spi(void) { return g_sec_support_poc_spi; }
EXPORT_SYMBOL_GPL(sec_feat_support_poc_spi);

// Camera params
static bool mcd_template_camera_feature = false;
static bool mcd_type_rsu = false;
static bool mcd_type_usu = false;
static bool mcd_type_usuv3 = false;
static bool mcd_type_usuv1 = false;
static bool mcd_type_usuv2 = false;

// Helper functions for each mcd_ variable
bool sec_has_mcd_template_camera_feature(void) { return mcd_template_camera_feature; }
EXPORT_SYMBOL_GPL(sec_has_mcd_template_camera_feature);

bool sec_has_mcd_type_rsu(void) { return mcd_type_rsu; }
EXPORT_SYMBOL_GPL(sec_has_mcd_type_rsu);

bool sec_has_mcd_type_usu(void) { return mcd_type_usu; }
EXPORT_SYMBOL_GPL(sec_has_mcd_type_usu);

bool sec_has_mcd_type_usuv3(void) { return mcd_type_usuv3; }
EXPORT_SYMBOL_GPL(sec_has_mcd_type_usuv3);

bool sec_has_mcd_type_usuv1(void) { return mcd_type_usuv1; }
EXPORT_SYMBOL_GPL(sec_has_mcd_type_usuv1);

bool sec_has_mcd_type_usuv2(void) { return mcd_type_usuv2; }
EXPORT_SYMBOL_GPL(sec_has_mcd_type_usuv2);

static bool g_detection_complete = false;

bool sec_is_detection_complete(void) {
    return g_detection_complete;
}
EXPORT_SYMBOL_GPL(sec_is_detection_complete);

#ifdef CONFIG_SEC_DETECT_SYSFS
// Sysfs attribute to show the current device name
static ssize_t device_name_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return snprintf(buf, 32, "%s\n", g_sec_current_device_name);
}

// Sysfs attribute to show the current device model
static ssize_t device_model_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	const char *model_name = "Unknown";
	if (g_sec_current_device >= 0 && g_sec_current_device < ARRAY_SIZE(device_names))
		model_name = device_names[g_sec_current_device];
	return snprintf(buf, 32, "%s\n", model_name);
}

static struct kobj_attribute device_name_attr = __ATTR(device_name, 0444, device_name_show, NULL);
static struct kobj_attribute device_model_attr = __ATTR(device_model, 0444, device_model_show, NULL);

static struct attribute *attrs[] = {
	&device_name_attr.attr,
	&device_model_attr.attr,
	NULL,
};

static struct attribute_group attr_group = {
	.attrs = attrs,
};

static struct kobject *device_kobj;
#endif

static inline void setup_camera_params(void) {
	switch (g_sec_current_device) {
	case SEC_R9S:
		mcd_type_rsu = true;
		break;
	case SEC_O1S:
		mcd_type_usu = true;
		break;
	case SEC_P3S:
		mcd_type_usuv3 = true;
		mcd_type_usu = true;
		break;
	case SEC_T2S:
		mcd_type_usu = true;
		break;
	default:
		break;
	}
}

// New function to print machine name and sec_ variables
static inline void print_sec_variables(const char *machine_name) {
	SEC_DETECT_LOG("Current machine name: %s\n", machine_name);
	// SEC_DETECT_LOG("g_sec_template_feature = %s\n", g_sec_template_feature ? "true" : "false");
	SEC_DETECT_LOG("g_sec_uses_s2mpb02 = %s\n", g_sec_uses_s2mpb02 ? "true" : "false");
	SEC_DETECT_LOG("g_sec_uses_ktd2692 = %s\n", g_sec_uses_ktd2692 ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_mask_layer = %s\n", g_sec_support_mask_layer ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_tig = %s\n", g_sec_support_tig ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_hmd = %s\n", g_sec_support_hmd ? "true" : "false");
	SEC_DETECT_LOG("g_sec_uses_ssp_unbound = %s\n", g_sec_uses_ssp_unbound ? "true" : "false");
	SEC_DETECT_LOG("g_sec_uses_ssp_r9s = %s\n", g_sec_uses_ssp_r9s ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_ddi_flash = %s\n", g_sec_support_ddi_flash ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_gm2_flash = %s\n", g_sec_support_gm2_flash ? "true" : "false");
	SEC_DETECT_LOG("g_sec_support_poc_spi = %s\n", g_sec_support_poc_spi ? "true" : "false");
}

static int __init sec_detect_init(void) {
	struct device_node *root;
	const char *machine_name;
	int retval = 0;
#ifdef CONFIG_SEC_DETECT_SYSFS
	int sysfs_ret = 0;
#endif

	root = of_find_node_by_path("/");
	if (!root) {
		SEC_DETECT_LOG("Failed to find device tree root\n");
		smp_wmb();
		g_detection_complete = true;
		retval = -ENOENT;
		goto exit_no_root;
	}

	machine_name = of_get_property(root, "model", NULL);
	if (!machine_name)
		machine_name = of_get_property(root, "compatible", NULL);

	if (!machine_name) {
		SEC_DETECT_LOG("Failed to find machine name\n");
		smp_wmb();
		g_detection_complete = true;
		retval = -ENOENT;
		goto exit_put_root;
	}

	if (strstr(machine_name, "R9S") != NULL) {
		g_sec_current_device = SEC_R9S;
		strscpy(g_sec_current_device_name, "r9s", sizeof(g_sec_current_device_name));
		g_sec_uses_ktd2692 = true;
		g_sec_support_mask_layer = true;
		g_sec_support_tig = true;
		g_sec_uses_ssp_r9s = true;
	} else if (strstr(machine_name, "O1S") != NULL) {
		g_sec_current_device = SEC_O1S;
		strscpy(g_sec_current_device_name, "o1s", sizeof(g_sec_current_device_name));
		g_sec_uses_s2mpb02 = true;
		g_sec_support_hmd = true;
		g_sec_uses_ssp_unbound = true;
		g_sec_support_ddi_flash = true;
		g_sec_support_gm2_flash = true;
		g_sec_support_poc_spi = true;
	} else if (strstr(machine_name, "P3S") != NULL) {
		g_sec_current_device = SEC_P3S;
		strscpy(g_sec_current_device_name, "p3s", sizeof(g_sec_current_device_name));
		g_sec_uses_s2mpb02 = true;
		g_sec_support_hmd = true;
		g_sec_uses_ssp_unbound = true;
	} else if (strstr(machine_name, "T2S") != NULL) {
		g_sec_current_device = SEC_T2S;
		strscpy(g_sec_current_device_name, "t2s", sizeof(g_sec_current_device_name));
		g_sec_uses_s2mpb02 = true;
		g_sec_support_hmd = true;
		g_sec_uses_ssp_unbound = true;
		g_sec_support_ddi_flash = true;
		g_sec_support_gm2_flash = true;
		g_sec_support_poc_spi = true;
	}

	// Print machine name and sec_ variables
	print_sec_variables(machine_name);

#ifdef CONFIG_SEC_DETECT_SYSFS
	// Create the sysfs entry
	device_kobj = kobject_create_and_add("sec_detect", kernel_kobj);
	if (!device_kobj) {
		SEC_DETECT_LOG("Failed to create sysfs kobject\n");
		retval = -ENOMEM;
		goto exit_put_root;
	}

	sysfs_ret = sysfs_create_group(device_kobj, &attr_group);
	if (sysfs_ret) {
		SEC_DETECT_LOG("Failed to create sysfs group, error %d\n", sysfs_ret);
		kobject_put(device_kobj);
		device_kobj = NULL;
	}
#endif

	setup_camera_params();
exit_put_root:
	of_node_put(root);
exit_no_root:
	smp_wmb();
	g_detection_complete = true;
	if (!retval)
		SEC_DETECT_LOG("Initialization complete and ready.\n");

	return retval;
}

static void __exit sec_detect_exit(void) {
#ifdef CONFIG_SEC_DETECT_SYSFS
	if (device_kobj) {
		sysfs_remove_group(device_kobj, &attr_group);
		kobject_put(device_kobj);
	}
#endif
	return;
}

rootfs_initcall(sec_detect_init); // runs before regular drivers init
module_exit(sec_detect_exit);

MODULE_AUTHOR("Flopster101");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Detects the device currently running this kernel. Also exposes device information through sysfs.");
