#!/usr/bin/env python

from pathlib import Path

from suite.context import thistest
from suite.tutils import build_harness, run_gnattest

BODY_STUB = Path("stubs", "simple", "pack.adb")
SPEC_STUB = Path("stubs", "simple", "pack.ads")

# Then run it again, without the parameter so external_stubbing is enabled.
run_gnattest("simple.gpr", ["-q", "--stub", "--harness-dir=h", "--stubs-dir=stubs"])

# Build the harness to catch any compilation problem.
build_harness("h/test_drivers.gpr", ["-q"])

# There is an "Unreferenced" aspect in the spec, with import aspects,
# make sure it's still here
with open(SPEC_STUB) as f:
    content = f.read()
    thistest.fail_if(
        not "Unreferenced" in content, "spec should still be 'with Unreferenced'"
    )


thistest.result()
