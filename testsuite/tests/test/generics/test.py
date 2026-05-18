#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

run_gnattest("pkg.gpr")
build_harness("gnattest/harness/test_driver.gpr", ["-q"])
run_harness("gnattest/harness/test_runner")

thistest.result()
