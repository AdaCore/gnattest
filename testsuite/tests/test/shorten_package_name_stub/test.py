#!/usr/bin/env python

import os

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
    "long_package.gpr",
    ["--stub", "-q", "--shorten-package", "--package-max-len=15"],
)

harness = os.path.join("gnattest_stub", "harness")
uut_dir = os.path.join(harness, "A_Very_Lon548c7.Test_Data.Tests")

print("=== harness dirs ===")
for d in sorted(os.listdir(harness)):
    if os.path.isdir(os.path.join(harness, d)):
        print(d)

print("=== UUT harness files ===")
for f in sorted(os.listdir(uut_dir)):
    if f.endswith((".ads", ".adb")):
        print(f)

print("=== UUT test_driver.gpr ===")
print_naming_section(os.path.join(uut_dir, "test_driver.gpr"))

build_harness(os.path.join(harness, "test_drivers.gpr"), ["-q"])

thistest.result()
