#!/usr/bin/env python

from suite.tutils import build_harness, run_gnattest
from suite.context import thistest


def print_naming_section(gpr_path):
    in_naming = False
    with open(gpr_path) as f:
        for line in f:
            line = line.rstrip()
            if "package Naming" in line:
                in_naming = True
            if in_naming:
                print(line)
            if in_naming and "end Naming" in line:
                in_naming = False


run_gnattest(
    "long_package_nested.gpr", ["-q", "--shorten-package", "--package-max-len=15"]
)

# The top package has no test routine of its own, so GNATtest generates a
# spec-only hosting package for it that also needs a Naming exception.

print("=== skeleton ===")
print_naming_section("gnattest/harness/test_long_package_nested.gpr")

print("=== harness ===")
print_naming_section("gnattest/harness/test_driver.gpr")

build_harness("gnattest/harness/test_driver.gpr", ["-q"])

thistest.result()
