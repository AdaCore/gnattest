#!/usr/bin/env python

from suite.tutils import run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("prj.gpr", ["-q"])
run_wrapper(["cat", "obj/gnattest/harness/coverage_settings.mk"])

thistest.result()
