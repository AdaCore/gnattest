"""
Check that "gnattest setup --lang" builds only the libraries of the selected
languages, and rejects the languages it cannot set up.
"""

import os

from suite.context import thistest
from suite.tutils import run_wrapper


def setup(prefix, *args):
    p = run_wrapper(
        ["gnattest", "setup", "-q", f"--prefix={prefix}", *args],
        allow_failure=True,
    )
    print(f"status: {p.status}")
    return os.path.join(prefix, "share", "gpr")


def installed(gpr_dir):
    """Names of the project files setup installed, ignoring manifests."""
    if not os.path.isdir(gpr_dir):
        return []
    return sorted(f for f in os.listdir(gpr_dir) if f.endswith(".gpr"))


# Unknown and empty language names
setup("bad", "--lang=foo")
setup("bad", "--lang=c,")

# TGen is an Ada runtime
setup("bad", "--lang=c", "--tgen")

# Google Test needs the full runtime
setup("bad", "--lang=c++", "--rts-profile=zfp")

thistest.fail_if(os.path.exists("bad"), "a rejected setup installed something")

# The names are case insensitive, and no Ada library is built without ada
print(installed(setup("c_cpp", "--lang=C,c++")))

# No C or C++ library is built without c and c++
print(installed(setup("ada", "--lang=ada", "--no-tgen")))

# By default, a library the configuration does not support is skipped:
# Google Test needs the full runtime
print(installed(setup("default_zfp", "--rts-profile=zfp", "--no-tgen")))

thistest.result()
