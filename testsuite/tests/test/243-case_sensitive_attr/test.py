#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("test1.gpr", ["-q"])
run_gnattest("test2.gpr", ["-q"])

thistest.result()
