#!/usr/bin/env python

"""
An aggregate library root project is processed as a regular project: a single
harness is generated in the aggregate library object directory, covering the
units of all the aggregated projects.
"""

import os

from suite.context import thistest
from suite.tutils import build_harness, run_gnattest, run_harness

harness = os.path.join("obj_agg", "gnattest", "harness")

run_gnattest("agg.gpr", ["-q"])

#  A single harness is generated, in the aggregate library object directory,
#  and it holds a test suite for the units of every aggregated project.

for unit in (
    "test_driver.gpr",
    "test_runner.adb",
    "gnattest_main_suite.ads",
    "pkg1-test_data-tests-suite.ads",
    "pkg2-test_data-tests-suite.ads",
):
    thistest.fail_if(
        not os.path.exists(os.path.join(harness, unit)),
        f"missing {unit} in {harness}",
    )

#  The aggregated projects get no harness of their own: this is what tells this
#  case apart from the sequential processing of a plain aggregate project.

for obj_dir in ("obj1", "obj2"):
    thistest.fail_if(
        os.path.exists(os.path.join(obj_dir, "gnattest", "harness")),
        f"unexpected harness generated in {obj_dir}",
    )

#  Test skeletons, on the other hand, belong to the project owning the unit

for obj_dir, skeleton in (("obj1", "pkg1"), ("obj2", "pkg2")):
    path = os.path.join(obj_dir, "gnattest", "tests", f"{skeleton}-test_data-tests.adb")
    thistest.fail_if(not os.path.exists(path), f"missing skeleton {path}")

build_harness(os.path.join(harness, "test_driver.gpr"), ["-q"])
run_harness(os.path.join(harness, "test_runner"))

thistest.result()
