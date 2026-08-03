#!/usr/bin/env python

"""
Test that TGen is able to generate tests for a derived type of a
discriminated tagged record defined using discriminant correspondance.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test.gpr",
    test_prj_src=["src/pkg.ads"],
)

thistest.result()
