#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("prj.gpr", ["--stub", "-q", "--stubs-dir=./stub_default"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])
run_wrapper(["grep", "pragma Ada_2012;", "./obj/stub_default/Prj/dep-stub_data.ads"])
run_gnattest("prj.gpr", ["--stub", "-q", "--stubs-dir=./stub_05", "-gnat05"])
build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])
run_wrapper(["grep", "pragma Ada_2005;", "./obj/stub_05/Prj/dep-stub_data.ads"])

thistest.result()
