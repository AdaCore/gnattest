#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

run_gnattest("root.gpr", ["-q", "--stub", "--stubs-dir=../some_other_dir"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])

thistest.result()
