#! /bin/bash

# Run without --detect-tgen-proxies=all_refs and check we have unsupported
# types
gnattest -P prj.gpr --gen-test-vectors
rm -r obj/gnattest/tests/

# Run again with it, we should have no unsupported types this time.
gnattest -P prj.gpr --gen-test-vectors --detect-tgen-proxies=all_refs
gprbuild -P obj/gnattest/harness/test_driver.gpr
./obj/gnattest/harness/test_runner
