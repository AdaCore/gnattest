#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

run_gnattest("simple_ext.gpr", ["--no-subprojects", "-q"])
build_harness("gnattest/harness/test_driver.gpr", ["-q"])

thistest.result()
