#!/bin/bash

gnattest -P prj.gpr --gen-test-vectors --gen-test-num=10 -q
gprbuild -P obj/gnattest/harness/test_driver.gpr -q
./obj/gnattest/harness/test_runner
