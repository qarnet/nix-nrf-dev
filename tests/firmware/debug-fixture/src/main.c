/* SPDX-License-Identifier: MIT */
#include <SEGGER_RTT.h>
#include <zephyr/drivers/hwinfo.h>
#include <zephyr/kernel.h>

#include "wire.h"

/* Public test symbols are resolved from the matching ELF, never fixed addresses.
 * The pattern is initialized once and stays unchanged even in intrusive tests.
 */
volatile uint32_t fixture_magic = 0x50423034U;
volatile uint32_t fixture_ready;
volatile uint32_t fixture_boot;
volatile uint32_t fixture_retained_valid;
volatile uint32_t fixture_reset_cause;
volatile uint32_t fixture_build_tag = FIXTURE_BUILD_TAG;
volatile uint32_t fixture_attempts;
volatile uint32_t fixture_drops;
volatile uint32_t fixture_summaries;
volatile uint32_t fixture_text_attempts;
volatile uint32_t fixture_text_drops;
volatile uint32_t fixture_action;
volatile uint32_t fixture_watch_word;
volatile uint8_t fixture_ram_pattern[256];

struct retained_state {
	uint32_t magic;
	uint32_t count;
	uint32_t inverse;
};
static struct retained_state retained __noinit;

static char binary_up[2048];
K_SEM_DEFINE(fixture_main_gate, 0, 1);

/* Put an explicit hardware breakpoint here, or watch fixture_watch_word.
 * This function runs only after an intrusive fixture_action=1 request.
 */
__attribute__((noinline)) void fixture_breakpoint_site(void)
{
	fixture_watch_word++;
}

static void text_thread(void *a, void *b, void *c)
{
	ARG_UNUSED(a); ARG_UNUSED(b); ARG_UNUSED(c);
	static const char text[] = "PB004 text channel\n";
	for (;;) {
		uint32_t action = fixture_action;
		if (action != 0) {
			fixture_action = 0;
			if (action == 1) {
				fixture_breakpoint_site();
			} else if (action == 2) {
				/* Kernel panic, not a claim of a hardware HardFault. */
				k_panic();
			}
		}
		fixture_text_attempts++;
		if (SEGGER_RTT_Write(0, text, sizeof(text) - 1) != sizeof(text) - 1) {
			fixture_text_drops++;
		}
		k_sleep(K_MSEC(100));
	}
}

static void binary_thread(void *a, void *b, void *c)
{
	ARG_UNUSED(a); ARG_UNUSED(b); ARG_UNUSED(c);
	uint8_t record[FIXTURE_RECORD_SIZE];
	for (;;) {
		for (unsigned i = 0; i < 128; ++i) {
			uint32_t seq = fixture_attempts++;
			fixture_record(record, FIXTURE_DATA, seq, fixture_drops,
				       fixture_boot, k_uptime_get_32(), FIXTURE_BUILD_TAG);
			/* Whole-record skip. No printf, allocation, blocking transport, or
			 * retry in this producer. This is a fixture, not a DMA recorder.
			 */
			if (SEGGER_RTT_Write(1, record, sizeof(record)) != sizeof(record)) {
				fixture_drops++;
			}
			k_sleep(K_MSEC(10));
		}
		/* A trailing summary reports drops even when no later DATA succeeds.
		 * Immutable summary retry is outside the producer loop and sleeps.
		 */
		fixture_record(record, FIXTURE_SUMMARY, fixture_attempts, fixture_drops,
			       fixture_boot, k_uptime_get_32(), FIXTURE_BUILD_TAG);
		while (SEGGER_RTT_Write(1, record, sizeof(record)) != sizeof(record)) {
			k_sleep(K_MSEC(50));
		}
		fixture_summaries++;
		k_sleep(K_MSEC(2000));
	}
}

K_THREAD_DEFINE(pb004_text, 1024, text_thread, NULL, NULL, NULL, 6, 0, SYS_FOREVER_MS);
K_THREAD_DEFINE(pb004_binary, 1024, binary_thread, NULL, NULL, NULL, 7, 0, SYS_FOREVER_MS);

int main(void)
{
	/* Keep initialized identity words live under linker section GC and refuse
	 * to publish readiness if the image data was not initialized correctly.
	 */
	if (fixture_magic != 0x50423034U || fixture_build_tag != FIXTURE_BUILD_TAG) {
		return 1;
	}
	/* This counter identifies tested warm resets only. NOLOAD is not a power
	 * retention guarantee and count=1 can recur after power loss or reload.
	 */
	fixture_retained_valid = retained.magic == 0xB004B004U &&
		retained.inverse == ~retained.count;
	uint32_t count = fixture_retained_valid ? retained.count + 1 : 1;
	retained.magic = 0;
	retained.count = count;
	retained.inverse = ~count;
	retained.magic = 0xB004B004U;
	fixture_boot = count;
	uint32_t cause = 0;
	if (hwinfo_get_reset_cause(&cause) == 0) {
		fixture_reset_cause = cause;
	}
	for (unsigned i = 0; i < sizeof(fixture_ram_pattern); ++i) {
		fixture_ram_pattern[i] = (uint8_t)(i ^ 0xA5U);
	}
	SEGGER_RTT_Init();
	if (SEGGER_RTT_ConfigUpBuffer(1, "pb004-binary", binary_up,
				     sizeof(binary_up), SEGGER_RTT_MODE_NO_BLOCK_SKIP) < 0) {
		return 1;
	}
	fixture_ready = 1;
	k_thread_start(pb004_text);
	k_thread_start(pb004_binary);
	/* A known blocked main thread alongside the two named periodic threads. */
	k_sem_take(&fixture_main_gate, K_FOREVER);
	return 0;
}
