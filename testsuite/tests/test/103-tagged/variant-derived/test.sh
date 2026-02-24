#!/bin/bash

rm -rf obj

LALTOOLS_ROOT=$(dirname $(which gnattest))/..
TEMPLATES_PATH=$LALTOOLS_ROOT/share/tgen/templates
mkdir -p test/obj/gnattest/tests/JSON_Tests obj
tgen_marshalling -P test.gpr --templates-dir=$TEMPLATES_PATH -o obj/tgen_support src/pkg.ads
gprbuild -q -P check.gpr
./obj_check/example_gen

gnattest -P test.gpr --gen-test-vectors
gprbuild -P obj/gnattest/harness/test_driver.gpr -q
./obj/gnattest/harness/test_runner
