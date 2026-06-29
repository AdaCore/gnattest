#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest


def print_config_lines(gpr):
    """
    Print the lines of the generated gnattest_common.gpr showing how the
    configuration packages of the argument project are inherited.
    """
    with open(gpr) as f:
        for line in f:
            line = line.rstrip()
            if line.startswith("with ") or "extends" in line:
                print(line.replace("\\", "/"), flush=True)


# The configuration packages of gnattest_common.gpr must extend the
# corresponding packages of the argument project, so that its configuration
# is inherited by the harness. In particular the harness build only works if
# Compiler'Local_Configuration_Pragmas (prj.adc, which contains pragma
# Ada_2022) is inherited, since pkg.ads uses Ada 2022 syntax while harness
# units are compiled with -gnat2012 by default.

# We also check that compiler switches are also inherited by checking the
# output of gprbuild, which issues message as gnattest generated code does
# not fully respect -gnata.

run_gnattest("prj.gpr", ["-q"])
print_config_lines("obj/gnattest/harness/gnattest_common.gpr")

build_harness("obj/gnattest/harness/test_driver.gpr")
run_harness("obj/gnattest/harness/test_runner")

# In stub mode the argument project is extended by the generated stub
# projects, so gnattest_common.gpr must not import it and its packages must
# not extend the user ones. The harness is not built here since the user
# configuration is precisely not inherited in this mode, so the Ada 2022
# spec cannot be compiled from the harness.

run_gnattest("prj.gpr", ["-q", "--stub"])
print("=== stub mode ===", flush=True)
print_config_lines("obj/gnattest_stub/harness/gnattest_common.gpr")

thistest.result()
