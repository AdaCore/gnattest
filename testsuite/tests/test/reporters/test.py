#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

from e3.fs import rm

print("Driver per unit:", flush=True)
run_gnattest("tagged_rec.gpr", ["-q", "--harness-dir=h1", "--reporter=xml", "--separate-drivers=unit"])
build_harness("obj/h1/test_drivers.gpr", ["-q"])
run_harness("obj/h1/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-suite-test_runner")
rm("obj", recursive=True)
print("Driver per test:", flush=True)
run_gnattest("tagged_rec.gpr", ["-q", "--harness-dir=h2", "--reporter=text", "--separate-drivers=test", "--validate-type-extensions"])
build_harness("obj/h2/test_drivers.gpr", ["-q"])
run_harness("obj/h2/Q.T2_Test_Data.T2_Tests/q-t2_test_data-t2_tests-driver_test_x2_0cbc93")
print("Driver per test (substitution check):", flush=True)
run_harness("obj/h2/Q.T2_Test_Data.T2_Tests/q-t2_test_data-t2_tests-vte_driver_test_x2_0cbc93")
rm("obj", recursive=True)
print("Driver per unit (stubbing):", flush=True)
run_gnattest("tagged_rec.gpr", ["-q", "--harness-dir=h3", "--reporter=xml", "--stub"])
build_harness("obj/h3/test_drivers.gpr", ["-q"])
run_harness("obj/h3/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-suite-test_runner")
rm("obj", recursive=True)
print("Driver per test (stubbing):", flush=True)
run_gnattest("tagged_rec.gpr", ["-q", "--harness-dir=h4", "--reporter=text", "--stub", "--separate-drivers=test"])
build_harness("obj/h4/test_drivers.gpr", ["-q"])
run_harness("obj/h4/P.T_Test_Data.T_Tests/p-t_test_data-t_tests-driver_test_x1_09503c")

thistest.result()
