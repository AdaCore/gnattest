--  This package has been generated automatically by GNATtest.
--  Do not edit any part of it, see GNATtest documentation for more details.

--  begin read only
with Gnattest_Generated;
with AUnit.Test_Caller;

package c.Test_Data.Tests is

   type Test is new GNATtest_Generated.GNATtest_Standard.c.Test_Data.Test
   with null record;

   procedure Test_func_c_15c5a0 (Gnattest_T : in out Test);
   --  c.ads:2:4:func_c

   package Caller is new AUnit.Test_Caller (Test);

end c.Test_Data.Tests;
--  end read only
