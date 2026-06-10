--  This package has been generated automatically by GNATtest.
--  Do not edit any part of it, see GNATtest documentation for more details.

--  begin read only
with Gnattest_Generated;
with AUnit.Test_Caller;

package b.Test_Data.Tests is

   type Test is new GNATtest_Generated.GNATtest_Standard.b.Test_Data.Test
   with null record;

   procedure Test_func_b_33df42 (Gnattest_T : in out Test);
   --  b.ads:2:4:func_b

   package Caller is new AUnit.Test_Caller (Test);

end b.Test_Data.Tests;
--  end read only
