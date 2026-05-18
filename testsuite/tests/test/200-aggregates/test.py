#!/usr/bin/env python

from suite.tutils import run_gnattest, run_wrapper
from suite.context import thistest

run_gnattest("prj.gpr", ["--stub", "--subdirs=test", "--stubs-dir=stub", "-q"])
run_wrapper(["gprbuild", "-q", "obj1/gnattest_stub/harness/test_drivers.gpr"])
run_wrapper(["gprbuild", "-q", "obj2/gnattest_stub/harness/test_drivers.gpr"])

thistest.result()
