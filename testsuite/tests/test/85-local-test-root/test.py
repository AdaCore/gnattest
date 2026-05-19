#!/usr/bin/env python

from suite.tutils import run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("nested/prj_1/prj_1.gpr", ["-q"])
run_wrapper(["find", "nested/prj_1/foo", "-name", "pkg-test_data.adb"])

thistest.result()
