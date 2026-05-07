from argparse import Namespace
import os
import sys

from drivers.base_driver import BaseDriver
from suite import cutils


class PythonScriptDriver(BaseDriver):
    """
    Driver to run a Python script.

    Interface:

    * put a "test.py" script in the test directory;
    * put a "test.out" text file in the test directory.

    This driver will run the Python script. Its output is then checked against
    the expected output (test.out file). This mechanism is the most flexible
    way to write a testcase, but also the more verbose one and the most complex
    one. Use this driver when no other one fits.
    """

    testcase_cmd: list[str] = []
    testfile_name: str = "test.py"

    def test_dir(self, *args):
        return os.path.join(super().test_dir(), *args)

    # ---------------------------
    # -- Testcase output files --
    # ---------------------------

    def outf(self):
        """
        Name of the file where outputs of the provided test object should go.

        Same location as the test source script, with same name + a .out extra
            suffix extension.
        """
        return self.working_dir("test_instance.out")

    def logf(self):
        """
        Similar to outfile, for the file where logs of the commands executed by
        the provided test object should go.
        """
        return self.working_dir("test_instance.log")

    def errf(self):
        """
        Similar to outf, for the file where diffs of the provided test object
        should go.
        """
        return self.working_dir("test_instance.err")

    @property
    def default_process_timeout(self):
        result = 300

        # Tests run almost 40 times slower under valgrind, so increase the
        # TIMEOUT in that case.
        if self.env.valgrind:
            result *= 40

        return result

    def set_up(self):

        outf = self.outf()
        logf = self.logf()
        errf = self.errf()

        for f in (outf, logf, errf):
            cutils.clear(f)

        self.testcase_cmd.clear()
        self.testcase_cmd.append(sys.executable)
        self.testcase_cmd.append(self.testfile_name)
        self.testcase_cmd.append("--report-file=" + outf)
        self.testcase_cmd.append("--test-log-file=" + logf)
        self.testcase_cmd.append("--error-file=" + errf)


        mopt = self.env.main_options
        if mopt:
            self.set_up_args(mopt)

        return super().set_up()

    def set_up_args(self, mopt: Namespace):
        """
        Build the command arguments that will be passed to the test.
        """
        if mopt.RTS:
            self.testcase_cmd.append("--RTS=%s" % mopt.RTS)

        if mopt.target:
            self.testcase_cmd.append("--target=%s" % mopt.target)

        if mopt.build:
            self.testcase_cmd.append("--build=%s" % mopt.build)

        if self.env.root_dir: 
            self.testcase_cmd.append("--root-dir=%s" % self.env.root_dir)

    def run(self):
        env = dict(os.environ)
        old_path = env.get("PYTHONPATH", "")
        if old_path:
            new_path = "{}{}{}".format(
                self.env.get_attr("root_dir", ""), os.path.pathsep, old_path
            )
        else:
            new_path = self.env.get_attr("root_dir", "")
        env["PYTHONPATH"] = new_path

        self.shell(self.testcase_cmd, env=env)
