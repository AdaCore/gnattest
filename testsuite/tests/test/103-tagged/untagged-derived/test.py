"""
Test that TGen is able to generate tests for a record derived from a
discriminated untagged record.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test.gpr",
    test_prj_src=["src/pkg.ads"],
)

thistest.result()
