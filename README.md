GNATtest
========

`gnattest` generates unit-test skeletons and a complete test-driver
infrastructure for Ada code, based on [Libadalang](https://github.com/AdaCore/libadalang/).
Given a GNAT project, it produces:

* AUnit-based test skeletons, one per subprogram declared in the project's
  visible specs;
* a test harness (drivers, suites, aggregator) that builds and runs those
  tests and reports results;
* optional stub-based and TGen-based (automatically generated test inputs)
  testing infrastructure.

It also runs the generated drivers and aggregates their results when invoked on
a `test_drivers.list` file.

Run `gnattest --help` for the full list of options.


Requirements
------------

To build `gnattest` you need a GNAT toolchain with `gprbuild`, plus the
following libraries available on your `GPR_PROJECT_PATH`:

* [Libadalang](https://github.com/AdaCore/libadalang/) (`libadalang.gpr`);
* GPR2 (`gpr2.gpr`);
* Templates Parser (`templates_parser.gpr`);
* XML/Ada.

Building against this repository's `main` branch requires the matching
stable releases of Libadalang and Langkit.


Build
-----

From the top of the repository:

```sh
# Build gnattest, its library, and the testsuite drivers.
make

# Install the gnattest binaries into ./local/bin (stripped in prod builds).
make install-bin-strip DESTDIR=local

# Install the TGen support files (runtime sources and templates) into ./local.
make install-tgen DESTDIR=local
```

By default this produces a development build (`BUILD_MODE=dev`). For a
production build, pass `BUILD_MODE=prod`, e.g.:

```sh
make BUILD_MODE=prod LIBRARY_TYPE=static
```

The TGen runtime project must then be built and installed so that generated
drivers can link against it:

```sh
gprbuild   -P local/share/tgen/tgen_rts/tgen_rts.gpr
gprinstall -P local/share/tgen/tgen_rts/tgen_rts.gpr -p
```

After installation, the `gnattest` executable lives in `local/bin/`.


Testing
-------

The testsuite is driven by
[e3-testsuite](https://github.com/AdaCore/e3-testsuite). Install it (e.g.
`pip install e3-testsuite`) and make sure the freshly built `gnattest` is on
your `PATH`.

The simplest way to build everything and run the full testsuite is:

```sh
make test
```

Alternatively, run the testsuite directly. From the `testsuite/` directory:

```sh
./testsuite.py [--setup-tgen-rts]
```

* `--setup-tgen-rts` builds and installs the TGen runtime as part of the run;
  it is only needed if you have not already installed it (see the build step
  above).
* The testsuite writes its report to an `out/` directory in the current
  working directory.

To run only specific testcases, pass their paths as arguments:

```sh
./testsuite.py tests/test/gtest-basic tests/test/60-stub-from-runtime
```

Use `--show-error-output` to see the diff between expected and actual output,
and `./testsuite.py --help` to discover the remaining options. See
[testsuite/README.rst](testsuite/README.rst) for more details.


Contributing
------------

See [CONTRIBUTING.md](CONTRIBUTING.md).


License
-------

All source files in this repository are licensed under the terms of the GNU
General Public License version 3 (GPLv3). See the [LICENSE](LICENSE) file for
more information.
