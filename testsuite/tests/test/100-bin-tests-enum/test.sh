#! /bin/bash

gnattest -P prj.gpr --gen-test-vectors --gen-test-binary --enum-strat --serialized-test-dir=bin-tests -q

# Count the number of tests that we find, only 4 should appear
find bin-tests -name 'ident-*' | wc -l
