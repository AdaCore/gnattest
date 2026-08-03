#!/usr/bin/env python

"""
Test that TGen is able to generate test for a derived type of a tagged
record with a private component.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test.gpr",
    test_prj_src=["src/pkh.ads"],
)

thistest.result()
