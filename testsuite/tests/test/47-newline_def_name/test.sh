#!/bin/bash

gnattest -P prj.gpr --stub
gprbuild -P obj/gnattest_stub/harness/test_drivers.gpr
gnattest obj/gnattest_stub/harness/test_drivers.list
