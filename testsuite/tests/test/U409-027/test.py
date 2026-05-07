from subprocess import PIPE
from suite.context import thistest
from suite.tutils import build_harness, run_gnattest, run_harness 

run_gnattest("p.gpr")
build_harness("gnattest/harness/test_driver.gpr", ["-q"])
ret = run_harness("gnattest/harness/test_runner", allow_failure=True, output=PIPE)

lines = ret.out.split("\n")
if 's)' not in lines[0]:
    print('test duration missing')
