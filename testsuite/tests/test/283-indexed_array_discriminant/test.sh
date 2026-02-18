#!/bin/bash

cd test/
gnattest -Psimple simple.ads
cd obj/gnattest/harness
make > /dev/null
./test_runner --routines=simple.ads:10
