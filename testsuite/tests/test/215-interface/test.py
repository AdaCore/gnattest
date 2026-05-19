#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

run_gnattest("lib1", ["-q", "-dd", "--stub"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])
run_gnattest("lib4", ["-q", "-dd", "--stub"])
build_harness("obj-lib4/gnattest_stub/harness/test_drivers.gpr", ["-q"])

thistest.result()
