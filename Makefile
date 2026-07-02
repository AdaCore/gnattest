# To build in production mode, do  "make LIBRARY_TYPE=static BUILD_MODE=prod".
# To build in development mode, do "make LIBRARY_TYPE=static BUILD_MODE=dev".

BUILD_MODE ?= dev
GNATTEST_BUILD_MODE ?= $(BUILD_MODE)
TGEN_RTS_BUILD_MODE ?= $(BUILD_MODE)
PROCESSORS ?= 0
BUILD_ROOT ?=

ALL_LIBRARY_TYPES = static static-pic relocatable
ALL_BUILD_MODES = dev prod

# When building the instrumented version, only make the static.
ifdef INSTRUMENTED
LIBRARY_TYPE ?= static
else
LIBRARY_TYPE ?= static static-pic relocatable
endif

INSTR_TARGETS = $(foreach libtype,$(LIBRARY_TYPE),instrument-$(libtype))
LIB_TARGETS = $(foreach libtype,$(LIBRARY_TYPE),lib-$(libtype))
INSTALL_LIB_TARGETS = $(foreach libtype,$(LIBRARY_TYPE),install-lib-$(libtype))

LIB_PROJECT = src/gnattest.gpr
TGEN_RTS_PROJECTS = \
	share/tgen/tgen_rts/tgen_rts.gpr \
	share/tgen/tgen_rts/tgen_marshalling_rts.gpr

BIN_PROJECT = src/build.gpr

TESTSUITE_PROJECTS ?= \
	testsuite/ada_drivers/gen_marshalling_lib/tgen_marshalling.gpr \
	testsuite/ada_drivers/tgen_dump_proc_name/tgen_dump_proc_name.gpr \
	testsuite/ada_drivers/light_marshalling_lib/light_marshalling_lib.gpr

ALL_PROJECTS = \
	$(BIN_PROJECT) $(LIB_PROJECT) $(TESTSUITE_PROJECTS)

ifeq ($(BUILD_ROOT),)
RELOCATE_BUILD=
BIN=bin
else
# build artifacts are relocated to $(BUILD_ROOT)
RELOCATE_BUILD=--relocate-build-tree="$(BUILD_ROOT)" --root-dir=.
BIN=$(BUILD_ROOT)/bin
endif

# gpr* specific arguments
GPR_ARGS = $(RELOCATE_BUILD)


ifdef INSTRUMENTED
GPR_ARGS += --implicit-with=gnatcov_rts \
	   --src-subdirs=gnatcov-instr
endif

# HOST platform
HOST   := $(shell gcc -dumpmachine)
# Get PATH separator for the host
ifeq ($(strip $(findstring mingw32, $(HOST))),mingw32)
PSEP = ;
else
PSEP = :
endif

# Somehow we need to go through cygpath to get a proper Windows path name..
CWD = $(shell pwd)
ifdef CYGWIN
CWD := $(shell cygpath -w $(CWD))
endif


.PHONY: all
all: bin lib testsuite_drivers

# Instrumenting the binary project gives instrumentation for lib and bin
.PHONY: $(INSTR_TARGETS)
$(INSTR_TARGETS):
ifdef INSTRUMENTED
# When instrumenting, expect a "GNATTEST_TRACE_DIR" variable at runtime
# to indicate where to put trace files.
	@echo "=========================================="
	@echo "============= $@ ============="
	@echo "=========================================="
	gnatcov instrument \
	 	-j$(PROCESSORS) \
		$(RELOCATE_BUILD) \
		--level=stmt \
		--dump-filename-env-var=GNATTEST_TRACE_DIR \
		-XLIBRARY_TYPE=$(subst instrument-,,$@) \
		-XXMLADA_BUILD=$(subst instrument-,,$@) \
		-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
		-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
		-P $(BIN_PROJECT) ;
else
# Instrumentation disabled: No-op
endif

.PHONY: $(LIB_TARGETS)
$(LIB_TARGETS): lib-%: instrument-%
	@echo "====================================="
	@echo "============= $@ ============="
	@echo "====================================="
	which gprbuild
	which gcc
	gprbuild \
	 	-j$(PROCESSORS) \
		$(GPR_ARGS) \
		-XLIBRARY_TYPE=$(subst lib-,,$@) \
		-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
		-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
		-P $(LIB_PROJECT)

.PHONY: lib
lib: $(LIB_TARGETS)

.PHONY: bin
bin: instrument-static
	@echo "====================================="
	@echo "============= $@ ============="
	@echo "====================================="
	which gprbuild
	which gcc
	gprbuild \
	 	-j$(PROCESSORS) \
		$(GPR_ARGS) \
		-XLIBRARY_TYPE=static \
		-XXMLADA_BUILD=static \
		-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
		-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
		-P $(BIN_PROJECT) ; \


# Allow for test drivers to be compiled with an externally built gnattest
ifdef EXTERNAL_GNATTEST_GPR
GNATTEST_GPR = $(EXTERNAL_GNATTEST_GPR)
GNATCOV_EXTRA_ARGS = --externally-built-projects --no-subprojects
else
# Look at the source directory in any other case
GNATTEST_GPR = $(CWD)/src
endif

