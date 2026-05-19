#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("contracts.gpr", ["-q"])
run_gnattest("contracts.gpr", ["-q", "-XGNATTEST_SOURCE_SELECT=after"])

thistest.result()
