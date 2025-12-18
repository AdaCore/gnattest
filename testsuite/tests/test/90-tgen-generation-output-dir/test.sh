TEST_DIR=generated_tests
export TGEN_GENERATION_OUTPUT_DIR=$TEST_DIR

mkdir -p $TEST_DIR
gnattest  -dn -P user_project.gpr --gen-test-vectors

ls $TEST_DIR
