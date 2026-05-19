#!/usr/bin/env python

import os

from suite.tutils import run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("nested/prj_1/prj_1.gpr", ["-q", f"--tests-root={os.getcwd()}/foo"])
run_wrapper(["find", "foo", "-name", "pkg-test_data.adb"])

thistest.result()
