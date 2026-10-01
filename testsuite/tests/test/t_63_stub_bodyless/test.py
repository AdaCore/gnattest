#!/usr/bin/env python

from pathlib import Path

from suite.context import thistest
from suite.tutils import build_harness, run_gnattest

UNFINISHED_BODY = Path("stubs", "simple", "unfinished.adb")
UNFINISHED_SPEC = Path("stubs", "simple", "unfinished.ads")

NULL_PROC_BODY = Path("stubs", "simple", "null_proc.adb")
EXPR_FUNC_BODY = Path("stubs", "simple", "expr_func.adb")

run_gnattest("simple.gpr", ["-q", "--stub", "--harness-dir=h", "--stubs-dir=stubs"])
build_harness("h/test_drivers.gpr", ["-q"])

# GNATtest should create a stub for pack, with a newly generated body file
thistest.fail_if(
    not UNFINISHED_BODY.exists(),
    f"{UNFINISHED_BODY} stub should have been created",
)

thistest.fail_if(
    UNFINISHED_SPEC.exists(),
    f"{UNFINISHED_SPEC} stub should not have been rewritten",
)

thistest.fail_if(
    NULL_PROC_BODY.exists(),
    f"{NULL_PROC_BODY} stub should not have been rewritten",
)

thistest.fail_if(
    EXPR_FUNC_BODY.exists(),
    f"{EXPR_FUNC_BODY} stub should not have been rewritten",
)

thistest.result()
