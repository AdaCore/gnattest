"""Exercise Unity diagnostic decoding and binary stdout capture."""

import os

from check import check
from suite.context import thistest
from suite.tutils import run_wrapper

prefix = os.path.join(os.getcwd(), "installed")
run_wrapper(
    ["gnattest", "setup", "-q", "--lang=c", f"--prefix={prefix}"],
    output_in_baseline=False,
)
run_wrapper(
    ["gprbuild", "-q", "-Ptest.gpr", f"-aP{prefix}/share/gpr"],
    output_in_baseline=False,
)
result = run_wrapper(["./driver"], output_in_baseline=False)
check(result.out)
thistest.result()
