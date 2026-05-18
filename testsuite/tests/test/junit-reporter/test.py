#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

print("Driver per unit:", flush=True)
run_gnattest(
    "tagged_rec.gpr",
    ["-q", "--harness-dir=h1", "--reporter=junit", "--separate-drivers=unit"],
)
build_harness("h1/test_drivers.gpr", ["-q"])
run_harness("h1/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-suite-test_runner")

print("Driver per test:", flush=True)
run_gnattest(
    "tagged_rec.gpr",
    [
        "-q",
        "--harness-dir=h2",
        "--reporter=junit",
        "--separate-drivers=test",
        "--validate-type-extensions",
        "--source-root=gnattest",
    ],
)
build_harness("h2/test_drivers.gpr", ["-q"])
run_harness("h2/Q.T2_Test_Data.T2_Tests/q-t2_test_data-t2_tests-driver_test_x2_0cbc93")

print("Driver per test (substitution check):", flush=True)
run_harness(
    "h2/Q.T2_Test_Data.T2_Tests/q-t2_test_data-t2_tests-vte_driver_test_x2_0cbc93"
)

print("Driver per unit (stubbing):", flush=True)
run_gnattest("tagged_rec.gpr", ["-q", "--harness-dir=h3", "--reporter=junit", "--stub"])
build_harness("h3/test_drivers.gpr", ["-q"])
run_harness("h3/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-suite-test_runner")

print("Driver file path relative (stubbing):", flush=True)
run_gnattest(
    "tagged_rec.gpr",
    [
        "-q",
        "--harness-dir=h4",
        "--reporter=junit",
        "--source-root=gnattest_stub",
        "--stub",
    ],
)
build_harness("h4/test_drivers.gpr", ["-q"])
run_harness("h4/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-suite-test_runner")

thistest.result()
