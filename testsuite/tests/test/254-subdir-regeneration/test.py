#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("test1.gpr", ["-q"], allow_failure=True)
run_gnattest("test2.gpr", ["-q", "--subdirs=my_tests"], allow_failure=True)

thistest.result()
