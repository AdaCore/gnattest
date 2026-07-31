from re import Match

import os

from e3.testsuite.driver import TestDriver
from e3.testsuite.driver.diff import PatternSubstitute
from e3.testsuite.control import TestControlCreator, TestControl
from e3.fs import cp

from drivers.python_script import PythonScriptDriver

from typing import override

class LoadAddressHider(PatternSubstitute):
    """
    Remove the "load address:" message from backtraces, as not all targets
    have address space randomization support.
    """
    def __init__(self):
        super().__init__(pattern=r"\nLoad address: 0x[a-f0-9]+")


class AddressHider(PatternSubstitute):
    """
    Refiner that identifies addresses from a symbolic Ada traceback and hides
    the addresses, to stabilize the output. All consecutive addresses separated
    by a space will be collapsed into a single placeholder as the length of a
    traceback may vary due to factors outside of gnattest/tgen's control.
    """

    def __init__(self):
        super().__init__(
            pattern=r"(0x[0-9a-f]{3,} ?)+",
            replacement="<addr_or_backtrace>",
        )


def build_lineno_replacement(m : Match) -> str:
    """
    Assuming the match instance contains a nested match group containing
    a filename, return filename:<line_number> to be used as baseline placeholder
    """
    return m.group(1) + ":<line_number>"


class LineHider(PatternSubstitute):
    """
    Refiner that identifies the line of a test procedure in a gnattest harness
    output and replaces it by a placeholder. The line at which test procedure
    is generated in the harness has no relevance, and can vary depending on the
    target.
    """

    def __init__(self):
        super().__init__(
            pattern=r" \((.*-test_data-test(s|_.*[0-9a-f]*).adb):\d+\)",
            replacement=build_lineno_replacement,
        )


class DumpedTestDeleter(PatternSubstitute):
    """
    Refiner that identifies the output of the common gnattest_tgen driver
    generated when counting how many tests we dumped by --dump-test-inputs
    and removes it from the baseline comparison. This is used to not check this
    specific part of the test when running on cross targets, where test input
    dumping does not exist.
    """

    def __init__(self):
        super().__init__(pattern=r"Test runner dumped \d+ tests\n")


class SkipCreator(TestControlCreator):
    """
    Creates a control creator that always skips
    """

    @override
    def create(self, driver: TestDriver) -> TestControl:
        return TestControl(message="tgen not supported on light runtimes", skip=True)


class GNATTestTgenDriver(PythonScriptDriver):
    """
    Test driver to execute gnattest in test generation mode (with TGen)
    The driver will attempt to run "gnattest --gen-test-vectors
    --dump-test-inputs -P<proj>" on the first .gpr file found on the test
    directory, and log the output, then build and run the generated test
    harness. The test harness execution log is also recorded in the output.
    """

    @property
    def has_light_rts(self) -> bool:
        """
        Returns wether the current test driver has a light runtime configured.
        """
        return (
            self.env.main_options is not None
            and self.env.main_options.RTS
            and "light" in self.env.main_options.RTS
        )

    @property
    def test_control_creator(self):
        """
        If the configured runtime is light, always skip the test, otherwise
        process the test.yaml contents.
        """
        if self.has_light_rts:
            return SkipCreator()
        return super().test_control_creator

    @property
    def baseline_file(self):
        """
        Only override the baseline filename when in gnatfuzz test mode
        """
        if os.environ.get("GNATTEST_GNATFUZZ", None):
            return "gnattest_baseline.out", False
        else:
            return super().baseline_file

    @property
    def tool_dirname(self):
        return "test"

    @property
    def output_refiners(self):
        return (
            super().output_refiners
            + [LoadAddressHider(), AddressHider(), LineHider()]
            + ([DumpedTestDeleter()] if self.env.is_cross else [])
        )

    def set_up(self):
        super().set_up()

        # generate a default gpr file if the test asks for one
        if self.test_env.get("default-gpr", False):
            cp(
                os.path.join(
                    self.shared_dir(),
                    "gnatfuzz_default_resources",
                    "user_project.gpr",
                ),
                os.path.join(self.working_dir(), "user_project.gpr"),
            )

        # Copy the common test script in the test directory
        cp(
            os.path.join(self.shared_dir(), "gnattest_tgen_common", "test.py"),
            os.path.join(self.working_dir(), self.testfile_name)
        )
