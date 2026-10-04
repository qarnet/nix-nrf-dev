/* SPDX-License-Identifier: MIT */
#ifndef NIX_NRF_FIXTURE_WIRE_H
#define NIX_NRF_FIXTURE_WIRE_H

#include <stdint.h>

#define FIXTURE_RECORD_SIZE 64U
#define FIXTURE_DATA 1U
#define FIXTURE_SUMMARY 2U

static inline void fixture_put32(uint8_t *out, uint32_t value)
{
	for (unsigned i = 0; i < 4; ++i) {
		out[i] = (uint8_t)(value >> (8 * i));
	}
}

/* Serialize explicitly: neither structure padding nor CPU endianness is wire ABI.
 * Sequence counts DATA attempts, not successful writes or SUMMARY retries.
 */
static inline void fixture_record(uint8_t out[FIXTURE_RECORD_SIZE], uint8_t kind,
				  uint32_t seq, uint32_t drops, uint32_t boot,
				  uint32_t uptime, uint32_t build)
{
	out[0] = 'P'; out[1] = 'B'; out[2] = '0'; out[3] = '4';
	out[4] = 1;
	out[5] = kind;
	out[6] = FIXTURE_RECORD_SIZE;
	out[7] = 0;
	fixture_put32(out + 8, seq);
	fixture_put32(out + 12, drops);
	fixture_put32(out + 16, boot);
	fixture_put32(out + 20, uptime);
	fixture_put32(out + 24, seq + (kind == FIXTURE_DATA));
	fixture_put32(out + 28, build);
	for (unsigned i = 0; i < 24; ++i) {
		out[32 + i] = (uint8_t)(seq + 17 * i);
	}
	uint32_t checksum = 0;
	for (unsigned i = 0; i < 56; ++i) {
		checksum += out[i];
	}
	fixture_put32(out + 56, checksum);
	fixture_put32(out + 60, 0x0DF00D04U);
}
#endif
