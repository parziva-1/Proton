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

#ifndef _LINUX_SEC_H
#define _LINUX_SEC_H

#include <linux/types.h>

#define SEC_DETECT_LOG(fmt, ...) printk(KERN_INFO "sec_detect: " fmt, ##__VA_ARGS__)
static const char *sec_detect_label = "sec_detect: ";

enum SEC_devices {
	DEVICE_UNKNOWN = -1,
	SEC_R9S,
	SEC_O1S,
	// Add other devices here as needed
};

extern const char *const device_names[];

// Device feature helpers
enum SEC_devices sec_get_current_device(void);
bool sec_feat_template_feature(void);
bool sec_feat_uses_s2mpb02(void);
bool sec_feat_uses_ktd2692(void);
bool sec_feat_support_mask_layer(void);

// Camera param helpers
bool sec_has_mcd_template_camera_feature(void);

bool sec_is_detection_complete(void);

#endif /* _LINUX_SEC_H */
