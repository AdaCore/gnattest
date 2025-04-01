#!/bin/bash

rm -rf obj

LALTOOLS_ROOT=$(dirname $(which gnattest))/..
TEMPLATES_PATH=$LALTOOLS_ROOT/share/tgen/templates
mkdir -p test/obj/gnattest/tests/JSON_Tests obj
tgen_marshalling -P test.gpr --templates-dir=$TEMPLATES_PATH -o obj/tgen_support src/pkg.ads
gprbuild -q -P obj/tgen_support/tgen_support.gpr

gnattest test.gpr --gen-test-vectors
gprbuild -P obj/gnattest/harness/test_driver.gpr -q
./obj/gnattest/harness/test_runner
