#!/usr/bin/env bash

gnattest -q -P p.gpr --gen-test-vectors
# No supported declarations remain from which to create a test runner.
test $? -eq 1
