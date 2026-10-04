/* SPDX-License-Identifier: MIT */
int source_fixture_value(void);

int main(void)
{
	/* Linking must fail if the application-owned extra module was omitted. */
	return source_fixture_value() == 23 ? 0 : 1;
}
