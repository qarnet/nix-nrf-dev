/* Host executable uses the exact firmware serializer to produce test traffic. */
#include <stdio.h>
#include "wire.h"

int main(void)
{
	uint8_t record[FIXTURE_RECORD_SIZE];
	fixture_record(record, FIXTURE_DATA, 0, 0, 1, 10, 0x12345678);
	if (fwrite(record, 1, sizeof(record), stdout) != sizeof(record)) return 1;
	/* Attempts 1 and 2 were skipped by a full firmware ring. */
	fixture_record(record, FIXTURE_DATA, 3, 2, 1, 40, 0x12345678);
	if (fwrite(record, 1, sizeof(record), stdout) != sizeof(record)) return 1;
	/* Trailing attempts 4 and 5 were also dropped. */
	fixture_record(record, FIXTURE_SUMMARY, 6, 4, 1, 60, 0x12345678);
	return fwrite(record, 1, sizeof(record), stdout) == sizeof(record) ? 0 : 1;
}
