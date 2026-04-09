#!/bin/bash

# Aks to dump test inputs, we need to ensure the right warnings are generated
# by gnattest for types which won't support this.
gnattest -P prj.gpr --gen-test-vectors --dump-test-inputs -q
gprbuild -P obj/gnattest/harness/test_driver.gpr -q --src-subdirs=gnattest-instr --implicit-with=obj/gnattest/harness/tgen_support/tgen_support.gpr 
./obj/gnattest/harness/test_runner
