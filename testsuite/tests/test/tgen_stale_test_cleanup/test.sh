gnattest -P prj.gpr --gen-test-vectors -q

# Modify the signature of the add procedure.
cp src2/simple.ads src/simple.ads
cp src2/simple.adb src/simple.adb

# Regenerate the test with a new signature.
gnattest -P prj.gpr --gen-test-vectors -q

# Check that there is only one spec file for test_add_*.
if [ "$(ls obj/gnattest/tests/simple-test_data-test_add_*.ads | wc -l)" != "1" ]; then
   echo "expected exactly one generated test package for Add, got:"
   ls obj/gnattest/tests/simple-test_data-test_add_*.ads
   exit 1
fi

# Check that the old generated suite package in the harness dir has been removed.
if [ "$(ls obj/gnattest/harness/simple-test_data-test_add_*-suite.ads | wc -l)" != "1" ]; then
   echo "expected exactly one generated suite package for Add, got:"
   ls obj/gnattest/harness/simple-test_data-test_add_*-suite.ads
   exit 1
fi

gprbuild -P obj/gnattest/harness/test_driver.gpr -q
