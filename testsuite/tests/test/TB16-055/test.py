#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("p", ["--stub", "-q", "simple.ads", "simple.adb"])

thistest.result()
