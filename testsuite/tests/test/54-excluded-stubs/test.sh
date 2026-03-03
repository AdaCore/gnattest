gnattest -P p -q --stub --skeleton-default=pass --exclude-from-stubbing=global_list.txt --exclude-from-stubbing=a.ads:a_list.txt

# Make sure that no stubs are generated for b
! grep -q "Set_Stub_func_b"

# Make sure that no call to C stub setters are generated in A tests
! grep -q "Set_Stub_func_c" gnattest_stub/tests/a~test_data-tests.adb
