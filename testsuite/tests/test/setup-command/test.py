#!/usr/bin/env python

"""
Test for the "gnattest setup" command.
"""

import os

from suite.context import thistest
from suite.tutils import run_wrapper

options = thistest.options
prefix = os.path.join(os.getcwd(), "installed")

# Build the `gnattest setup` command line, using the testsuite configuration
cmd = ["gnattest", "setup", "-q", f"--prefix={prefix}"]
if options.RTS:
    cmd.append(f"--RTS={options.RTS}")
if options.target:
    cmd.append(f"--target={thistest.env.target.platform}")

run_wrapper(cmd, output_in_baseline=False)

# Check that AUnit is installed
thistest.fail_if(
    not os.path.exists(os.path.join(prefix, "share", "gpr", "aunit.gpr")),
    "missing aunit install",
)

# Check that TGen is installed in native configurations
if thistest.env.target.is_host:
    thistest.fail_if(
        not os.path.exists(os.path.join(prefix, "share", "gpr", "tgen_rts.gpr")),
        "missing TGen runtime install",
    )
    thistest.fail_if(
        not os.path.exists(os.path.join(prefix, "share", "gpr", "tgen_marshalling_rts.gpr")),
        "missing TGen marshalling runtime install",
    )

thistest.result()
