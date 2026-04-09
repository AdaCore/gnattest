#! /bin/bash

gnattest -P prj.gpr --gen-test-vectors --dump-test-inputs
gprbuild -P obj/gnattest/harness/test_driver.gpr --src-subdirs=gnattest-instr --implicit-with=obj/gnattest/harness/tgen_support/tgen_support.gpr -q
./obj/gnattest/harness/test_runner

# Generate some binary tests, this will call and exercise the conversion programs
gnattest -P prj.gpr --gen-test-vectors --gen-test-binary --serialized-test-dir=bin_tests
# post process the filenames to make it easier to locate them in the Ada test
# program
ls bin_tests | sed -n 's/\(.*\)\(-[0-9a-f]*-\)\([0-4]\)/mv bin_tests\/\1\2\3 bin_tests\/\1\-\3/p' | sh

# Build the test program to decode the testcase
gprbuild -P test.gpr -q
./obj-test/test_main
