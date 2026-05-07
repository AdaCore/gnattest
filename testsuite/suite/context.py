import os
from pathlib import Path
import sys
import time

import e3.log
from e3.env import Env
from e3.main import Main
from e3.os.fs import cd

from suite.cutils import exit_if
from suite import control

logger = e3.log.getLogger("os_fs")

# This is where the toplevel invocation was issued for the individual test
# at hand, which we expect to be where the toplevel testsuite.py is located.
ROOT_DIR = os.getcwd()


class _ReportOutput(object):
    """
    A class that allows us to write some text to a report file, while
    bufferizing part of it until we know whether this part should also be
    printed on standard output or not.  The idea is to buffer the output
    generated for each driver until the end of the test, and then print that
    output to stdout if we then determine that the test failed.

    ATTRIBUTES
      report_fd: A file descriptor to the report file where all the output
            is always written.
      output: A string buffer holding the output being written to the report
            file.  The contents of that buffer may be reset after a driver
            has been run and associated results have been collected.  See
            method "flush" below.
      print_diff: A boolean, False by default, that should be true if
            the contents of the output attribute should be printed on
            standard output at the next flush.
    """

    def __init__(self, report_file: Path, log_file, error_file):
        """Constructor.

        PARAMETERS
          report_file: The name of the file where to write all the logs.
        """
        self.report_file = report_file
        self.log_file = log_file
        self.error_file = error_file

        self.report_fd = open(self.report_file, "w")
        self.log_fd = open(self.log_file, "w")
        self.error_fd = open(self.error_file, "w")

        self.output = ""
        self.print_diff = False

    def enable_diffs(self):
        """
        Turn printing of the output buffer on.  The printing will be done at
        the next flush.
        """
        self.print_diff = True

    def report(self, text: str, end_of_line=True):
        """
        Write the given text in the output file.  This also adds the text to
        the output buffer.

        PARAMETERS
          text:   The text to be reported.
          end_of_line: If True, then append a '\n' character at the end
                  of text. This affects both the report file and the output
                  buffer. The idea is to emulate the "print" statement
                  which adds this '\n' by default too.
        """
        if end_of_line:
            text += os.linesep
        self.output += text
        self.report_fd.write(text)

    def log(self, text: str, end_of_line=True):
        """
        Write the given text in the log file.

        PARAMETERS
          text:   The text to be logged.
          end_of_line: If True, then append a '\n' character at the end
                  of text. The idea is to emulate the "print" statement
                  which adds this '\n' by default too.
        """
        if end_of_line:
            text += os.linesep
        self.log_fd.write(text)

    def error(self, text: str, end_of_line=True):
        """
        Write the given text in the error file.

        PARAMETERS
          text:   The text to be reported as an error.
          end_of_line: If True, then append a '\n' character at the end
                  of text. The idea is to emulate the "print" statement
                  which adds this '\n' by default too.
        """
        if end_of_line:
            text += os.linesep
        self.error_fd.write(text)

    def flush(self):
        """
        Reset the output buffer (printing its content on standard output first
        if print_diff is True).  Reset print_diff to False as well.
        """
        if self.print_diff:
            sys.stdout.write(self.output + " ")
        self.output = ""
        self.print_diff = False
        self.report_fd.flush()
        self.log_fd.flush()
        self.error_fd.flush()

    def close(self):
        """Close the file descriptor for our report file."""
        self.report_fd.close()
        self.log_fd.close()
        self.error_fd.close()


class Test(object):
    def __init__(self):
        self.env = Env()

        self.start_time = time.time()
        # Compute this test's home directory, absolute dir where test.py
        # is located, then the position relative to testsuite.py. Note that
        # .__file__ might be an absolute path, which os.path.join handles
        # just fine (join("/foo", "/foo/bar") yields "/foo/bar").

        testsuite_py_dir = ROOT_DIR
        test_py_file = sys.modules["__main__"].__file__
        test_py_dir = ""
        if not test_py_file:
            logger.error("Could not found the main module")
            exit(1)
        test_py_dir = os.path.dirname(test_py_file)

        self.homedir = os.path.join(testsuite_py_dir, test_py_dir)
        self.reldir = os.path.relpath(self.homedir, start=testsuite_py_dir)

        cd(self.homedir)

        self.options = self.__cmdline_options()
        self.n_failed = 0
        self.report = _ReportOutput(
            self.options.report_file, self.options.test_log_file, self.options.error_file
        )

    def __cmdline_options(self):
        """Return an options object to represent the command line options"""
        main = Main(platform_args=True)
        parser = main.argument_parser

        parser.add_argument("--timeout", type=int, default=None)
        parser.add_argument(
            "--root-dir",
            metavar="DIR",
            type=Path,
            help="The toplevel invocation was issued for the "
            "individual test at hand [required]",
        )
        parser.add_argument(
            "--report-file",
            metavar="FILE",
            help="The filename where to store the test report" " [required]",
        )

        parser.add_argument(
            "--test-log-file",
            metavar="FILE",
            help="The filename where to store the test logs" " [required]",
        )
        parser.add_argument(
            "--error-file",
            metavar="FILE",
            help="The filename where to store the test errors " " [required]",
        )
        control.add_shared_options_to(parser)

        main.parse_args()

        if not main.args:
            sys.stderr.write("The main arguments cannot be none" + "\n")
            sys.exit(1)

        # "--report-file" is a required "option" which is a bit
        # self-contradictory, but it's easy to do it that way.
        exit_if(
            main.args.report_file is None,
            "The report file must be specified with --report-file",
        )
        return main.args

    def log(self, text: str, new_line=True):
        """Calls self.report.log."""
        self.report.log(text, new_line)

    def output_report(self, text: str, new_line=True):
        """Calls self.report.report."""
        self.report.report(text, new_line)

    def error_report(self, text: str, new_line=True):
        """Calls self.report.error."""
        self.report.error(text, new_line)

    def flush(self):
        """Calls self.report.flush."""
        self.report.flush()

    def result(self):
        """Output the final result which the testsuite driver looks for.

        This should be called once at the end of the test
        """

        if self.n_failed == 0:
            self.output_report("==== PASSED ============================.")
        else:
            self.output_report("**** FAILED ****************************.")

        # Log the total execution time as well as the list of processes that
        # were run, with their duration. This is useful to investigate where
        # time is spent exactly when testcases take too long to run.
        duration = time.time() - self.start_time
        self.log("Total ellapsed time: {:.3f}s".format(duration))
        # Flush the output, in case we forgot to do so earlier.  This has no
        # effect if the flush was already performed.
        self.flush()
        self.report.close()
        exit(0 if self.n_failed == 0 else 1)


thistest = Test()
