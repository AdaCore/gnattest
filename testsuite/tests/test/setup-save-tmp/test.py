"""
Check that --save-temps does preserve build artifacts when
invoking gnattest setup.
"""

from suite.tutils import run_wrapper
from suite.context import thistest
from glob import glob
import os

run_wrapper(
    ["gnattest", "setup", "--prefix=local", "--save-temps"],
    output_in_baseline=False,
)

# Temp dir get overriden by the TMPDIR env variable, defined by anod
temp_dir = os.environ["TMPDIR"] if "TMPDIR" in os.environ else os.getcwd()

# Inspect the current directory for build artifacts
aunit_obj = glob("GNAT-*/gnattest-setup-*/aunit/lib/aunit-obj", root_dir=temp_dir)
thistest.fail_if(len(aunit_obj) == 0, "Could not find aunit build object dir")
thistest.result()
