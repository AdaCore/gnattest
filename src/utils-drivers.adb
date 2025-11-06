------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                       Copyright (C) 2021, AdaCore                        --
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
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with GPR2;

with Test.Command_Lines; use Test.Command_Lines;
with Test.Common;
with Test.Generation;

with Utils.Environment;
with Utils.Err_Out;
with Utils.Projects;         use Utils.Projects;
with Utils.Projects.Aggregate;
with Utils.String_Utilities; use Utils.String_Utilities;

with Libadalang.Iterators; use Libadalang.Iterators;

package body Utils.Drivers is

   use Test_Boolean_Switches, Test_String_Seq_Switches;

   use Test.Actions;
   use type GNAT.OS_Lib.String_Access;
   use type GPR2.Project_Kind;

   procedure Driver (Cmd : Command_Line; Tool : in out Tool_State) is
      use String_Sets;

      procedure Process_Files;

      procedure Include_One (File_Name : String);
      --  Include File_Name in the Ignored set below

      Ignored : String_Set;
      --  Set of file names mentioned in the --ignore=... switch

      procedure Include_One (File_Name : String) is
      begin
         Include (Ignored, Ada.Directories.Simple_Name (File_Name));
      end Include_One;

      procedure Process_Files is
         N_File_Names : constant Natural := Num_File_Names (Cmd);

         Counter        : Natural := N_File_Names;
         Has_Syntax_Err : Boolean := False;

         use Ada.Directories;
      begin
         --  First compute the Ignored set by looking at all the --ignored
         --  switches.

         for Ignored_Arg of Arg (Cmd, Ignore) loop
            Read_File_Names_From_File (Ignored_Arg.all, Include_One'Access);
         end loop;

         if Tool.Run_First_Pass then
            if Arg (Cmd, Verbose) then
               Err_Out.Put ("First pass:\n");
            end if;
            for F_Name of File_Names (Cmd) loop
               if not Contains (Ignored, Simple_Name (F_Name.all)) then
                  if Arg (Cmd, Verbose) then
                     Err_Out.Put ("[\1] \2\n", Image (Counter), F_Name.all);
                  end if;

                  Has_Syntax_Err := False;

                  --  Call Create_Context if we don't have one, or after an
                  --  arbitrary number of files.
                  Tool.Maybe_Recreate_Context (Wide_Character_Encoding (Cmd));

                  Process_File
                    (Tool,
                     Cmd,
                     F_Name.all,
                     Counter,
                     Has_Syntax_Err,
                     Pass => First_Pass);
                  if Has_Syntax_Err and then not Utils.Syntax_Errors then
                     Utils.Syntax_Errors := True;
                  end if;
               end if;

               Counter := Counter - 1;
            end loop;

            pragma Assert (Counter = 0);

            --  We always need the lib support when running the generation
            --  harness.

            Test.Common.Generate_TGen_Lib_Support;
            Test.Generation.Generate_Build_And_Run (Cmd);

            Counter := N_File_Names;
            if Arg (Cmd, Verbose) then
               Err_Out.Put ("Second pass:\n");
            end if;
         end if;

         Counter := N_File_Names;

         for F_Name of File_Names (Cmd) loop
            if not Contains (Ignored, Simple_Name (F_Name.all)) then
               if Arg (Cmd, Verbose) then
                  Err_Out.Put ("[\1] \2\n", Image (Counter), F_Name.all);
               elsif not Arg (Cmd, Quiet) and then N_File_Names > 1 then
                  Err_Out.Put ("Units remaining: \1     \r", Image (Counter));
               end if;

               Has_Syntax_Err := False;

               --  Call Create_Context if we don't have one, or after an
               --  arbitrary number of files.
               Tool.Maybe_Recreate_Context (Wide_Character_Encoding (Cmd));

               Process_File
                 (Tool,
                  Cmd,
                  F_Name.all,
                  Counter,
                  Has_Syntax_Err,
                  Pass => Second_Pass);
               if Has_Syntax_Err and then not Utils.Syntax_Errors then
                  Utils.Syntax_Errors := True;
               end if;
            end if;

            Counter := Counter - 1;
         end loop;
         pragma Assert (Counter = 0);
      end Process_Files;

      --  Start of processing for Driver

   begin
      if Project_Tree.Is_Defined
        and then Project_Tree.Root_Project.Kind = GPR2.K_Aggregate
      then
         Aggregate.Process_Aggregated_Projects (Cmd);
      else
         Process_Files;
      end if;

      --  Abort here if we the switch --dump-subp-hash is on. This return
      --  should not be moved further down.

      if Test.Common.Subp_File_Name /= null then
         return;
      end if;

      --  If the project is an aggregate one, exit early and do nothing. The
      --  aggregated projects will be processed in sequence in subprocess calls
      --  made by the driver. Aggregate libraries are excluded: they are
      --  processed as regular projects.

      if Project_Tree.Is_Defined
        and then Project_Tree.Root_Project.Kind = GPR2.K_Aggregate
      then
         return;
      end if;

      --  In any case, generate the support library if needed

      if Test.Common.Get_Lib_Support_Status in Test.Common.Needed then
         Test.Common.Generate_TGen_Lib_Support;
      end if;

      --  Run GNATtest, either in generation or in execution mode.

      if Project_Tree.Is_Defined then
         Generate_Tests (Cmd);
      else
         Run_Tests;
      end if;

      if Test.Common.Strict_Execution
        and then Test.Common.Source_Processing_Failed
      then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;

      Environment.Clean_Up;
      Unload;

      Utils.Main_Done := True;
   end Driver;

   procedure Make_Dir (Dir : String) is
      Cannot_Create : constant String :=
        "cannot create directory '" & Dir & "'";
      use Ada.Directories;
   begin
      if Exists (Dir) then
         if Kind (Dir) /= Directory then
            Cmd_Error (Cannot_Create & "; file already exists");
         end if;
      else
         begin
            Create_Path (Dir);
         exception
            when Name_Error | Use_Error =>
               Cmd_Error (Cannot_Create);
         end;
      end if;
   end Make_Dir;

end Utils.Drivers;
