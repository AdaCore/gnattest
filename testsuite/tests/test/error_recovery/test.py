#!/usr/bin/env python

import os

from suite.tutils import run_gnattest
from suite.context import thistest

run_gnattest("p", ["--stub", "importing.ads", "-q"], env={**os.environ, "GNATTEST_STRICT": "False"})

thistest.result()
