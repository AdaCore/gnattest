#!/usr/bin/env python

# Two projects share the common test code in shared/ through their (committed,
# persistent) gnattest_common.gpr, whose Additional_Source_Dirs points at that
# directory. The committed test skeletons consume Shared_Setup, a unit found
# only there, so gnattest reusing those files and a successful build prove the
# directory ends up on each harness Source_Dirs. No file is edited at runtime.

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

for prj, obj in [("p1.gpr", "obj1"), ("p2.gpr", "obj2")]:
    harness = f"{obj}/gnattest/harness"
    run_gnattest(prj)
    build_harness(f"{harness}/test_driver.gpr", ["-q"])
    run_harness(f"{harness}/test_runner")

thistest.result()
