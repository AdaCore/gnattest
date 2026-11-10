"""
Check that gnattest warns about stub list entries that do not name a spec of
the project, and about lists with no valid entry at all.
"""

import glob

from suite.context import thistest
from suite.tutils import run_gnattest


def run(args):
    """Run gnattest in stub mode and print only its warnings."""
    p = run_gnattest("p.gpr", ["--stub"] + args, output_in_baseline=False)
    for line in p.out.splitlines():
        if "warning" in line:
            print(line, flush=True)


def stubs_mention(name):
    """Whether any generated test file mentions name."""
    for path in glob.glob("gnattest_stub/tests/*"):
        with open(path) as f:
            if name in f.read():
                return True
    return False


print("== Invalid entries are reported one by one", flush=True)
run(["--exclude-from-stubbing=mixed_list.txt"])
thistest.fail_if(
    stubs_mention("Set_Stub_func_b"), "valid entry b.ads was not kept"
)

print("== A file with no valid entry is reported as a whole", flush=True)
run(["--exclude-from-stubbing=b.adb"])

print("== The spec of a UUT-specific list must be a project spec", flush=True)
run(["--exclude-from-stubbing=z.ads:valid_list.txt"])

print("== Valid lists do not warn", flush=True)
run(
    [
        "--exclude-from-stubbing=valid_list.txt",
        "--exclude-from-stubbing=a.ads:valid_list.txt",
    ]
)

thistest.result()
