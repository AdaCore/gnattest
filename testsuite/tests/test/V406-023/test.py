#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

# The harness directory is kept short on purpose. Under the default
# gnattest_stub/harness, the longest path gprbuild writes in the test driver
# object directory goes over the Windows MAX_PATH limit.
run_gnattest("simple.gpr", ["-q", "--stub", "--harness-dir=h"])
build_harness("h/test_drivers.gpr", ["-q"])

thistest.result()
