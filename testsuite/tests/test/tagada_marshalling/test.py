#!/usr/bin/env python

"""
Test checking tgen support (dynamic type introspection and binary /
JSON marshallers) for all of the types supported by the library.
"""

from suite.tutils import run_tgen_marshalling_test
from suite.context import thistest

run_tgen_marshalling_test(
    test_prj="test/test",
    test_prj_objdir="test/obj",
    test_prj_src=[
        "test/my_file.ads",
        "test/show_date.ads",
    ],
    check_prj="test_gen.gpr",
)

thistest.result()
