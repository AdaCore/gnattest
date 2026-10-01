"""
Check that gnattest preserves, with a warning, a stub body it did not
generate, while still regenerating its own stub bodies.
"""

import filecmp
import os
import re
import shutil

from suite.tutils import build_harness, run_gnattest, run_harness
from suite.context import thistest

stubs_dir = os.path.join("obj", "gnattest_stub", "stubs", "Prj")
dep_stub = os.path.join(stubs_dir, "dep.adb")
other_stub = os.path.join(stubs_dir, "other.adb")
put_test = os.path.join(
    "obj", "gnattest_stub", "tests", "put-test_data-tests.adb"
)


def substitute(filename, pattern, repl):
    """Replace the single match of pattern in filename by repl."""
    with open(filename) as f:
        content = f.read()
    content, count = re.subn(pattern, repl, content)
    thistest.fail_if(count != 1, f"{pattern!r} not found in {filename}")
    with open(filename, "w") as f:
        f.write(content)


def check_stubs():
    """Check that both stub bodies hold the user code."""
    thistest.fail_if(
        not filecmp.cmp("dep_stub.adb", dep_stub, shallow=False),
        "hand-written stub body was modified",
    )
    with open(other_stub) as f:
        thistest.fail_if(
            "return 2;" not in f.read(),
            "user edit of the generated stub body was lost",
        )


# The hand-written body is in place before the first generation. GNATtest
# must keep it and warn.

os.makedirs(stubs_dir)
shutil.copy("dep_stub.adb", dep_stub)
run_gnattest("prj.gpr", ["-q", "--stub"])

# Edit the generated stub body of Other and the test of Put, which depends
# on both stubbed units.

substitute(other_stub, r"return Stub_Data\.\w+\.H_Result;", "return 2;")
substitute(
    put_test,
    r'Gnattest_Generated\.Default_Assert_Value,\s*"Test not implemented\."',
    "Put.F = 42, \"F =\" & Integer'Image (Put.F)",
)

# A second generation must keep both bodies, and warn again about the
# hand-written one.

print("=== second generation ===", flush=True)
run_gnattest("prj.gpr", ["-q", "--stub"])
check_stubs()

# The driver of Put must use both stubs.

build_harness("obj/gnattest_stub/harness/test_drivers.gpr", ["-q"])
run_harness(
    os.path.join(
        "obj",
        "gnattest_stub",
        "harness",
        "Put.Test_Data.Tests",
        "put-test_data-tests-suite-test_runner",
    )
)

thistest.result()
