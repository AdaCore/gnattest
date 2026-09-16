#!/usr/bin/env python

import os

from suite.tutils import run_gnattest
from suite.context import thistest

# --separate-drivers without a value defaults to "unit", so it must produce
# the same harness layout as --separate-drivers=unit: a per-unit driver
# directory and the test_drivers.list consumed by the test execution mode.

for switch, harness in [
    ("--separate-drivers", "harness_no_value"),
    ("--separate-drivers=unit", "harness_unit"),
]:
    run_gnattest("p.gpr", ["-q", switch, f"--harness-dir={harness}"])
    for artifact in [
        "test_drivers.list",
        os.path.join("Simple.Test_Data.Tests", "test_driver.gpr"),
    ]:
        path = os.path.join("obj", harness, artifact)
        thistest.fail_if(
            not os.path.isfile(path),
            f"{switch}: missing {artifact}",
        )

thistest.result()
