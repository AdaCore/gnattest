"""Exercise Unity detail isolation with fixed slots and a detail stack."""

import os

from check import check
from suite.context import thistest
from suite.tutils import run_wrapper

for mode, flags in [("slots", []), ("stack", ["-DUNITY_DETAIL_STACK_SIZE=8"])]:
    prefix = os.path.join(os.getcwd(), mode)
    run_wrapper(
        ["gnattest", "setup", "-q", "--lang=c", f"--prefix={prefix}"]
        + (["-gargs", "-cargs", *flags] if flags else []),
        output_in_baseline=False,
    )
    run_wrapper(
        ["gprbuild", "-q", "-p", "-Ptest.gpr", f"-aP{prefix}/share/gpr", f"-XMODE={mode}"]
        + (["-cargs", *flags] if flags else []),
        output_in_baseline=False,
    )
    result = run_wrapper(["./driver"], output_in_baseline=False)
    check(result.out)
thistest.result()
