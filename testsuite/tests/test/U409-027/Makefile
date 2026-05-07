.PHONY: all
CROSS_ARGS=
all:
	@gnattest -P p ${CROSS_ARGS}
	@gprbuild -P gnattest/harness/test_driver.gpr -q ${CROSS_ARGS}
	@-gnattest/harness/test_runner > foo\
	&& echo "exit code from gpr not set" || echo -n ""