# Note: the quotes in the variable definition bellow are important to prevent
# make from interpreting the Windows path separator ';' as actual command
# sequences when setting the GPR_PROJECT_PATH in the rules bellow.
TEST_GPR_PROJECT_PATH = "$(GNATTEST_GPR)$(PSEP)$(GPR_PROJECT_PATH)"

.PHONY: instrument-drivers
instrument-drivers:
ifdef INSTRUMENTED
	@echo "====================================="
	@echo "====== $@ ======"
	@echo "====================================="

	for proj in $(TESTSUITE_PROJECTS); do \
		echo "Instrumenting $$proj" ; \
		GPR_PROJECT_PATH=$(TEST_GPR_PROJECT_PATH) \
		gnatcov instrument \
			-j$(PROCESSORS) \
			$(RELOCATE_BUILD) \
			$(GNATCOV_EXTRA_ARGS) \
			--level=stmt \
			--dump-filename-env-var=GNATTEST_TRACE_DIR \
			-XLIBRARY_TYPE=static \
			-XXMLADA_BUILD=static \
			-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
			-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
			-P $$proj \
			--projects gnattest.gpr ; \
		done
else
# Instrumentation disabled: No-op
endif

.PHONY: testsuite_drivers
testsuite_drivers: instrument-drivers
	@echo "====================================="
	@echo "========= $@ ========"
	@echo "====================================="
	which gprbuild
	which gcc
	for proj in $(TESTSUITE_PROJECTS) ; do \
		GPR_PROJECT_PATH=$(TEST_GPR_PROJECT_PATH) \
		gprbuild \
			-j$(PROCESSORS) \
			$(GPR_ARGS) \
			-XLIBRARY_TYPE=static \
			-XXMLADA_BUILD=static \
			-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
			-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
			-P $$proj ; \
	done


.PHONY: test
test: all
	testsuite/testsuite.py

.PHONY: clean
clean:
	for proj in $(ALL_PROJECTS) ; do \
		for build_mode in $(ALL_BUILD_MODES) ; do \
			for library_type in $(ALL_LIBRARY_TYPES) ; do \
				GPR_PROJECT_PATH=$$GPR_PROJECT_PATH$(PSEP)$(GNATTEST_GPR) \
				gprclean $(RELOCATE_BUILD) \
					-XLIBRARY_TYPE=$$library_type \
					-XGNATTEST_BUILD_MODE=$$build_mode \
					-q -P $$proj; \
			done ; \
		done ; \
	done
	$(RM) $(find . -name '*.sid')

.PHONY: $(INSTALL_LIB_TARGETS)
$(INSTALL_LIB_TARGETS):
	@echo "=============================="
	@echo "========= $@ ========"
	@echo "=============================="
	gprinstall \
		$(GPR_ARGS) \
		-v \
		-XLIBRARY_TYPE=$(subst install-lib-,,$@) \
		-XGNATTEST_BUILD_MODE=$(GNATTEST_BUILD_MODE) \
		-XTGEN_RTS_BUILD_MODE=$(TGEN_RTS_BUILD_MODE) \
		--prefix="$(DESTDIR)" \
		--sources-subdir=include/$$(basename $(LIB_PROJECT) | cut -d. -f1) \
		--build-name=$(subst install-lib-,,$@) \
		--build-var=LIBRARY_TYPE \
		-P $(LIB_PROJECT) -p -f

.PHONY: install-lib
install-lib: $(INSTALL_LIB_TARGETS)

.PHONY: install-bin-strip
install-bin-strip:
	mkdir -p "$(DESTDIR)"
	cp -r "$(BIN)" "$(DESTDIR)/"
	# Don't strip debug builds
	test "$(BUILD_MODE)" = dev || strip "$(DESTDIR)/bin/"*

.PHONY: install-tgen
install-tgen:
	mkdir -p "$(DESTDIR)/share/tgen"
	cp -r share/tgen/tgen_rts "$(DESTDIR)/share/tgen/"
	cp -r share/tgen/templates "$(DESTDIR)/share/tgen/"

# Path to the AUnit source tree shipped with gnattest. When the submodule
# is wired up this points to aunit/. Override via AUNIT_SRC to build against
# a local checkout during development.
AUNIT_SRC ?= share/aunit

.PHONY: install-aunit
install-aunit:
	@if [ ! -d "$(AUNIT_SRC)/lib/gnat" ] || [ ! -d "$(AUNIT_SRC)/include/aunit" ] ; then \
		echo "error: AUnit sources not found at $(AUNIT_SRC)" ; \
		echo "Either initialize the submodule:" ; \
		echo "    git submodule update --init $(AUNIT_SRC)" ; \
		echo "or point AUNIT_SRC at a local AUnit checkout:" ; \
		echo "    make install-aunit AUNIT_SRC=/path/to/aunit DESTDIR=..." ; \
		exit 1 ; \
	fi
	mkdir -p "$(DESTDIR)/share/aunit"
	cp -r "$(AUNIT_SRC)/include" "$(DESTDIR)/share/aunit/"
	cp -r "$(AUNIT_SRC)/lib"     "$(DESTDIR)/share/aunit/"
