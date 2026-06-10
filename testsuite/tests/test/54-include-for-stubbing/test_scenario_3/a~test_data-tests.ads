--  This package has been generated automatically by GNATtest.
--  Do not edit any part of it, see GNATtest documentation for more details.

--  begin read only
with Gnattest_Generated;
with AUnit.Test_Caller;

package a.Test_Data.Tests is

   type Test is new GNATtest_Generated.GNATtest_Standard.a.Test_Data.Test
   with null record;

   procedure Test_show_b_ad0ec9 (Gnattest_T : in out Test);
   --  a.ads:2:4:show_b

   procedure Test_show_c_0921f1 (Gnattest_T : in out Test);
   --  a.ads:3:4:show_c

   package Caller is new AUnit.Test_Caller (Test);

end a.Test_Data.Tests;
--  end read only
