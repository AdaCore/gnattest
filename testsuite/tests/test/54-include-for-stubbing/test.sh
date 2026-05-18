# Scenario 1: refine the stub config locally
gnattest -P p --stub --skeleton-default=pass --include-for-stubbing=global_list.txt --include-for-stubbing=a.ads:a_list.txt
gprbuild -Pgnattest_stub/harness/test_drivers.gpr -q -gnatws
gnattest gnattest_stub/harness/test_drivers.list --passed-tests=hide

# Scenario 2: mix globals include-for-stubbing and exclude-from-stubbing. gnattest should reject this.
gnattest -P p --stub --skeleton-default=pass --include-for-stubbing=global_list.txt --exclude-from-stubbing=global_list.txt

# Scenario 3: mix a global exclude-from-stubbing and a local include-for-stubbing
gnattest -P p --stub --skeleton-default=pass --include-for-stubbing=global_list.txt --exclude-from-stubbing=a.ads:global_list.txt
gprbuild -Pgnattest_stub/harness/test_drivers.gpr -q -gnatws
gnattest gnattest_stub/harness/test_drivers.list --passed-tests=hide

# Scenario 4: mix locals include-for-stubbing and exclude-from-stubbing for the same UUT. gnattest should reject this.
gnattest -P p --stub --skeleton-default=pass --exclude-from-stubbing=a.ads:global_list.txt --include-for-stubbing=a.ads:global_list.txt
