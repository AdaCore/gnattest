#!/bin/sh

gnattest -P nested/prj_1/prj_1.gpr -q

# check that the tests produced for nested/prj_1 are in the expected location
find nested/prj_1/foo -name 'pkg-test_data.adb'
