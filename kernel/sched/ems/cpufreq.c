/*
 * Exynos Mobile Scheduler cpufreq helpers
 *
 * Runtime backend for emstune fclamp.
 */

#include <linux/cpufreq.h>
#include <linux/slab.h>

#include "../sched.h"
#include "ems.h"

#define FCLAMP_MIN	0
#define FCLAMP_MAX	1
#define PART_HIST_SIZE	10

struct fclamp {
	struct fclamp_data fclamp_min;
	struct fclamp_data fclamp_max;
} __percpu **fclamp;

#define per_cpu_fc(cpu)		(*per_cpu_ptr(fclamp, cpu))

static int fclamp_monitor_group[STUNE_GROUP_COUNT];

static bool fclamp_has_monitored_group(void)
{
	int group;

	for (group = 0; group < STUNE_GROUP_COUNT; group++)
		if (fclamp_monitor_group[group])
			return true;

	return false;
}

static bool fclamp_any_group_active(struct cpufreq_policy *policy)
{
	u64 now = sched_clock();
	int cpu, group;

	if (!fclamp_has_monitored_group())
		return false;

	for_each_cpu(cpu, policy->cpus) {
		for (group = 0; group < STUNE_GROUP_COUNT; group++) {
			if (!fclamp_monitor_group[group])
				continue;

			if (freqboost_cpu_boost_group_active(group, cpu, now))
				return true;
		}
	}

	return false;
}

static int fclamp_cpu_active_ratio(int cpu, int target_period)
{
	int idx, active_ratio = 0, samples = 0;

	if (target_period <= 0)
		return 0;

	/* Avoid wrapping through the fixed-size activity history ring. */
	if (target_period > PART_HIST_SIZE)
		target_period = PART_HIST_SIZE;

	idx = get_part_hist_idx(cpu);
	idx = idx ? idx - 1 : PART_HIST_SIZE - 1;

	while (target_period--) {
		active_ratio += get_part_hist_value(cpu, idx);
		samples++;
		idx = idx ? idx - 1 : PART_HIST_SIZE - 1;
	}

	if (!samples)
		return 0;

	active_ratio /= samples;

	return (active_ratio * 100) / SCHED_CAPACITY_SCALE;
}

static bool fclamp_can_release(int cpu, struct fclamp_data *fcd)
{
	int active_ratio;

	if (!fcd->target_period)
		return true;

	active_ratio = fclamp_cpu_active_ratio(cpu, fcd->target_period);

	if (fcd->type == FCLAMP_MAX)
		return active_ratio > fcd->target_ratio;

	return active_ratio < fcd->target_ratio;
}

unsigned int fclamp_apply(struct cpufreq_policy *policy, unsigned int orig_freq)
{
	struct fclamp *fc = per_cpu_fc(policy->cpu);
	struct fclamp_data *fcd;
	unsigned int new_freq;
	int cpu, count = 0, type;

	if (!fc)
		return orig_freq;

	if (!fclamp_any_group_active(policy))
		return orig_freq;

	if (orig_freq > fc->fclamp_max.freq)
		fcd = &fc->fclamp_max;
	else if (orig_freq < fc->fclamp_min.freq)
		fcd = &fc->fclamp_min;
	else
		return orig_freq;

	if (!fcd->freq || !fcd->target_period)
		return orig_freq;

	type = fcd->type;
	new_freq = fcd->freq;

	for_each_cpu(cpu, policy->cpus) {
		if (!fclamp_can_release(cpu, fcd))
			continue;

		count++;
		if (type == FCLAMP_MAX)
			break;
	}

	if (type == FCLAMP_MIN && count == cpumask_weight(policy->cpus))
		new_freq = orig_freq;
	if (type == FCLAMP_MAX && count > 0)
		new_freq = orig_freq;

	return clamp_val(new_freq, policy->cpuinfo.min_freq,
			policy->cpuinfo.max_freq);
}

static int fclamp_emstune_notifier_call(struct notifier_block *nb,
					unsigned long val, void *v)
{
	struct emstune_set *cur_set = v;
	int cpu, group;

	for_each_possible_cpu(cpu) {
		struct fclamp *fc = per_cpu_fc(cpu);

		if (!fc)
			continue;

		fc->fclamp_min.freq = cur_set->fclamp.min_freq[cpu];
		fc->fclamp_min.target_period =
				cur_set->fclamp.min_target_period[cpu];
		fc->fclamp_min.target_ratio =
				cur_set->fclamp.min_target_ratio[cpu];

		fc->fclamp_max.freq = cur_set->fclamp.max_freq[cpu];
		fc->fclamp_max.target_period =
				cur_set->fclamp.max_target_period[cpu];
		fc->fclamp_max.target_ratio =
				cur_set->fclamp.max_target_ratio[cpu];
	}

	for (group = 0; group < STUNE_GROUP_COUNT; group++)
		fclamp_monitor_group[group] = cur_set->fclamp.monitor_group[group];

	return NOTIFY_OK;
}

static struct notifier_block fclamp_emstune_notifier = {
	.notifier_call = fclamp_emstune_notifier_call,
};

static int fclamp_init(void)
{
	int cpu;

	fclamp = alloc_percpu(struct fclamp *);
	if (!fclamp) {
		pr_err("failed to allocate fclamp\n");
		return -ENOMEM;
	}

	for_each_possible_cpu(cpu) {
		struct fclamp *fc;
		int i;

		if (cpu != cpumask_first(cpu_coregroup_mask(cpu)))
			continue;

		fc = kzalloc(sizeof(*fc), GFP_KERNEL);
		if (!fc)
			return -ENOMEM;

		fc->fclamp_min.type = FCLAMP_MIN;
		fc->fclamp_max.type = FCLAMP_MAX;

		for_each_cpu(i, cpu_coregroup_mask(cpu))
			per_cpu_fc(i) = fc;
	}

	/* Default to monitoring top-app like newer trees. */
	fclamp_monitor_group[STUNE_TOPAPP] = 1;

	emstune_register_mode_update_notifier(&fclamp_emstune_notifier);

	return 0;
}

int cpufreq_init(void)
{
	return fclamp_init();
}
