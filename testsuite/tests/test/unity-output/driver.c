#include <stdio.h>
#include "gnattest_unity.h"

static void nul_bytes (void)
{
  static const char bytes[] = "\0before\0\0after\0";
  fwrite (bytes, 1, sizeof (bytes) - 1, stdout);
}

static void nul_only (void) { putchar (0); }
static void mixed_output (void)
{
  TEST_MESSAGE ("info \\x00 \\x41 \xC3\xA9");
  printf ("before%cafter\n", 0);
}
static void literal_failure (void)
{
  TEST_FAIL_MESSAGE ("literal \\x00after \\x41 \\xC3 \\n \\r \\\\ \xC3\xA9");
}
static void literal_info (void) { TEST_MESSAGE ("\\x00after"); }
static void literal_skip (void) { TEST_IGNORE_MESSAGE ("\\x41after"); }
static void compared_nul (void) { TEST_ASSERT_EQUAL_STRING ("a", ""); }
static void plain_output (void) { printf ("plain \xC3\xA9\n"); }
static void incomplete_utf8 (void)
{
  static const char bytes[] = { '\xC3', '\0', '\xE2', '\x82' };
  fwrite (bytes, 1, sizeof (bytes), stdout);
}
static void control_info (void) { TEST_MESSAGE ("byte: \x01"); }
static void invalid_info (void) { TEST_MESSAGE ("byte: \xC3"); }
static void bounded_failure (void)
{
  TEST_ASSERT_EQUAL_STRING_LEN ("\xC3\xA9", "x", 2);
}
static void empty_output (void) {}
static void info_only (void) { TEST_MESSAGE ("info"); }

static const gnattest_suite suite = { "suite", NULL, NULL, NULL, NULL };
#define ENTRY(f) { &suite, #f, "path\\to\\test-\xC3\xA9.c", __LINE__, f }
static const gnattest_test tests[] = {
  ENTRY (nul_bytes), ENTRY (nul_only), ENTRY (mixed_output),
  ENTRY (literal_failure), ENTRY (literal_info), ENTRY (literal_skip),
  ENTRY (compared_nul), ENTRY (plain_output), ENTRY (incomplete_utf8),
  ENTRY (empty_output), ENTRY (info_only), ENTRY (control_info),
  ENTRY (invalid_info), ENTRY (bounded_failure)
};
static const gnattest_test_table table = {
  tests, sizeof (tests) / sizeof (tests[0])
};

int main (int argc, char **argv)
{
  const gnattest_test_table *tables[] = { &table };
  return gnattest_unity_run (argc, argv, tables, 1);
}
