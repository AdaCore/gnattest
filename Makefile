# To build in production mode, do  "make LIBRARY_TYPE=static BUILD_MODE=prod".
# To build in development mode, do "make LIBRARY_TYPE=static BUILD_MODE=dev".

BUILD_MODE ?= dev
LIBRARY_TYPE ?= static
PROCESSORS ?= 0
BUILD_ROOT ?=

ALL_LIBRARY_TYPES = static static-pic relocatable
ALL_BUILD_MODES = dev prod AddressSanitizer

LIB_PROJECT = src/gnattest.gpr

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

GPRBUILD = gprbuild -v -k -p \
	   -j$(PROCESSORS) \
	   $(RELOCATE_BUILD)


ifdef INSTRUMENTED
# When instrumenting, expect a "GNATTEST_TRACE_DIR" variable at runtime
# to indicate where to put trace files.
GNATCOV_INSTR = gnatcov instrument \
		-j$(PROCESSORS) \
		--level=stmt \
		--dump-filename-env-var=GNATTEST_TRACE_DIR
GPRBUILD += --implicit-with=gnatcov_rts \
	   --src-subdirs=gnatcov-instr
endif

.PHONY: all
all: bin lib testsuite_drivers

.PHONY: lib
lib:
	which gprbuild
	which gcc
ifdef INSTRUMENTED
	for kind in $(ALL_LIBRARY_TYPES) ; do \
		rm -f obj/lib/$$kind/*.lexch; \
		$(GNATCOV_INSTR) \
			-XLIBRARY_TYPE=$$kind \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $(LIB_PROJECT) ; \
		$(GPRBUILD) \
			-XLIBRARY_TYPE=$$kind \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $(LIB_PROJECT) ; \
	done ;
else
	for kind in $(ALL_LIBRARY_TYPES) ; do \
		rm -f obj/lib/$$kind/*.lexch; \
		$(GPRBUILD) \
			-XLIBRARY_TYPE=$$kind \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $(LIB_PROJECT) ; \
	done ;
endif

.PHONY: bin
bin:
	which gprbuild
	which gcc
ifdef INSTRUMENTED
	$(GNATCOV_INSTR) \
		-XLIBRARY_TYPE=$(LIBRARY_TYPE) \
		-XXMLADA_BUILD=$(LIBRARY_TYPE) \
		-XBUILD_MODE=$(BUILD_MODE) \
		-P $(BIN_PROJECT) ;
endif
	$(GPRBUILD) \
		-XLIBRARY_TYPE=$(LIBRARY_TYPE) \
		-XXMLADA_BUILD=$(LIBRARY_TYPE) \
		-XBUILD_MODE=$(BUILD_MODE) \
		-P $(BIN_PROJECT) ; \

.PHONY: testsuite_drivers
testsuite_drivers:
	which gprbuild
	which gcc
ifdef INSTRUMENTED
	for proj in $(TESTSUITE_PROJECTS) ; do \
		$(GNATCOV_INSTR) \
			-XLIBRARY_TYPE=$(LIBRARY_TYPE) \
			-XXMLADA_BUILD=$(LIBRARY_TYPE) \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $$proj \
			--projects $(LIB_PROJECT) ; \
		$(GPRBUILD) \
			-XLIBRARY_TYPE=$(LIBRARY_TYPE) \
			-XXMLADA_BUILD=$(LIBRARY_TYPE) \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $$proj ; \
	done
else
	for proj in $(TESTSUITE_PROJECTS) ; do \
		$(GPRBUILD) \
			-XLIBRARY_TYPE=$(LIBRARY_TYPE) \
			-XXMLADA_BUILD=$(LIBRARY_TYPE) \
			-XBUILD_MODE=$(BUILD_MODE) \
			-P $$proj ; \
	done
endif

.PHONY: test
test: all
	testsuite/testsuite.py

.PHONY: clean
clean:
	for proj in $(ALL_PROJECTS) ; do \
		for build_mode in $(ALL_BUILD_MODES) ; do \
			for library_type in $(ALL_LIBRARY_TYPES) ; do \
				gprclean $(RELOCATE_BUILD) \
					-XLIBRARY_TYPE=$$library_type \
					-XBUILD_MODE=$$build_mode \
					-q -P $$proj; \
			done ; \
		done ; \
	done

.PHONY: install-lib
install-lib:
	for kind in $(ALL_LIBRARY_TYPES) ; do \
		gprinstall $(RELOCATE_BUILD) \
			-XLIBRARY_TYPE=$$kind \
			-XBUILD_MODE=$(BUILD_MODE) \
			--prefix="$(DESTDIR)" \
			--sources-subdir=include/$$(basename $(LIB_PROJECT) | cut -d. -f1) \
			--build-name=$$kind \
			--build-var=LIBRARY_TYPE \
			-P $(LIB_PROJECT) -p -f ; \
	done ;

.PHONY: install-bin-strip
install-bin-strip:
	mkdir -p "$(DESTDIR)"
	cp -r "$(BIN)" "$(DESTDIR)/"
	# Don't strip debug builds
	test "$(BUILD_MODE)" = dev || strip "$(DESTDIR)/bin/"*

.PHONY: install-tgen
install-tgen:
	mkdir -p "$(DESTDIR)/share/tgen"
	cp -r src/tgen/tgen_rts "$(DESTDIR)/share/tgen/"
	cp -r share/tgen/templates "$(DESTDIR)/share/tgen/"
