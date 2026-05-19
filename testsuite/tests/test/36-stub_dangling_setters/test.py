#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest

run_gnattest("prj.gpr", ["-q", "-XSRC_DIR=old", "--stub"])
run_gnattest("prj.gpr", ["-XSRC_DIR=new", "--stub"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q", "-XSRC_DIR=new"])

thistest.result()
