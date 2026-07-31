from glob import glob
import os
from pathlib import Path

from suite.context import thistest
from suite.tutils import run_gnattest, build_harness, run_harness

if thistest.test_env.get("default-gpr", False):
    gpr_file = os.path.join(thistest.homedir, "user_project.gpr")
else:
    gpr_file_candidates = glob(os.path.join(thistest.homedir, "*.gpr"), recursive=False)
    gpr_file_candidates.sort()

    thistest.fail_if(
        len(gpr_file_candidates) == 0,
        "Could not find gpr project file on which to run gnattest."
        f" (cwd: {thistest.homedir})"
    )
    gpr_file = gpr_file_candidates[0]

gnattest_args = [
    "--gen-test-vectors",
    "-gnat2022",
    "-q",
]

# Suppress test input dumping if specified in the test.yaml file, or in cross contexts
if not thistest.test_env.get("suppress_test_dump", False) and not thistest.env.is_cross:
    gnattest_args.append("--dump-test-inputs")

test_name = os.path.basename(thistest.homedir)
if test_name.startswith("ag") or test_name.startswith("eag"):
    gnattest_args.append("--gen-wrappers")

# Append extra arguments specified in the test.yaml file
gnattest_args += thistest.test_env.get("extra_gnattest_args", [])

run_gnattest(gpr_file, gnattest_args)

# Get the object directory to be able to build the harness. This assumes
# there is no Harness_Dir attribute in the project file.
harness_dir = thistest.test_env.get(
    "harness_dir",
    os.path.join(thistest.homedir, "obj", "gnattest", "harness"),
)
harness_dir = ""
for path in Path(thistest.homedir).rglob('harness'):
    harness_dir = path

td_prj = os.path.join(harness_dir, "test_driver.gpr")
support_lib_prj = os.path.join(harness_dir, "tgen_support", "tgen_support.gpr")
thistest.fail_if(not os.path.exists(td_prj), "Could not locate test harness project")

# Determine if the test harness needs to be compiled for test dumping mode
has_test_dump = "--dump-test-inputs" in gnattest_args
gprbuild_args = ["-q"]
if has_test_dump:
    gprbuild_args += [
        "--src-subdirs=gnattest-instr",
        f"--implicit-with={support_lib_prj}",
    ]

# Disable dynamic elaboration model that some of the gnatfuzz tests enable,
# they are very verbose, as well as the optional warnings some of the projects
# enable
gprbuild_args += ["-cargs", "-gnatwA", "-gnatJ", "-bargs", "-ws"]

# Append extra gpbuild args if specified in the test.yaml file
gprbuild_args += thistest.test_env.get("extra_gprbuild_args", [])

build_harness(td_prj, gprbuild_args)

if not thistest.test_env.get("suppress_test_runner_execution", False):
    # Finally, run the test harness. Do not register failure exit codes as
    # it is likely that some tests may crash the subprogram under test.
    td_runner = os.path.join(os.path.dirname(td_prj), "test_runner")
    run_harness(td_runner, thistest.test_env.get("extra_run_args", []))

    # Log the number of test files that were created by the test runner, if
    # test input dumping was enabled.
    if has_test_dump:
        num_tests = len(
            glob(os.path.join(thistest.homedir, "tgen_test_inputs", "*"))
        )
        print(f"Test runner dumped {num_tests} tests")

thistest.result()
