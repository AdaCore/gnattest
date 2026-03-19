#!/bin/bash

gnattest -P root.gpr --additional-tests=missing_aunit/extra_tests.gpr
gnattest -P root.gpr --additional-tests=missing_tested_prj/extra_tests.gpr
