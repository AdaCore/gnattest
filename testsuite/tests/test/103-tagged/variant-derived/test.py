"""
Test that TGen is able to generate tests for a derived type of a tagged
record with a variant part.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test.gpr",
    test_prj_src=["src/pkg.ads"],
    check_prj="check.gpr"
)

thistest.result()
