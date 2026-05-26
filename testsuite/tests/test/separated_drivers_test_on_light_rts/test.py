#!/usr/bin/env python

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("p", ["-q", "--stub", "--separate-drivers=test", "--harness-dir=harness1"], allow_failure=True)

thistest.result()
