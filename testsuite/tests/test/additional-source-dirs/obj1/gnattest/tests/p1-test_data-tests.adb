--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into P1.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only
with Shared_Setup;

--  begin read only
--  end read only
package body P1.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Bump (Gnattest_T : in out Test);
   procedure Test_Bump_400510 (Gnattest_T : in out Test) renames Test_Bump;
--  id:2.2/4005108b36fbabe8/Bump/1/0/
   procedure Test_Bump (Gnattest_T : in out Test) is
   --  p1.ads:2:4:Bump
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Bump (5) = 5 + Shared_Setup.Increment,
         "shared increment not visible");

--  begin read only
   end Test_Bump;
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
end P1.Test_Data.Tests;
