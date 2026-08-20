#!/usr/bin/env python

from pathlib import Path

from suite.context import thistest
from suite.tutils import build_harness, run_gnattest

BODY_STUB = Path("obj-dep", "stubs", "Dep", "pack.adb")
SPEC_STUB = Path("obj-dep", "stubs", "Dep", "pack.ads")

# Run gnattest to generate the stub
run_gnattest("simple.gpr", ["-q", "--stub", "--harness-dir=h", "--stubs-dir=stubs"])

# Build the harness to catch any compilation problem.
build_harness("h/test_drivers.gpr", ["-q"])

# GNATtest should create a stub for pack, with
# - A newly generated body file
# - A rewritten spec file override without the pragma imports
thistest.fail_if(
    not BODY_STUB.exists(),
    f"{BODY_STUB} stub should have been created",
)

thistest.fail_if(
    not SPEC_STUB.exists(),
    f"{SPEC_STUB} stub should have been created",
)

with open(SPEC_STUB) as f:
    content = f.read()
    thistest.fail_if(
        "Import" in content, "pragmas should have been removed from the stub spec"
    )


thistest.result()
