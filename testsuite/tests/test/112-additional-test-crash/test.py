#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("root.gpr", ["--additional-tests=missing_aunit/extra_tests.gpr"], allow_failure=True)
run_gnattest("root.gpr", ["--additional-tests=missing_tested_prj/extra_tests.gpr"], allow_failure=True)

thistest.result()
