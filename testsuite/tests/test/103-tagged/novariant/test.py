#!/usr/bin/env python

"""
Test checking tgen support (dynamic type introspection and binary /
JSON marshallers) for all of the types supported by the library.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test.gpr",
    test_prj_src=["src/pkg.ads"],
)

thistest.result()
