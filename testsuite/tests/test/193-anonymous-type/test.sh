GNATTEST_ROOT=$(dirname $(which gnattest))/..
TEMPLATES_PATH=$GNATTEST_ROOT/share/tgen/templates
tgen_marshalling -P test.gpr --templates-dir=$TEMPLATES_PATH
