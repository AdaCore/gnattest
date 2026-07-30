"""
Test that gnattest correctly displays an error message when the user
does not provide a suitable mapping file for in target generation.
"""

import os.path

from suite.context import thistest
from suite.tutils import run_gnattest

from e3.fs import cp
from e3.os.fs import which

# Log the error message we get when the passed config file is invalid JSON
p = run_gnattest(
    "prj.gpr",
    args=["--gen-test-vectors", "--tgen-target-config=invalid.json"],
    allow_failure=True,
)
thistest.fail_if(p.status == 0, "gnattest did not exit in error for invalid mapping")

# Same but with a config file that does not contain an entry for the current
# target.
p = run_gnattest(
    "prj.gpr",
    args=["--gen-test-vectors", "--tgen-target-config=missing_target.json"],
    allow_failure=True,
)
thistest.fail_if(
    p.status == 0, "gnattest did not exit in error for missing target in mapping"
)

# Passing a valid file should work ok, we'll copy the one shipped with gnattest
# to remain up to date.
gnattest = which("gnattest")
config_source = os.path.join(
    os.path.dirname(gnattest), "..", "share", "tgen", "tgen_target_runtimes.json"
)
cp(config_source, "valid.json")
run_gnattest(
    "prj.gpr",
    args=["--gen-test-vectors", "--tgen-target-config=valid.json", "-q"],
)

thistest.result()
