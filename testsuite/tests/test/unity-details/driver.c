#include "gnattest_unity.h"

static void suite_setup (void)
{
  char first[] = "suite first", second[] = "suite second";
  UNITY_SET_DETAILS (first, second);
}

static void first_failure (void) { TEST_FAIL_MESSAGE ("first failure"); }

static void own_failure (void)
{
  char first[] = "own first", second[] = "own second";
  UNITY_SET_DETAILS (first, second);
  TEST_FAIL_MESSAGE ("own failure");
}

static void own_ignore (void)
{
  char first[] = "ignore first", second[] = "ignore second";
  UNITY_SET_DETAILS (first, second);
  TEST_IGNORE_MESSAGE ("own ignore");
}

static void after_ignore (void) { TEST_FAIL_MESSAGE ("after ignore"); }

static void last_test (void)
{
  char first[] = "last first", second[] = "last second";
  UNITY_SET_DETAILS (first, second);
#ifdef UNITY_DETAIL_STACK_SIZE
  /* A partial pop would leave the two details below this entry alive.  */
  UnityPushDetail (UNITY_DETAIL_D1, (UNITY_DETAIL_VALUE_TYPE) "extra", __LINE__);
#endif
}

static void suite_teardown (void) { TEST_FAIL_MESSAGE ("teardown failure"); }

static void failed_setup (void)
{
  char first[] = "setup first", second[] = "setup second";
  UNITY_SET_DETAILS (first, second);
  TEST_FAIL_MESSAGE ("setup failure");
}

static void next_setup (void) { TEST_FAIL_MESSAGE ("next setup failure"); }
static void not_run (void) { TEST_FAIL_MESSAGE ("must not run"); }

static const gnattest_suite suites[] = {
  { "tests", NULL, NULL, suite_setup, suite_teardown },
  { "failed_setup", NULL, NULL, failed_setup, NULL },
  { "next_setup", NULL, NULL, next_setup, NULL }
};
#define ENTRY(s, f) { &suites[s], #f, __FILE__, __LINE__, f }
static const gnattest_test tests[] = {
  ENTRY (0, first_failure), ENTRY (0, own_failure), ENTRY (0, own_ignore),
  ENTRY (0, after_ignore), ENTRY (0, last_test),
  ENTRY (1, not_run), ENTRY (2, not_run)
};
static const gnattest_test_table table = {
  tests, sizeof (tests) / sizeof (tests[0])
};

int main (int argc, char **argv)
{
  const gnattest_test_table *tables[] = { &table };
  return gnattest_unity_run (argc, argv, tables, 1);
}
