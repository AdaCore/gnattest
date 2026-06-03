------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                    Copyright (C) 2021-2023, AdaCore                      --
--                                                                          --
-- GNATtest  is  free  software; you  can  redistribute  it  and/or  modify --
-- it  under  terms of the  GNU  General  Public  License  as  published by --
-- the Free Software Foundation;  either version 3, or (at your option) any --
-- later version. This software  is distributed in the hope that it will be --
-- useful but  WITHOUT  ANY  WARRANTY; without even the implied warranty of --
-- MERCHANTABILITY  or  FITNESS  FOR A PARTICULAR PURPOSE.                  --
--                                                                          --
-- As a special  exception  under  Section 7  of  GPL  version 3,  you are  --
-- granted additional  permissions described in the  GCC  Runtime  Library  --
-- Exception, version 3.1, as published by the Free Software Foundation.    --
--                                                                          --
-- You should have received a copy of the GNU General Public License and a  --
-- copy of the GCC Runtime Library Exception along with this program;  see  --
-- the files COPYING3 and COPYING.RUNTIME respectively.  If not, see        --
-- <http://www.gnu.org/licenses/>.                                          --
------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Exceptions;

with GNAT.Command_Line;
with GNAT.OS_Lib;

with GNATCOLL.Traces;

with Utils.Command_Lines; use Utils.Command_Lines;
with Utils.Drivers;
with Utils.Environment;
with Utils.Err_Out;
with Utils.Projects;
with Utils.String_Utilities;
with Utils.Tool_Names;

with Utils_Debug; use Utils_Debug;

with Test.Command_Lines; use Test.Command_Lines;
with Test.Actions;
with Test.Setup;

procedure Test.Main is

   --  Main procedure for gnattest

   use Test_String_Switches;

   Tool : Test.Actions.Tool_State;

   Global_Cmd : Command_Line renames Test.Actions.Global_Cmd;

begin
   GNATCOLL.Traces.Parse_Config_File;

   --  By default, send errors to stdout
   Utils.Err_Out.Output_Enabled := True;

   --  Subcommand dispatch: a leading "setup" word routes to the AUnit
   --  setup logic. Anything else falls through to the classic gnattest
   --  pipeline below.

   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "setup"
   then
      Test.Setup.Run;
      return;
   end if;

   Test.Register_Specific_Attributes;

   --  Parse command line switches, load project file, and load extra switches
   --  in project file.

   Utils.Projects.Process_Command_Line
     (Global_Cmd, Print_Help => Test.Actions.Tool_Help'Access);

   if Debug_Flag_C then
      Dump_Cmd (Global_Cmd);
   end if;

   --  Create output directory if necessary

   if Present (Arg (Global_Cmd, Output_Directory)) then
      Utils.Drivers.Make_Dir (Arg (Global_Cmd, Output_Directory).all);
   end if;

   --  Do a lot of initialization work:
   --  - Setup some Test.Common.* values from CLI arguments
   --  - Maybe generate Tgen lib
   --  - Configure Tool variable

   Test.Actions.Init (Tool, Global_Cmd);

   --  Run the heart of gnattest, in generation or aggregation/execution mode.

   Utils.Drivers.Driver (Test.Actions.Global_Cmd, Tool);
exception
   when X : Utils.String_Utilities.File_Not_Found =>
      declare
         use Ada.Exceptions, Utils.Tool_Names;
      begin
         Utils.Err_Out.Put ("\1: \2\n", Tool_Name, Exception_Message (X));
      end;
      Utils.Environment.Clean_Up;
      GNAT.OS_Lib.OS_Exit (1);
   when Utils.Command_Lines.Command_Line_Error =>

      --  Error message has already been printed.

      GNAT.Command_Line.Try_Help;
      Utils.Environment.Clean_Up;
      GNAT.OS_Lib.OS_Exit (1);
   when
     Utils.Command_Lines.Command_Line_Error_No_Help
     | Utils.Command_Lines.Command_Line_Error_No_Tool_Name
   =>
      --  Error message has already been printed.

      Utils.Environment.Clean_Up;
      GNAT.OS_Lib.OS_Exit (1);
end Test.Main;
