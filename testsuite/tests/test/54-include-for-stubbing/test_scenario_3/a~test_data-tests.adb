--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into a.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

with Ada.Text_IO; use Ada.Text_IO;

--  begin read only
--  end read only
package body a.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_show_b (Gnattest_T : in out Test);
   procedure Test_show_b_ad0ec9 (Gnattest_T : in out Test) renames Test_show_b;
--  id:2.2/ad0ec9ab08c616df/show_b/1/0/
   procedure Test_show_b (Gnattest_T : in out Test) is
   --  a.ads:2:4:show_b
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin
      AUnit.Assertions.Assert
        ("original b",
         a.show_b,
         "Unexpected value for a.show_b");

--  begin read only
   end Test_show_b;
--  end read only


--  begin read only
   procedure Test_show_c (Gnattest_T : in out Test);
   procedure Test_show_c_0921f1 (Gnattest_T : in out Test) renames Test_show_c;
--  id:2.2/0921f1dff799818f/show_c/1/0/
   procedure Test_show_c (Gnattest_T : in out Test) is
   --  a.ads:3:4:show_c
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin
      AUnit.Assertions.Assert
        ("original c",
         a.show_c,
         "Unexpected value for a.show_c");

--  begin read only
   end Test_show_c;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end a.Test_Data.Tests;
