"""
Check that "gnattest setup --lang=c" builds and installs Unity for a cross
target.
"""

import os

from suite.context import thistest
from suite.tutils import run_wrapper

prefix = os.path.join(os.getcwd(), "installed")

run_wrapper(
    [
        "gnattest",
        "setup",
        "-q",
        "--lang=c",
        f"--target={thistest.env.target.platform}",
        f"--prefix={prefix}",
    ],
    output_in_baseline=False,
)

thistest.fail_if(
    not os.path.exists(os.path.join(prefix, "share", "gpr", "gnattest_unity.gpr")),
    "missing Unity project",
)
thistest.fail_if(
    not os.path.exists(
        os.path.join(prefix, "lib", "gnattest_unity", "libgnattest_unity.a")
    ),
    "missing Unity library",
)

thistest.result()
