#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

run_gnattest("generics.gpr", ["-q", "--stub", "importing.ads"])
build_harness("gnattest_stub/harness/test_drivers.gpr", ["-q"])

thistest.result()
