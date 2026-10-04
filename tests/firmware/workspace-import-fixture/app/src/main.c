/* SPDX-License-Identifier: MIT */
int source_import_fixture_value(void);

int main(void)
{
	/* The final link proves manifest-owned module discovery participated. */
	return source_import_fixture_value() == 41 ? 0 : 1;
}
