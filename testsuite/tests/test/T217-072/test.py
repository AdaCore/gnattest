#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("p.gpr", ["-q"])

thistest.result()
