#! /usr/bin/env python

"""
Usage::

    testsuite.py [OPTIONS]

Run the libadalang-tools testsuite.
"""

import os
from typing import List

import e3.testsuite
from e3.fs import sync_tree
from e3.os.process import Run
from e3.testsuite.testcase_finder import ParsedTest

from drivers.python_script import PythonScriptDriver
from drivers.shell_script import ShellScriptDriver
from drivers.gnattest_tgen import GNATTestTgenDriver
from suite.control import add_shared_options_to


class Testsuite(e3.testsuite.Testsuite):
    @property
    def tests_subdir(self) -> str:
        return "tests"

    @property
    def test_driver_map(self):
        return {
            "python_script": PythonScriptDriver,
            "shell_script": ShellScriptDriver,
            "gnattest_tgen": GNATTestTgenDriver,
            # Driver available only in the GNATfuzz testsuite.
            # Uses GNATtest and TGen
            "fuzz_everything": GNATTestTgenDriver,
        }

    def add_options(self, parser):
        parser.add_argument(
            "--no-wip",
            action="store_true",
            help="Do not run tests for work-in-progress (WIP) programs",
        )
        parser.add_argument(
            "--fold-casing",
            action="store_true",
            help="Ignore casing in testcase outputs",
        )
        parser.add_argument(
            "--valgrind", action="store_true", help="Run tests under valgrind"
        )
        parser.add_argument(
            "--rewrite",
            "-r",
            action="store_true",
            help="Rewrite test baselines according to current output.",
        )
        parser.add_argument(
            "--setup-tgen-rts",
            action="store_true",
            help="Build and install TGen_RTS (regular and light) to prevent tests "
            "from re-building the library. This is not needed if the environment "
            "already provides the installed project.",
        )
        parser.add_argument(
            "--gnatfuzz-tests",
            action="store_true",
            help="enable the special 'gnatfuzz testsuite' mode, where all"
            " tests are run with the gnattest_tgen driver. It is meant"
            " to be used when running the testsuite on tests from the"
            " gnatfuzz testsuite, to ensure TGen doesn't crash. It is"
            " possible to instruct gnattest to emit debug logs and"
            " preserve generation artifacts by setting the GNATTEST_DEBUG"
            " env variable to aid debugging.",
        )

        add_shared_options_to(parser)

    def setup_tgen_runtime(self, rts_install_dir: str) -> None:
        e3.testsuite.logger.info("Running gnattest setup ...")
        args = self.main.args
        assert args is not None
        cmd = ["gnattest", "setup", f"--prefix={rts_install_dir}"]
        if args.target:
            # --target may use the extended target[,version[,machine[,mode]]]
            # syntax; only pass the target triplet to gnattest.
            cmd.append(f"--target={args.target.split(',')[0]}")
        if args.RTS:
            cmd.append(f"--RTS={args.RTS}")
        p_setup = Run(cmd)
        if p_setup.status != 0:
            e3.testsuite.logger.fatal(f"Failed to run gnattest setup: {p_setup.out}")
            exit(1)

        self.env.add_search_path(
            "GPR_PROJECT_PATH", os.path.join(rts_install_dir, "share", "gpr")
        )

    def set_up(self):
        super().set_up()

        # If the main arguments have not been properly defined stop.
        if not self.main.args:
            return

        self.env.no_wip = self.main.args.no_wip
        self.env.fold_casing = self.main.args.fold_casing
        self.env.valgrind = self.main.args.valgrind
        self.env.rewrite_baselines = self.main.args.rewrite

        # We need to add "." to the PATH, because some tests run programs in
        # the current directory.
        os.environ["PATH"] = "%s:." % os.environ["PATH"]

        # Setup TGen runtime support
        if self.main.args.setup_tgen_rts:
            self.setup_tgen_runtime(rts_install_dir=self.working_dir)

        if self.env.valgrind:
            # The --valgrind switch was given. Set the PATH to point to the
            # valgrind directory (see ../../valgrind/README).
            valgrind_dir = os.path.abspath(
                os.path.join(script_dir, "..", "..", "valgrind")
            )
            os.environ["PATH"] = valgrind_dir + os.pathsep + os.environ["PATH"]

        # Signal to the tests that we are in GNATFUZZ execution mode (for test
        # control purposes).
        if self.main.args.gnatfuzz_tests:
            os.environ["GNATTEST_GNATFUZZ"] = "TRUE"

            # Run all gnatfuzz tests, as we aren't that resource-constrained
            # when generating tests through TGen
            os.environ["GNATFUZZ_LOCAL_EXECUTION"] = "TRUE"

        # Turn on strict mode for gnattest to catch real errors
        os.environ["GNATTEST_STRICT"] = "TRUE"

        # Set a fixed seed for TGen random generation, in order to keep the
        # testsuite deterministic.
        os.environ["TGEN_RANDOM_SEED"] = "1234"

    @property
    def default_driver(self):
        """
        By default, all tests should specify the required driver, except when in
        gnatfuzz_test mode, where we only want to use the gnattest_tgen driver.
        """
        return (
            "gnattest_tgen"
            if self.main.args and self.main.args.gnatfuzz_tests
            else None
        )


if __name__ == "__main__":
    Testsuite(os.path.dirname(__file__)).testsuite_main()
