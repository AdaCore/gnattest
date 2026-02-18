#! /bin/bash

gnattest -P user_project.gpr --gen-test-binary
gnattest -P user_project.gpr --enum-strat
gnattest -P user_project.gpr --gen-test-num=5
gnattest -P user_project.gpr --gen-test-subprograms=foo.ads:5
