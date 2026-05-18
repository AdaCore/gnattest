#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_wrapper
from suite.context import thistest

run_wrapper(["ln", "-s", "nest1/nest2/nest3", "sim"])
run_gnattest("sim/simple.gpr", ["-q", "--harness-dir=."])
build_harness("sim/test_driver.gpr", ["-q"])
run_wrapper(["cat", "sim/test_simple.gpr"])
run_wrapper(["cat", "sim/test_driver.gpr"])

thistest.result()
