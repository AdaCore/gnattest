from suite.context import thistest
from suite.tutils import build_harness, run_gnattest, run_harness

for _ in range(2):
    run_gnattest("test.gpr", ["-q", "--skeleton-default=pass"])
    build_harness("obj/gnattest/harness/test_driver.gpr", ["-q"])
    run_harness("obj/gnattest/harness/test_runner")

thistest.result()
