#!/usr/bin/env python

"""
Test checking tgen support (dynamic type introspection and binary /
JSON marshallers) for all of the types supported by the library.
"""

from suite.tutils import (
    build_harness,
    run_gnattest,
    run_harness,
    run_command,
    run_wrapper,
)
from suite.context import thistest

from os import makedirs
from os.path import dirname, join
from e3.os.fs import which

if not thistest.env.is_cross:
    templates_path = join(
        dirname(dirname(which("gnattest"))), "share", "tgen", "templates"
    )
    makedirs("test/obj", exist_ok=True)
    makedirs("obj", exist_ok=True)
    run_command(
        "tgen_marshalling",
        "test/test.gpr",
        [
            f"--templates-dir={templates_path}",
            "-o",
            "test/tgen_support",
            "test/my_file.ads",
            "test/show_date.ads",
        ],
    )
    run_command("gprbuild", "test_gen.gpr", ["-q"])
    run_wrapper(["./obj/example_gen"])
    run_wrapper(["./obj/example_introspection"])


run_gnattest("test/test.gpr", ["-q", "--gen-test-vectors"])
build_harness("test/obj/gnattest/harness/test_driver.gpr", ["-q"])
run_harness("test/obj/gnattest/harness/test_runner")

thistest.result()
