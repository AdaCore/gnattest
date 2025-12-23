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

with Ada.Directories;
with Ada.Exceptions;

with GNAT.Command_Line;
with GNAT.OS_Lib;

with GPR2;

with Test.Command_Lines; use Test.Command_Lines;

with Utils.Environment;
with Utils.Err_Out;
with Utils.Projects;         use Utils.Projects;
with Utils.Projects.Aggregate;
with Utils.String_Utilities; use Utils.String_Utilities;
with Utils.Tool_Names;

with Libadalang.Iterators; use Libadalang.Iterators;

package body Utils.Drivers is

   use Test_Boolean_Switches, Test_String_Switches, Test_String_Seq_Switches;

   use Test.Actions;
   use type GNAT.OS_Lib.String_Access;

   procedure Driver
     (Cmd                   : in out Command_Line;
      Tool                  : in out Tool_State;
      Preprocessing_Allowed : Boolean := True)
   is
      use String_Sets;

      procedure Process_Files;

      procedure Print_Help;

      Global_Report_Dir : String_Ref;

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
                  Process_File
                    (Tool,
                     Cmd,
                     F_Name.all,
                     Counter,
                     Has_Syntax_Err,
                     Pass                  => First_Pass,
                     Preprocessing_Allowed => Preprocessing_Allowed);
                  if Has_Syntax_Err and then not Utils.Syntax_Errors then
                     Utils.Syntax_Errors := True;
                  end if;
               end if;

               Counter := Counter - 1;
            end loop;

            pragma Assert (Counter = 0);
            Tool.First_Pass_Post_Process (Cmd);
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
               Process_File
                 (Tool,
                  Cmd,
                  F_Name.all,
                  Counter,
                  Has_Syntax_Err,
                  Pass                  => Second_Pass,
                  Preprocessing_Allowed => Preprocessing_Allowed);
               if Has_Syntax_Err and then not Utils.Syntax_Errors then
                  Utils.Syntax_Errors := True;
               end if;
            end if;

            Counter := Counter - 1;
         end loop;
         pragma Assert (Counter = 0);
      end Process_Files;

      procedure Print_Help is
      begin
         Tool_Help (Tool);
      end Print_Help;

      --  Start of processing for Driver

   begin
      Process_Command_Line
        (Cmd, Global_Report_Dir, Print_Help => Print_Help'Access);

      if Debug_Flag_C then
         Dump_Cmd (Cmd);
      end if;

      --  Create output directory if necessary

      if Present (Arg (Cmd, Output_Directory)) then
         declare
            Dir           : constant String := Arg (Cmd, Output_Directory).all;
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
         end;
      end if;

      Init (Tool, Cmd);

      if Project_Tree.Is_Defined
        and then Project_Tree.Root_Project.Kind in GPR2.Aggregate_Kind
      then
         Aggregate.Process_Aggregated_Projects (Cmd);
      else
         Process_Files;
      end if;

      Final (Tool, Cmd);
      Environment.Clean_Up;
      Unload;

      Utils.Main_Done := True;

   exception
      when X : File_Not_Found =>
         declare
            use Ada.Exceptions, Utils.Tool_Names;
         begin
            Err_Out.Put ("\1: \2\n", Tool_Name, Exception_Message (X));
         end;
         Environment.Clean_Up;
         GNAT.OS_Lib.OS_Exit (1);
      when Utils.Command_Lines.Command_Line_Error =>

         --  Error message has already been printed.

         GNAT.Command_Line.Try_Help;
         Environment.Clean_Up;
         GNAT.OS_Lib.OS_Exit (1);
      when
        Utils.Command_Lines.Command_Line_Error_No_Help
        | Utils.Command_Lines.Command_Line_Error_No_Tool_Name
      =>
         --  Error message has already been printed.

         Environment.Clean_Up;
         GNAT.OS_Lib.OS_Exit (1);
   end Driver;

end Utils.Drivers;
