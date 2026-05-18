#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("root.gpr", ["--stub", "--stubs-dir", "../stubs", "--tests-dir", "../tests", "-q"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])
run_wrapper(["gnattest", "obj/gnattest_stub/harness/test_drivers.list"])

thistest.result()
