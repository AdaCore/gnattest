#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

ret_gnattest = run_gnattest("simple.gpr")

ret_gprbuild = build_harness("obj/gnattest/harness/test_driver.gpr", ["-q"])

ret_run = run_harness("obj/gnattest/harness/test_runner")

thistest.result()
