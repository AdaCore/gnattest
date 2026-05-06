------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                     Copyright (C) 2021-2025, AdaCore                     --
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

with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Directories;         use Ada.Directories;
with Ada.Environment_Variables;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.Directory_Operations;
with GNAT.OS_Lib; use GNAT.OS_Lib;

with GNATCOLL.JSON; use GNATCOLL.JSON;
with GNATCOLL.VFS;  use GNATCOLL.VFS;

with Langkit_Support.Diagnostics;
with Langkit_Support.Errors;
with Langkit_Support.File_Readers;
with Langkit_Support.Text;

with GPR2; use GPR2;
pragma Warnings (Off);
with GPR2.Build.Source.Sets;
pragma Warnings (On);
with GPR2.Path_Name.Set;
with GPR2.Path_Name;
with GPR2.Project.Attribute;
with GPR2.Project.Attribute_Index;
with GPR2.Project.Tree;
with GPR2.Project.View;

with Libadalang;               use Libadalang;
with Libadalang.Common;
with Libadalang.Iterators;     use Libadalang.Iterators;
with Libadalang.Preprocessing; use Libadalang.Preprocessing;
with Libadalang.Project_Provider;

with Test.Aggregator;
with Test.Common;
use type Test.Common.Reporters;
with Test.Command_Lines; use Test.Command_Lines;
with Test.Generation;
with Test.Harness;
with Test.Harness.Source_Table;
with Test.Mapping;
with Test.Skeleton;
with Test.Skeleton.Source_Table;
with Test.Suite_Min;

with TGen.LAL_Utils;
with TGen.Libgen;

with Utils.Err_Out;
with Utils.Formatted_Output; use Utils.Formatted_Output;
with Utils.Projects;         use Utils.Projects;
with Utils.String_Utilities; use Utils.String_Utilities;

with Utils_Debug;

package body Test.Actions is

   procedure Process_Exclusion_List
     (Value : String; From_Project : Boolean := False);
   --  Processes value of --exclude-from-stubbing switch. If values come from
   --  project attributes they do not override already stored ones.

   procedure Check_Direct;
   --  Checks if there are no intersections between target and source dirs.
   --  If everything is fine, tries to create target dirs.

   procedure Check_Subdir;
   --  Checks if there are no intersections between target and source dirs.
   --  If everything is fine, tries to create all target subdirs.

   procedure Check_Separate_Root;
   --  Checks if there are no intersections between target and source dirs.
   --  If everything is fine, tries to create a directory hierarchy similar
   --  to one of the tested sources.

   procedure Check_Stub;
   --  Checks if there are no intersections between stub and source dirs and
   --  between stub and test dirs.

   function Non_Null_Intersection
     (Left : File_Array_Access; Right : File_Array) return Boolean;
   --  Returns True if two file arrays have at least one common file.

   procedure Process_Additional_Tests (Cmd : Command_Line);
   --  Loads the project containing additional tests and processes them.
   --  This project needs to get loaded with the same environment as the
   --  argument one.

   procedure Dump_Subprogram_Hash (File_Name : String; Unit : Analysis_Unit);
   --  Print the hash of the subprogram at file:line in the standard output.

   function Get_All_Units (Decl : Base_Type_Decl) return Analysis_Unit_Array;
   --  Helper for TGen to search for proxy subprograms in all units of the
   --  project.

   pragma Warnings (Off); -- ????
   --  These use clauses will be necessary later.
   --  At least some of them.

   use Ada_Version_Switches, Test_Nat_Switches, Test_String_Seq_Switches;

   use Test_Boolean_Switches, Test_String_Switches, Test_String_Seq_Switches;
   pragma Warnings (On);

   type Additional_Tests_Event_Handler is new Event_Handler_Interface
   with null record;

   procedure Unit_Requested_Callback
     (Self               : in out Additional_Tests_Event_Handler;
      Context            : Analysis_Context'Class;
      Name               : Langkit_Support.Text.Text_Type;
      From               : Analysis_Unit'Class;
      Found              : Boolean;
      Is_Not_Found_Error : Boolean);
   --  Report when a unit is not found while processing additional tests.
   --  This is usually an indication that the project passed to
   --  --additional-tests has errors, such as a missing dependency on Aunit
   --  or on the tested project.

   procedure Release (Self : in out Additional_Tests_Event_Handler) is null;
   --  Nothing to release as Additional_Tests_Event_Handler is only used to
   --  provide a callback.

   ATEH_Instance : constant Additional_Tests_Event_Handler :=
     Additional_Tests_Event_Handler'(null record);
   --  Instance from which we'll create the event handler.

   ----------------------------
   -- Maybe_Recreate_Context --
   ----------------------------

   procedure Maybe_Recreate_Context
     (Tool : in out Tool_State; Char_Encoding : String) is
   begin
      if Tool.Context = No_Analysis_Context
        or else Tool.Ctx_Counter = Max_Files_Per_Context
      then
         declare
            Default_Config : Libadalang.Preprocessing.File_Config;
            File_Configs   : Libadalang.Preprocessing.File_Config_Maps.Map;
            File_Reader    :
              Langkit_Support.File_Readers.File_Reader_Reference :=
                Langkit_Support.File_Readers.No_File_Reader_Reference;

            Provider : constant Unit_Provider_Reference :=
              Libadalang.Project_Provider.Create_Project_Unit_Provider
                (Tree => Project_Tree);

         begin
            --  Check if there are preprocessing directives and if so, update
            --  the File_Reader.

            Libadalang.Preprocessing.Extract_Preprocessor_Data_From_Project
              (Tree           => Project_Tree,
               Default_Config => Default_Config,
               File_Configs   => File_Configs);

            if Default_Config.Enabled or not File_Configs.Is_Empty then
               File_Reader :=
                 Libadalang.Preprocessing.Create_Preprocessor
                   (Default_Config, File_Configs);
            end if;

            Tool.Context :=
              Create_Context
                (Charset       => Char_Encoding,
                 File_Reader   => File_Reader,
                 Unit_Provider => Provider);
            Tool.Ctx_Counter := 0;
         end;
      else
         Tool.Ctx_Counter := Tool.Ctx_Counter + 1;
      end if;
   end Maybe_Recreate_Context;

   ------------------
   -- Process_File --
   ------------------

   procedure Process_File
     (Tool         : Tool_State;
      Cmd          : Command_Line;
      File_Name    : String;
      Counter      : Natural;
      Syntax_Error : out Boolean;
      Reparse      : Boolean := False;
      Pass         : Pass_Kind := Second_Pass) is
   begin
      declare
         Unit : constant Analysis_Unit :=
           Get_From_File (Tool.Context, File_Name, Reparse => Reparse);
      begin
         Syntax_Error := False;

         if Has_Diagnostics (Unit) then
            Syntax_Error := True;
            Utils.Err_Out.Put
              ("Syntax errors in \1\n",
               Ada.Directories.Simple_Name (File_Name));

            for D of Libadalang.Analysis.Diagnostics (Unit) loop
               Utils.Err_Out.Put
                 ("\1\n", Langkit_Support.Diagnostics.To_Pretty_String (D));
            end loop;

            if Pass = Second_Pass then
               Test.Common.Source_Processing_Failed := True;
            end if;

         else
            declare
               use Ada.Strings.Unbounded;
            begin
               pragma Assert (not Root (Unit).Is_Null);
               case Pass is
                  when First_Pass  =>
                     Test.Generation.Process_Source (Unit);

                  when Second_Pass =>
                     if Utils_Debug.Debug_Flag_V then
                        Print (Unit);
                        Put ("With trivia\n");
                        PP_Trivia (Unit);
                     end if;

                     if Test.Common.Subp_File_Name /= null then
                        Dump_Subprogram_Hash (File_Name, Unit);
                        return;
                     end if;

                     if Test.Common.Harness_Only then
                        Test.Harness.Process_Source (Unit);
                     else
                        Test.Skeleton.Process_Source (Unit);
                     end if;
               end case;
            end;
         end if;
      end;
   end Process_File;

   ----------
   -- Init --
   ----------

   procedure Init (Tool : in out Tool_State; Cmd : in out Command_Line) is
      Tmp   : GNAT.OS_Lib.String_Access;
      Files : File_Array_Access;

      Root_Prj : GPR2.Project.View.Object;

      type Output_Mode_Type is (Root_Mode, Subdir_Mode, Direct_Mode);
      Output_Mode : Output_Mode_Type := Direct_Mode;

      --  Flags for default output dirs being set explicitly:
      Stub_Dir_Set    : Boolean := False;
      Tests_Dir_Set   : Boolean := False;
      Harness_Dir_Set : Boolean := False;

      Ignored : Test.Common.String_Set.Set;
      --  Set of file names mentioned in the --ignore=... switch

      procedure Report_Multiple_Output
        (Second_Output_Mode : Output_Mode_Type;
         From_Project       : Boolean := False);
      --  Issue message about switches that correspond to Output_Mode and
      --  Second_Output_Mode are mutually exclusive and raise
      --  Command_Line_Error.

      procedure Report_Multiple_Output
        (Second_Output_Mode : Output_Mode_Type;
         From_Project       : Boolean := False)
      is
         function Mode_Image_Cmd (M : Output_Mode_Type) return String
         is (case M is
               when Root_Mode   => "--tests-root",
               when Subdir_Mode => "--subdirs",
               when Direct_Mode => "--tests-dir");

         function Mode_Image_Att (M : Output_Mode_Type) return String
         is (case M is
               when Root_Mode   => "Tests_Root",
               when Subdir_Mode => "Subdir",
               when Direct_Mode => "Tests_Dir");
      begin
         Test.Common.Report_Err ("multiple output modes are not allowed");
         if From_Project then
            Cmd_Error_No_Help
              ("attributes "
               & Mode_Image_Att (Output_Mode)
               & " and "
               & Mode_Image_Att (Second_Output_Mode)
               & " are mutually exclusive");
         else
            Cmd_Error_No_Help
              ("options "
               & Mode_Image_Cmd (Output_Mode)
               & " and "
               & Mode_Image_Cmd (Second_Output_Mode)
               & " are mutually exclusive");
         end if;
      end Report_Multiple_Output;

      function Process_Comma_Separated_String
        (String_List : String) return Test.Common.Unbounded_String_Vector;
      --  Process a string of comma separated values and returns a vectors of
      --  the values. An empty String produces and empty vector.
      --  It is up to the caller to free the allocated strings.

      function Process_Comma_Separated_String
        (String_List : String) return Test.Common.Unbounded_String_Vector
      is
         Result      : Test.Common.Unbounded_String_Vector;
         Value_Begin : Positive := 1;
         Value_End   : Positive := 1;

      begin
         if String_List = "" then
            return Result;
         end if;

         while Value_End < String_List'Length loop
            if String_List (Value_End) = ',' then
               Result.Append
                 (Ada.Strings.Unbounded.To_Unbounded_String
                    (String_List (Value_Begin .. Value_End - 1)));
               Value_Begin := Value_End + 1;
            end if;

            Value_End := @ + 1;
         end loop;

         if Value_End - Value_Begin >= 1 then
            Result.Append
              (Ada.Strings.Unbounded.To_Unbounded_String
                 (String_List (Value_Begin .. Value_End)));
         end if;

         return Result;
      end Process_Comma_Separated_String;
   begin
      Test.Common.Verbose := Arg (Cmd, Verbose);
      Test.Common.Quiet := Arg (Cmd, Quiet);
      Test.Common.Instrument := Arg (Cmd, Dump_Test_Inputs);
      Test.Common.Lang_Version := Arg (Cmd);

      --  If the tool project is an aggregate one, exit early and do nothing.
      --  The aggregated projects will be processed in sequence in subprocess
      --  calls made by the driver.

      if Project_Tree.Is_Defined
        and then Project_Tree.Root_Project.Kind in Aggregate_Kind
      then
         return;
      end if;

      if Arg (Cmd, Dump_Subp_Hash) /= null then
         Test.Common.Subp_File_Name :=
           new String'
             (Test.Common.Parse_File_And_Number
                ("--dump-subp-hash",
                 Arg (Cmd, Dump_Subp_Hash).all,
                 Test.Common.Subp_Line_Nbr));
         Test.Command_Lines.Test_Boolean_Switches.Set_Arg (Cmd, Quiet, True);
      end if;

      --  Passed_Tests
      declare
         Passed_Test_Arg     : constant String_Ref := Arg (Cmd, Passed_Tests);
         Present             : constant Boolean := Passed_Test_Arg /= null;
         Passed_Test_Arg_Val : constant String :=
           (if Present then To_Lower (Passed_Test_Arg.all) else "");
      begin
         if Present then
            if Passed_Test_Arg_Val = "hide" then
               Test.Common.Show_Passed_Tests := False;

            elsif Passed_Test_Arg_Val = "show" then
               Test.Common.Show_Passed_Tests := True;

            else
               Cmd_Error_No_Help
                 ("--passed-tests should be either show or hide");
            end if;
         end if;
      end;

      --  Exit status
      --
      --  If this switch is used and set to "on" for the test drivers'
      --  generation it must also be used at the test driver's execution if
      --  it is done throught the "gnattest test_drivers.list" command. This
      --  is needed to avoid confusing an unexpected non-zero error code
      --  (crash) of a driver with one that simply signals the failure of at
      --  least on test.
      declare
         Exit_Status_Switch : constant String_Ref := Arg (Cmd, Exit_Status);
         Present            : constant Boolean := Exit_Status_Switch /= null;
         Exit_Status_Val    : constant String :=
           (if Present then To_Lower (Exit_Status_Switch.all) else "");
      begin
         if Present then
            if Exit_Status_Val = "off" then
               Test.Common.Add_Exit_Status := False;

            elsif Exit_Status_Val = "on" then
               Test.Common.Add_Exit_Status := True;

            else
               Cmd_Error_No_Help ("--exit-status should be either on or off");
            end if;
         end if;
      end;

      if not Project_Tree.Is_Defined then
         if Arg (Cmd, Subdirs) /= null then
            GNAT.OS_Lib.Free (Test.Common.Aggregate_Subdir_Name);
            Test.Common.Aggregate_Subdir_Name :=
              new String'(Arg (Cmd, Subdirs).all);
         end if;

         for File of File_Names (Cmd) loop

            if GNAT.Directory_Operations.File_Extension (File.all)
               in ".ads" | ".adb"
            then
               --  No project is specified but there are argument sources.
               --  Most probably user forgot to specify the project, and since
               --  gnattest cannot work without a project file it only makes
               --  sense to stop here.
               Cmd_Error_No_Help ("project file not specified");
            end if;

            Tmp :=
              new String'
                (GNAT.OS_Lib.Normalize_Pathname
                   (File.all,
                    Resolve_Links  => False,
                    Case_Sensitive => False));
            if not GNAT.OS_Lib.Is_Regular_File (Tmp.all) then
               Cmd_Error_No_Help ("cannot find " & Tmp.all);
            end if;
            Test.Aggregator.Add_Drivers_To_List (Tmp.all);
            GNAT.OS_Lib.Free (Tmp);
         end loop;

         if Arg (Cmd, Jobs) = 0 then
            Cmd_Error_No_Help (" -j should be a positive number");
         else
            Test.Common.Queues_Number := Arg (Cmd, Jobs);
         end if;

         --  Dealing with environment dir to copy
         if Arg (Cmd, Copy_Environment) /= null then
            Test.Common.Environment_Dir :=
              new String'
                (Normalize_Pathname
                   (Arg (Cmd, Copy_Environment).all,
                    Resolve_Links  => False,
                    Case_Sensitive => False));
            if not Is_Directory (Test.Common.Environment_Dir.all) then
               Cmd_Error_No_Help
                 ("environment dir "
                  & Test.Common.Environment_Dir.all
                  & " does not exist");
            end if;
         end if;

         --  Clearing argument files so that the driver does not try to process
         --  them as ada sources.
         Clear_File_Names (Cmd);

         --  Aggregation mode does not require any further processing
         return;
      end if;

      Test.Common.Target_Val := new String'(String (Project_Tree.Target));
      Test.Common.RTS_Attribute_Val :=
        new String'(String (Project_Tree.Runtime (Ada_Language)));

      Root_Prj := Project_Tree.Root_Project;
      Test.Common.Object_Directory :=
        new String'(Root_Prj.Object_Directory.String_Value);

      declare
         procedure Include_One (File_Name : String);
         --  Include File_Name in the Ignored set

         procedure Include_One (File_Name : String) is
         begin
            Ignored.Include (Ada.Directories.Simple_Name (File_Name));
         end Include_One;
      begin
         for Ignored_Arg of Arg (Cmd, Ignore) loop
            Read_File_Names_From_File (Ignored_Arg.all, Include_One'Access);
         end loop;
      end;

      declare
         Attr_Value : GPR2.Project.Attribute.Object;
      begin
         if Root_Prj.Check_Attribute
              (Root_Attribute ("runtime"),
               GPR2.Project.Attribute_Index.Create (Ada_Language),
               Result => Attr_Value)
         then
            Test.Common.RTS_Attribute_Val :=
              new String'(String (Attr_Value.Value.Text));
         end if;
      end;

      if Arg (Cmd, Recursive) then
         --  We need to override the list of argument sources. Switch -r is
         --  a legacy switch equal to -U without parameter that other tools
         --  do not have. We can also optimise a bit, since gnattest only cares
         --  about units specs as entry points of analysis.
         Clear_File_Names (Cmd);
         for S of Project_Tree.Root_Project.Visible_Sources loop
            if not Ignored.Contains (String (S.Path_Name.Simple_Name))
              and then S.Language = Ada_Language
              and then S.Unit.Kind = S_Spec
              and then not S.Owning_View.Is_Externally_Built
            then
               Append_File_Name (Cmd, S.Path_Name.String_Value);
            end if;
         end loop;
      end if;

      if Arg (Cmd, Harness_Only) then
         Test.Common.Harness_Only := True;

         if Arg (Cmd, Additional_Tests) /= null then
            Cmd_Error_No_Help
              ("--harness only and --additional-tests are mutually exclusive");
         elsif Root_Prj.Has_Attribute (+Additional_Tests_Attr) then
            Cmd_Error_No_Help
              ("--harness only and Gnattest.Additional_Tests "
               & "are mutually exclusive");
         end if;
      end if;

      --  Check for multiple output modes
      if Arg (Cmd, Tests_Dir) /= null then

         Output_Mode := Direct_Mode;

         if Arg (Cmd, Tests_Root) /= null then
            Report_Multiple_Output (Root_Mode);
         elsif Arg (Cmd, Subdirs) /= null then
            Report_Multiple_Output (Subdir_Mode);
         end if;

         Tests_Dir_Set := True;
         Free (Test.Common.Test_Dir_Name);
         Test.Common.Test_Dir_Name := new String'(Arg (Cmd, Tests_Dir).all);

      elsif Arg (Cmd, Tests_Root) /= null then

         Output_Mode := Root_Mode;

         if Arg (Cmd, Subdirs) /= null then
            Report_Multiple_Output (Subdir_Mode);
         end if;

         Tests_Dir_Set := True;
         Test.Common.Separate_Root_Dir :=
           new String'(Arg (Cmd, Tests_Root).all);

      elsif Arg (Cmd, Subdirs) /= null then

         Output_Mode := Subdir_Mode;
         Tests_Dir_Set := True;
         Test.Common.Test_Subdir_Name := new String'(Arg (Cmd, Subdirs).all);

      else

         if Root_Prj.Has_Attribute (+Tests_Dir_Attr) then

            Output_Mode := Direct_Mode;

            if Root_Prj.Has_Attribute (+Tests_Root_Attr) then
               Report_Multiple_Output (Root_Mode, True);
            elsif Root_Prj.Has_Attribute (+Subdir_Attr) then
               Report_Multiple_Output (Subdir_Mode, True);
            end if;

            Tests_Dir_Set := True;
            Free (Test.Common.Test_Dir_Name);
            Test.Common.Test_Dir_Name :=
              new String'(Attr_Value (Root_Prj, +Tests_Dir_Attr));

         elsif Root_Prj.Has_Attribute (+Tests_Root_Attr) then

            Output_Mode := Root_Mode;

            if Root_Prj.Has_Attribute (+Subdir_Attr) then
               Report_Multiple_Output (Subdir_Mode, True);
            end if;

            Tests_Dir_Set := True;
            Test.Common.Separate_Root_Dir :=
              new String'
                (String (Root_Prj.Attribute (+Tests_Root_Attr).Value.Text));

         elsif Root_Prj.Has_Attribute (+Subdir_Attr) then

            Output_Mode := Subdir_Mode;
            Tests_Dir_Set := True;
            Test.Common.Test_Subdir_Name :=
              new String'
                (String (Root_Prj.Attribute (+Subdir_Attr).Value.Text));

         end if;

      end if;

      --  Forbid specifying a test subdir along with a source directory path
      --  ending with "**".
      --  Upon running gnattest twice in a row, the subdirs created during the
      --  first run will be taken as source directories during the second,
      --  leading to an error.

      if (Root_Prj.Has_Attribute (+Subdir_Attr)
          or else Arg (Cmd, Subdirs) /= null)
        and then Root_Prj.Has_Attribute (Root_Attribute ("source_dirs"))
      then
         for Src_Dir_Path of
           Root_Prj.Attribute (Root_Attribute ("source_dirs")).Values
         loop
            declare
               Src_Dir_Str : constant String := String (Src_Dir_Path.Text);
            begin
               if Src_Dir_Str'Length >= 2
                 and then Src_Dir_Str
                            (Src_Dir_Str'Last - 1 .. Src_Dir_Str'Last)
                          = "**"
               then
                  Cmd_Error_No_Help
                    ("cannot specify test subdir along with a source directory"
                     & " path ending with ""**""");
               end if;
            end;
         end loop;
      end if;

      if Arg (Cmd, Stubs_Dir) /= null then
         Free (Test.Common.Stub_Dir_Name);
         Test.Common.Stub_Dir_Name := new String'(Arg (Cmd, Stubs_Dir).all);
         Stub_Dir_Set := True;

      elsif Root_Prj.Has_Attribute (+Stubs_Dir_Attr) then
         Free (Test.Common.Stub_Dir_Name);
         Test.Common.Stub_Dir_Name :=
           new String'(Attr_Value (Root_Prj, +Stubs_Dir_Attr));
         Stub_Dir_Set := True;

      end if;

      if Arg (Cmd, Harness_Dir) /= null then
         Free (Test.Common.Harness_Dir_Str);
         Test.Common.Harness_Dir_Str :=
           new String'(Arg (Cmd, Harness_Dir).all);
         Harness_Dir_Set := True;

      elsif Root_Prj.Has_Attribute (+Harness_Dir_Attr) then
         Free (Test.Common.Harness_Dir_Str);
         Test.Common.Harness_Dir_Str :=
           new String'(Attr_Value (Root_Prj, +Harness_Dir_Attr));
         Harness_Dir_Set := True;
      end if;

      --  Checks if the source root argument was passed and point to
      --  a directory that exists.
      declare
         Source_Root_Str : constant GNAT.OS_Lib.String_Access :=
           Arg (Cmd, Source_Root);
      begin
         if Source_Root_Str /= null then
            Test.Common.Source_Root_Str :=
              new String'(Ada.Directories.Full_Name (Source_Root_Str.all));

         end if;
      end;

      --  Checking if argument project has IDE package specified.
      Test.Common.IDE_Package_Present := Root_Prj.Has_Package (+"ide");

      --  Checking if argument project has Make package specified.
      Test.Common.Make_Package_Present := Root_Prj.Has_Package (+"make");

      --  We need to fill a local source table since gnattest actually needs
      --  info not only on current source but on any particular one or even
      --  all of them at once.

      declare
         --  For now repeating code from Utils.Drivers to get rid of ignored
         --  files, this should be optimized.
         use Test.Common.String_Set;

         Source : GPR2.Build.Source.Object;

      begin
         Test.Common.Recursive_Stubbing_ON := Arg (Cmd, Recursive_Stub);
         Test.Common.Stub_Mode_ON :=
           Arg (Cmd, Stub) or else Test.Common.Recursive_Stubbing_ON;

         for File of File_Names (Cmd) loop
            if not Contains (Ignored, Ada.Directories.Simple_Name (File.all))
            then
               Source := Src (File.all);
               if Source.Unit.Kind = S_Spec then
                  if Test.Common.Harness_Only then
                     Test.Harness.Source_Table.Add_Source_To_Process
                       (Source.Path_Name.String_Value);
                  else
                     Test.Skeleton.Source_Table.Add_Source_To_Process
                       (Source.Path_Name.String_Value);
                  end if;
               end if;
            end if;
         end loop;
      end;

      Test.Common.Substitution_Suite := Arg (Cmd, Validate_Type_Extensions);
      Test.Common.Inheritance_To_Suite := Arg (Cmd, Inheritance_Check);
      Test.Common.Test_Case_Only := Arg (Cmd, Test_Case_Only);
      Test.Common.Omit_Sloc := Arg (Cmd, Omit_Sloc);
      Test.Common.Show_Test_Duration := Arg (Cmd, Test_Duration);
      Test.Common.Relocatable_Harness := Arg (Cmd, Relocatable_Harness);
      Test.Common.Test_Filtering := Arg (Cmd, Test_Filtering);
      Test.Common.Include_Subp_Name := Arg (Cmd, Include_Subp_Name);

      Test.Common.Strict_Execution :=
        Arg (Cmd, Strict)
        or else (Ada.Environment_Variables.Exists ("GNATTEST_STRICT")
                 and then Ada.Environment_Variables.Value ("GNATTEST_STRICT")
                          = "TRUE");

      --  Command line support

      if not Arg (Cmd, Command_Line_Support) then
         Test.Common.No_Command_Line := True;
      else
         declare
            Target_Cmd_Line_Support : Boolean := False;
         begin

            --  We depend on GNAT.Command_Line to parse the command line
            --  switches. There are some runtimes that have a-comlin but not
            --  g-comlin, so explicitly check for both.

            if Has_Runtime_Source ("a-comlin.ads")
              and then Has_Runtime_Source ("g-comlin.ads")
            then
               Target_Cmd_Line_Support := True;
            end if;
            Test.Common.No_Command_Line := not Target_Cmd_Line_Support;

            if Target_Cmd_Line_Support then
               if Arg (Cmd, Test_Filtering_File_IO)
                 and then Has_Runtime_Source ("s-ficobl.ads")
               then
                  Test.Common.Text_IO_Present := True;
               end if;
               if Has_Runtime_Source ("g-os_lib.ads") then
                  Test.Common.GNAT_OS_Lib_Present := True;
               end if;
            end if;
         end;
      end if;

      --  Default behaviour of tests
      declare
         Skeleton_Default_Switch : constant String_Ref :=
           Arg (Cmd, Skeleton_Default);

         Present : constant Boolean :=
           Skeleton_Default_Switch /= null
           or else Root_Prj.Has_Attribute (+Skeletons_Default_Attr);

         Skeleton_Default_Val : constant String :=
           To_Lower
             ((if Skeleton_Default_Switch = null
               then
                 (if Present
                  then
                    String
                      (Root_Prj.Attribute (+Skeletons_Default_Attr).Value.Text)
                  else "")
               else Arg (Cmd, Skeleton_Default).all));
         --  If Skeleton_Default was specified through a switch, use this
         --  value. Otherwise, if it was specified through a project file
         --  attribute, use this value. If it was not specified, set it to the
         --  empty string.
      begin
         if Present then
            if Skeleton_Default_Val = "pass" then
               Test.Common.Skeletons_Fail := False;

            elsif Skeleton_Default_Val = "fail" then
               Test.Common.Skeletons_Fail := True;

            elsif Skeleton_Default_Val /= "" then
               Cmd_Error_No_Help
                 ((if Skeleton_Default_Switch /= null
                   then "--skeleton-default"
                   else "Gnattest.Skeletons_Default")
                  & " should be either fail or pass");
            end if;
         end if;
      end;

      --  Separate drivers
      declare
         Separate_Drivers_Switch : constant String_Ref :=
           Arg (Cmd, Separate_Drivers);
         Present                 : constant Boolean :=
           Separate_Drivers_Switch /= null;
         Separate_Drivers_Val    : constant String :=
           (if Present then To_Lower (Separate_Drivers_Switch.all) else "");
      begin
         if Present then
            Test.Common.Separate_Drivers := True;

            if Separate_Drivers_Val = "unit" or else Separate_Drivers_Val = ""
            then
               Test.Common.Driver_Per_Unit := True;

            elsif Separate_Drivers_Val = "test" then
               Test.Common.Driver_Per_Unit := False;

            else
               Cmd_Error_No_Help
                 ("--separate-drivers should be either unit or test"
                  & " >"
                  & Separate_Drivers_Switch.all
                  & "<");
            end if;
         end if;
      end;

      --  Reporter
      if Arg (Cmd, Reporter) /= null then
         if Test.Common.Stub_Mode_ON
           or else Arg (Cmd, Separate_Drivers) /= null
         then
            Test.Common.Report_Std
              ("warning: (gnattest) --reporter has no effect");
         end if;
         begin
            Test.Common.Reporter_Name :=
              Test.Common.Reporters'Value (Arg (Cmd, Reporter).all);
            --  Check if the reporter name can be converted to its enum value.
            --  If not this function will raise a Constraint_Error that will
            --  be caught and then display an error message.
            if Test.Common.Reporter_Name in Test.Common.Xml_Reporters then
               Test.Common.Include_Subp_Name := True;
            end if;
            if Test.Common.Reporter_Name = Test.Common.Xml_Deprecated then
               Test.Common.Report_Std
                 ("warning: (gnattest) --reporter=XML_Deprecated is "
                  & "deprecated, consider using --reporter=XML instead");
            end if;
         --  The subprogram names are needed to properly display all the
         --  information in the XML.
         exception
            when Constraint_Error =>
               Cmd_Error_No_Help
                 ("switch --reporter must pass a valid reporter");
         end;
      end if;

      if Test.Common.Stub_Mode_ON then

         if Arg (Cmd, Harness_Only) then
            Cmd_Error_No_Help
              ("options --harness-only and --stub are incompatible");
         end if;

         if Arg (Cmd, Additional_Tests) /= null then
            Cmd_Error_No_Help
              ("options --additional-tests and --stub are incompatible");
         end if;

         if Arg (Cmd, Dump_Test_Inputs) then
            Cmd_Error_No_Help
              ("options --dump-test-inputs and --stub are not yet compatible");
         end if;

         if not Tests_Dir_Set then
            Free (Test.Common.Test_Dir_Name);
            Test.Common.Test_Dir_Name :=
              new String'("gnattest_stub" & Directory_Separator & "tests");
         end if;

         if not Stub_Dir_Set then
            Free (Test.Common.Stub_Dir_Name);
            Test.Common.Stub_Dir_Name :=
              new String'("gnattest_stub" & Directory_Separator & "stubs");
         end if;

         if not Harness_Dir_Set then
            Free (Test.Common.Harness_Dir_Str);
            Test.Common.Harness_Dir_Str :=
              new String'("gnattest_stub" & Directory_Separator & "harness");
         end if;

         Test.Skeleton.Source_Table.Initialize_Project_Table;

         for F of Project_Tree.Root_Project.Visible_Sources loop
            if F.Language = Ada_Language
              and then not F.Owning_View.Is_Externally_Built
            then
               case F.Unit.Kind is
                  when S_Body =>
                     declare
                        View : GPR2.Project.View.Object := F.Owning_View;
                     begin
                        --  The name of the project here will be used to create
                        --  stub projects. Those extend original projects, so
                        --  if a source belongs to an extended project we need
                        --  the extending on here instead, so that we do not
                        --  end up with different extensions of same project.
                        View := Outermost_Extending (View);

                        Test.Skeleton.Source_Table.Add_Body_To_Process
                          (F.Path_Name.String_Value,
                           String (View.Name),
                           String (F.Unit.Name));
                     end;

                  when S_Spec =>
                     Test.Skeleton.Source_Table.Add_Body_Reference
                       (F.Path_Name.String_Value);

                  when others =>
                     null;
               end case;
            end if;
         end loop;
         Unchecked_Free (Files);

      end if;

      --  Processing harness dir specification

      if Is_Absolute_Path
           (GNATCOLL.VFS.Create (+Test.Common.Harness_Dir_Str.all))
      then
         Tmp := Test.Common.Harness_Dir_Str;
         Test.Common.Harness_Dir_Str :=
           new String'
             (Normalize_Pathname
                (Tmp.all, Resolve_Links => False, Case_Sensitive => False)
              & Directory_Separator);
         Free (Tmp);
      else
         Tmp := Test.Common.Harness_Dir_Str;
         Test.Common.Harness_Dir_Str :=
           new String'
             (Normalize_Pathname
                (Root_Prj.Object_Directory.String_Value
                 & Directory_Separator
                 & Tmp.all,
                 Resolve_Links  => False,
                 Case_Sensitive => False)
              & Directory_Separator);
         Free (Tmp);
      end if;

      for Dir of Recursive_Source_Dirs loop
         if Test.Common.Harness_Dir_Str.all
           = Normalize_Pathname
               (Dir.String_Value,
                Resolve_Links  => False,
                Case_Sensitive => False)
             & Directory_Separator
         then
            Cmd_Error_No_Help
              ("invalid harness directory, cannot mix up "
               & "infrastructure and sources");
         end if;
      end loop;

      if Is_Regular_File (Test.Common.Harness_Dir_Str.all) then
         Cmd_Error_No_Help ("cannot create harness directory");
      elsif not Is_Directory (Test.Common.Harness_Dir_Str.all) then

         declare
            Dir : File_Array_Access;
         begin
            Append
              (Dir, GNATCOLL.VFS.Create (+Test.Common.Harness_Dir_Str.all));
            Test.Common.Create_Dirs (Dir);
         exception
            when GNAT.Directory_Operations.Directory_Error =>
               Cmd_Error_No_Help ("cannot create harness directory");
         end;

      end if;

      case Output_Mode is
         when Direct_Mode =>
            Check_Direct;

         when Subdir_Mode =>
            Check_Subdir;

         when Root_Mode   =>
            Check_Separate_Root;
      end case;

      --  Instrumentation

      if Arg (Cmd, Dump_Test_Inputs) then
         for F of Project_Tree.Root_Project.Visible_Sources loop
            if F.Language = Ada_Language
              and then not F.Owning_View.Is_Externally_Built
            then
               if F.Unit.Kind = S_Body then
                  Test.Skeleton.Source_Table.Add_Body_For_Instrumentation
                    (F.Path_Name.String_Value);
               end if;
            end if;
         end loop;
         Unchecked_Free (Files);

         declare
            F : File_Array_Access;
         begin
            Append
              (F,
               GNATCOLL.VFS.Create
                 (+(Test.Common.Harness_Dir_Str.all
                    & Directory_Separator
                    & "test_obj"
                    & Directory_Separator
                    & Test.Common.Test_Prj_Prefix
                    & To_Lower (Project_Tree.Root_Project.Name)
                    & Test.Common.Instr_Suffix)));
            Test.Common.Create_Dirs (F);
            Unchecked_Free (F);
         end;

      end if;

      --  JSON Tests

      if Arg (Cmd, Minimize) then
         Test.Common.Minimize := True;
      end if;

      if Arg (Cmd, Serialized_Test_Dir) /= null then
         if not GNAT.OS_Lib.Is_Absolute_Path
                  (Arg (Cmd, Serialized_Test_Dir).all)
         then
            Test.Common.JSON_Test_Dir :=
              new String'
                (Ada.Directories.Current_Directory
                 & GNAT.OS_Lib.Directory_Separator
                 & Arg (Cmd, Serialized_Test_Dir).all);
         else
            Test.Common.JSON_Test_Dir :=
              new String'(Arg (Cmd, Serialized_Test_Dir).all);
         end if;
      else
         if Is_Absolute_Path (Test.Common.Test_Dir_Name.all) then
            Test.Common.JSON_Test_Dir :=
              new String'
                (Normalize_Pathname
                   (Test.Common.Test_Dir_Name.all
                    & Directory_Separator
                    & "JSON_Tests",
                    Resolve_Links  => False,
                    Case_Sensitive => False));
         else
            Test.Common.JSON_Test_Dir :=
              new String'
                (Normalize_Pathname
                   (Root_Prj.Object_Directory.String_Value
                    & Directory_Separator
                    & Test.Common.Test_Dir_Name.all
                    & Directory_Separator
                    & "JSON_Tests",
                    Resolve_Links  => False,
                    Case_Sensitive => False));
         end if;
      end if;

      --  Check that JSON_Test_Dir is a valid path. If not, checking whether
      --  the directory exists later on will raise an exception, so replace it
      --  with a valid but never existing directory name to avoid this.

      declare
         Dummy_Bool : Boolean;
      begin
         Dummy_Bool := Ada.Directories.Exists (Test.Common.JSON_Test_Dir.all);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Ada.Strings.Unbounded.Free (Test.Common.JSON_Test_Dir);
            Test.Common.JSON_Test_Dir :=
              new String'("gnattest_never_existing_dir_name");
      end;

      --  Test vectors

      --  Alway initialize the Libgen context; we don't know if there will be
      --  JSON tests to load or not.

      if Arg (Cmd, Detect_TGen_Proxies) /= null then
         begin
            Test.Common.TGen_Proxy_Search :=
              TGen.Libgen.Proxy_Autodetect_Policy'Value
                (Arg (Cmd, Detect_TGen_Proxies).all);
         exception
            when Constraint_Error =>
               Cmd_Error
                 ("Unexpected value for --detect-tgen-proxies. Should be one"
                  & " of ""none"", ""unit"" or ""all_refs"".");
         end;
      end if;

      Test.Common.TGen_Libgen_Ctx :=
        TGen.Libgen.Create
          (Output_Dir         =>
             Test.Common.Harness_Dir_Str.all & "tgen_support",
           User_Project_Path  => Arg (Cmd, Project_File).all,
           Root_Templates_Dir =>
             (Containing_Directory
                (Containing_Directory
                   (GNAT.OS_Lib.Locate_Exec_On_Path ("gnattest").all))
              & GNAT.OS_Lib.Directory_Separator
              & "share"
              & GNAT.OS_Lib.Directory_Separator
              & "tgen"
              & GNAT.OS_Lib.Directory_Separator
              & "templates"),
           Proxy_Detection    => Test.Common.TGen_Proxy_Search,
           Relevant_Units     => Get_All_Units'Access);

      Test.Common.Extract_Preprocessor_Config (Project_Tree);
      TGen.Libgen.Set_Preprocessing_Definitions
        (Test.Common.TGen_Libgen_Ctx, Test.Common.Preprocessor_Config);

      TGen.Libgen.Set_Minimum_Lang_Version
        (Test.Common.TGen_Libgen_Ctx,
         (case Test.Common.Lang_Version is
            when Ada_83 | Ada_95 | Ada_2005 | Ada_2012 => TGen.Libgen.Ada_12,
            when Ada_2022                              => TGen.Libgen.Ada_22));

      if Arg (Cmd, Gen_Test_Vectors) then
         Test.Common.Generate_Test_Vectors := True;
         Test.Common.Request_Lib_Support;

         Test.Common.Gen_Bin_Tests := Arg (Cmd, Gen_Test_Binary);

         if Arg (Cmd, Gen_Test_Subprograms) /= null then
            declare
               Subp_List : constant Test.Common.Unbounded_String_Vector :=
                 Process_Comma_Separated_String
                   (Arg (Cmd, Gen_Test_Subprograms).all);
            begin
               for E of Subp_List loop
                  declare
                     Line_Number : Natural;
                     File_Path   : constant String :=
                       Test.Common.Parse_File_And_Number
                         ("--gen-test-subprograms",
                          E.To_String,
                          Line_Number,
                          Extract_File_Name => True);
                  begin
                     Test.Common.Add_Allowed_Subprograms
                       (File_Path
                        & ":"
                        & Utils.String_Utilities.Image (Line_Number));
                  end;
               end loop;
            end;
         end if;

         if Arg (Cmd, Enum_Strat) then
            Test.Common.TGen_Strat_Kind := TGen.Libgen.Stateful;
         end if;

         Test.Common.Gen_Bin_Tests := Arg (Cmd, Gen_Test_Binary);
         Test.Common.Generate_Wrappers := Arg (Cmd, Gen_Wrappers);

         --  Activate the first pass

         Tool.Run_First_Pass := True;

         Test.Common.Unparse_Test_Vectors := Arg (Cmd, Unparse);
         declare
            Dir : File_Array_Access;
         begin
            Append (Dir, GNATCOLL.VFS.Create (+Test.Common.JSON_Test_Dir.all));
            Test.Common.Create_Dirs (Dir);
         exception
            when GNAT.Directory_Operations.Directory_Error =>
               Cmd_Error_No_Help ("cannot create JSON test directory");
         end;

         if Arg (Cmd, Gen_Test_Num) /= null then
            begin
               Test.Common.TGen_Num_Tests :=
                 Natural'Value (Arg (Cmd, Gen_Test_Num).all);
            exception
               when others =>
                  Cmd_Error_No_Help
                    ("--gen-test-num should be a natural integer");
            end;
         end if;
      else
         declare
            type All_Switches_Array is
              array (Positive range <>) of All_Switches;
            All_Gen_Test_Switches : constant All_Switches_Array :=
              (To_All (Gen_Test_Binary),
               To_All (Gen_Test_Num),
               To_All (Gen_Test_Subprograms),
               To_All (Enum_Strat));
         begin
            for Sw of All_Gen_Test_Switches loop
               if Present (Cmd, Sw) then
                  Cmd_Error
                    (Switch_Text (Cmd, Sw)
                     & " requires "
                     & Switch_Text (Cmd, To_All (Gen_Test_Vectors))
                     & " to also be present on the command line.");
               end if;
            end loop;
         end;
      end if;

      if Test.Common.Stub_Mode_ON then
         Check_Stub;
         declare
            Excludes : constant String_Ref_Array :=
              Arg (Cmd, Exclude_From_Stubbing);
         begin
            for Exclude of Excludes loop
               Process_Exclusion_List (Exclude.all);
            end loop;
         end;

         if Root_Prj.Has_Attribute (+Default_Stub_Exclusion_List_Attr) then
            Process_Exclusion_List
              (Attr_Value (Root_Prj, +Default_Stub_Exclusion_List_Attr),
               From_Project => True);
         end if;
         for Attr of Root_Prj.Attributes (+Stub_Exclusion_List_Attr) loop
            Process_Exclusion_List
              (String (Attr.Index.Text) & ":" & String (Attr.Value.Text),
               From_Project => True);
         end loop;
      end if;

      --  Process additional tests
      if Arg (Cmd, Additional_Tests) /= null then
         Test.Common.Additional_Tests_Prj :=
           new String'
             (Normalize_Pathname
                (Arg (Cmd, Additional_Tests).all,
                 Resolve_Links  => False,
                 Case_Sensitive => False));
      elsif Root_Prj.Has_Attribute (+Additional_Tests_Attr) then
         Test.Common.Additional_Tests_Prj :=
           new String'
             (Normalize_Pathname
                (Attr_Value (Root_Prj, +Additional_Tests_Attr),
                 Resolve_Links  => False,
                 Case_Sensitive => False));
      end if;

      if Test.Common.Additional_Tests_Prj /= null
        and then not Is_Regular_File (Test.Common.Additional_Tests_Prj.all)
      then
         Cmd_Error_No_Help
           ("cannot find " & Test.Common.Additional_Tests_Prj.all);
      end if;

      if Root_Prj.Has_Attribute (Attr_Id ("compiler", "default_switches")) then
         declare
            Switches : constant GPR2.Project.Attribute.Object :=
              Project_Tree.Root_Project.Attribute
                (Name  => Attr_Id ("compiler", "default_switches"),
                 Index => GPR2.Project.Attribute_Index.Create (Ada_Language));
         begin
            for Switch of Switches.Values loop
               if Switch.Text = "-gnatE" then
                  Test.Common.Inherited_Switches.Append (String (Switch.Text));
               end if;
            end loop;
         end;
      end if;

      Ignored.Clear;

   end Init;

   --------------------
   -- Generate_Tests --
   --------------------

   procedure Generate_Tests (Cmd : Command_Line) is
      Src_Prj : constant String :=
        Project_Tree.Root_Project.Path_Name.String_Value;
   begin
      if Test.Common.Stub_Mode_ON then
         Test.Harness.Generate_Stub_Test_Driver_Projects (Src_Prj);
      elsif Arg (Cmd, Separate_Drivers) /= null then
         Test.Skeleton.Generate_Project_File (Src_Prj);
         Test.Harness.Generate_Test_Driver_Projects (Src_Prj);
      else
         if not Arg (Cmd, Harness_Only) then
            if Test.Common.Additional_Tests_Prj /= null then
               Process_Additional_Tests (Cmd);
            end if;
            Test.Skeleton.Report_Unused_Generic_Tests;
            Test.Skeleton.Generate_Project_File (Src_Prj);
            if Test.Common.Verbose then
               Test.Skeleton.Report_Tests_Total;
            end if;
         end if;
         Test.Harness.Test_Runner_Generator (Src_Prj);
         Test.Harness.Project_Creator (Src_Prj);
      end if;
      Test.Harness.Generate_Makefile (Src_Prj);
      Test.Harness.Generate_Config;
      Test.Common.Generate_Common_File;

      --  Only generate the mapping file if we are not minimizing.
      --  Otherwise, the gnattest subprocess will take care of generating it
      --  once all the redundant tests are removed.

      if Test.Common.Minimize then
         if Test.Common.Harness_Has_Gen_Tests then
            Test.Suite_Min.Minimize_Suite (Cmd);
         else
            Test.Common.Report_Err
              ("No generated tests found in the harness,"
               & " nothing to do in the minimization phase.");
            Test.Mapping.Generate_Mapping_File;
         end if;
      else
         Test.Mapping.Generate_Mapping_File;
      end if;
   end Generate_Tests;

   ---------------
   -- Run_Tests --
   ---------------

   procedure Run_Tests is
   begin
      Test.Aggregator.Process_Drivers_List;
   end Run_Tests;

   ----------------------------
   -- Second_Per_File_Action --
   ----------------------------

   procedure Dump_Subprogram_Hash (File_Name : String; Unit : Analysis_Unit) is
      use Libadalang.Common;
      use Ada.Strings.Unbounded;
   begin
      if Ada.Directories.Simple_Name (Test.Common.Subp_File_Name.all)
        = Ada.Directories.Simple_Name (File_Name)
      then
         declare
            Found_Hash : Boolean := False;

            function Visit (Node : Ada_Node'Class) return Visit_Status;

            function Visit (Node : Ada_Node'Class) return Visit_Status is
            begin
               if Found_Hash then
                  return Stop;
               end if;
               if Kind (Node) in Ada_Basic_Subp_Decl
                 and then Natural (Node.Sloc_Range.Start_Line)
                          = Test.Common.Subp_Line_Nbr
               then
                  Ada.Text_IO.Put_Line
                    (TGen.LAL_Utils.Short_Hash (Node.As_Basic_Decl));
                  Found_Hash := True;
                  return Stop;
               end if;
               return Into;
            end Visit;

         begin
            Traverse (Root (Unit), Visit'Access);
            if not Found_Hash then
               Ada.Text_IO.Put
                 ("Subprogram in "
                  & Test.Common.Subp_File_Name.all
                  & " at line "
                  & Natural'Image (Test.Common.Subp_Line_Nbr)
                  & " could not be found.");
               return;
            end if;
         end;

      end if;
      return;
   end Dump_Subprogram_Hash;

   -------------------
   -- Get_All_Units --
   -------------------

   function Get_All_Units (Decl : Base_Type_Decl) return Analysis_Unit_Array is
      All_Files : constant String_Ref_Array := File_Names (Global_Cmd);
   begin
      return
        Analysis_Unit_Array'
          (for File of All_Files =>
             Decl.Unit.Context.Get_From_File (File.all));
   end Get_All_Units;

   ---------------
   -- Tool_Help --
   ---------------

   procedure Tool_Help is
   begin
      pragma Style_Checks ("M200"); -- Allow long lines
      Put ("usage: gnattest -Pprj [opts] {filename}\n");
      Put ("        - generates the unit testing framework\n");
      Put ("\n");
      Put (" or   gnattest test_drivers.list [opts]\n");
      Put ("        - executes tests and aggregates the results\n");
      Put ("\n");
      Put (" --version        - Display version and exit\n");
      Put (" --help           - Display usage and exit\n");
      Put (" -v, --verbose    - Verbose mode\n");
      Put (" -q, --quiet      - Quiet mode\n");
      Put ("\n");

      Put ("Framework generation mode options:\n");
      Put ("\n");
      Put
        (" -Pproject        - Use project file project. Only one such switch can be used\n");
      Put
        (" -U               - Process all sources of the argument project\n");
      Put
        (" -U main          - Process the closure of units rooted at unit main\n");
      Put (" --no-subprojects - Process sources of root project only\n");
      Put
        (" -Xname=value     - Specify an external reference for argument project file\n");
      Put
        (" -eL              - Follow all symbolic links when processing project files\n");
      Put (" --target=target  - Specify a target\n");
      Put (" --RTS=runtime    - Specify runtime for Ada\n");
      Put
        (" --files=file     - Name of a text file containing a list of Ada\n");
      Put ("                    source files to process\n");
      Put
        (" --ignore=file    - Name of a text file containing a list of sources\n");
      Put ("                    to be excluded from processing\n");

      Put
        (" --strict                - Return error exit code if there are parsing errors\n");
      Put
        (" --additional-tests=prj  - Treat sources from project prj as additional\n");
      Put
        ("                           manual tests to add to the test suite\n");
      Put
        (" --harness-only          - Treat argument sources as tests to add to the suite\n");
      Put
        (" --stub                  - Generate testing framework that uses stubs\n");
      Put
        (" --recursive-stub        - Recursively stub dependencies of stubbed units\n");
      Put ("\n");

      Put
        (" --exclude-from-stubbing=file       - List of sources whose bodies should not\n");
      Put ("                                      be stubbed\n");
      Put
        (" --exclude-from-stubbing=spec:file  - List of sources whose bodies should not\n");
      Put
        ("                                        be stubbed when testing unit whose\n");
      Put
        ("                                        specification is located in file spec\n");
      Put ("\n");

      Put (" --harness-dir=dirname  - Output dir for test harness\n");
      Put (" --tests-dir=dirname    - Test files are put in dirname\n");
      Put
        (" --source-root=dirname  - The root from which the test file path will be starting\n");
      Put
        (" --subdirs=dirname      - Test files are put in subdirs dirname of source dirs\n");
      Put
        (" --tests-root=dirname   - Test files are put in the same directory hierarchy\n");
      Put ("                          as sources but rooted at dirname\n");
      Put
        (" --stubs-dir=dirname    - Stub files are put in subdirs of dirname\n");
      Put ("\n");

      Put
        (" --validate-type-extensions                           - Run all tests from all parents to check LSP\n");
      Put
        (" --inheritance-check                                  - Run inherited tests for descendants\n");
      Put
        (" --no-inheritance-check                               - Do not run inherited tests for descendants\n");
      Put
        (" --test-case-only                                     - Create tests only when Test_Case is specified\n");
      Put
        (" --skeleton-default=(pass|fail)                       - Default behavior of unimplemented tests\n");
      Put
        (" --passed-tests=(show|hide)                           - Default output of passed tests\n");
      Put
        (" --exit-status=(on|off)                               - Default usage of the exit status\n");
      Put
        (" --omit-sloc                                          - Don't record subprogram sloc in test package\n");
      Put
        (" --no-command-line                                    - Don't add command line support to test driver\n");
      Put
        (" --include-subp-name                                  - Include the tested subprogram's name in the output\n");
      Put
        (" --test-duration                                      - Show timing for each test\n");
      Put
        (" --test-filtering                                     - Add test filtering option to generated driver\n");
      Put
        (" --no-test-filtering                                  - Suppress test filtering in generated driver\n");
      Put
        (" --gen-test-vectors                                   - Generate test inputs for supported subprograms (experimental)\n");
      Put
        (" --gen-test-binary                                    - Generate test inputs in binary format (experimental, requires --gen-test-vectors)\n");
      Put
        (" --gen-test-num=n                                     - Specify the number of test inputs to be generated (experimental, defaults to 5)\n");
      Put
        (" --gen-test-subprograms=file:line                     - Specify a comma separated list of subprograms declared at file:line to generate test cases for\n");
      Put
        (" --detect-tgen-proxies=(none|unit|all_refs)           - Specify where gnattest should search for proxy subprograms for unsupported types. Default to ""unit"" if unspecified.");
      Put
        (" --dump-subp-hash=file:line                           - Print the hash of the subprogram at file:line in the standard output and bypass all other swicthes.\n");
      Put
        (" --serialized-test-dir=dir                            - Specify in which directory test inputs should be generated (experimental)\n");
      Put
        (" --dump-test-inputs                                   - Dump input values of the subprogram under test as blobs during harness execution (experimental)\n");
      Put
        (" --minimize                                           - Minimize the generated testsuite based on structural coverage analysis (experimental)\n");
      Put
        (" --minimization-filter=file:line                      - Only minimize tests for the subprogram declared at file:line (file must be a simple name)\n");
      Put
        (" --cov-level=level                                    - Use level as the coverage level to guide test minimization (see gnatcov help for available choices)\n");
      Put
        (" --reporter=(gnattest|xml|junit|text|xml_deprecated)  - Specify which reporter to use when outputing test results (defaults to 'gnattest')\n");
      Put ("\n");

      Put ("Tests execution mode options:\n");
      Put ("\n");
      Put (" --passed-tests=(show|hide)  - Default output of passed tests\n");
      Put
        (" --queues=n, -jn             - Run n tests in parallel (default n=1)\n");
      Put
        (" --copy-environment=dir      - Copy contents of dir to temp dirs where test\n");
      Put ("                               drivers are spawned\n");
      Put
        (" --subdirs=dirname           - Look for test drivers in subdirs\n");
      pragma Style_Checks ("M79");
   end Tool_Help;

   -----------------------------
   -- Unit_Requested_Callback --
   -----------------------------

   procedure Unit_Requested_Callback
     (Self               : in out Additional_Tests_Event_Handler;
      Context            : Analysis_Context'Class;
      Name               : Langkit_Support.Text.Text_Type;
      From               : Analysis_Unit'Class;
      Found              : Boolean;
      Is_Not_Found_Error : Boolean)
   is
      pragma Unreferenced (Context);
      use Test.Common;
      use Langkit_Support.Text;
   begin
      --  We only care about missing units which can cause a LAL crash
      if Found or else not Is_Not_Found_Error then
         return;
      end if;

      declare
         Lower_Name              : constant String := Image (To_Lower (Name));
         Missing_Unit_From_Aunit : constant Boolean :=
           Ada.Strings.Fixed.Index (Lower_Name, "aunit", From => 1) = 1;
      begin
         Report_Err
           ("Could not find unit "
            & Ada.Directories.Simple_Name (Image (Name))
            & " while processing "
            & Ada.Directories.Simple_Name (From.Get_Filename)
            & " to find additional tests.");
         if Missing_Unit_From_Aunit then
            Cmd_Error_No_Tool_Name
              ("Ensure "
               & Ada.Directories.Simple_Name (Additional_Tests_Prj.all)
               & " passed to --additional-tests depends on ""aunit.gpr"" and"
               & " can be compiled.");
         else
            Cmd_Error_No_Tool_Name
              ("Ensure "
               & Ada.Directories.Simple_Name (Additional_Tests_Prj.all)
               & " passed to --additional-tests depends on the tested project"
               & " and can be compiled.");
         end if;
      end;
   end Unit_Requested_Callback;

   ------------------------------
   -- Process_Additional_Tests --
   ------------------------------

   procedure Process_Additional_Tests (Cmd : Command_Line) is
      Context  : Analysis_Context;
      Provider : Unit_Provider_Reference;
      Unit     : Analysis_Unit;

      Current_Source : String_Access;

      Additional_Tests_Project : constant GPR2.Project.Tree.Object :=
        Load_Project_File (Cmd, Test.Common.Additional_Tests_Prj.all);
      use Libadalang.Project_Provider;
   begin
      for Src of Additional_Tests_Project.Root_Project.Sources loop
         if Src.Unit.Kind = S_Spec then
            Test.Harness.Source_Table.Add_Source_To_Process
              (Src.Path_Name.String_Value);
         end if;
      end loop;

      Provider :=
        Create_Project_Unit_Provider (Tree => Additional_Tests_Project);
      Context :=
        Create_Context
          (Charset       => Wide_Character_Encoding (Cmd),
           Unit_Provider => Provider,
           Event_Handler => Create_Event_Handler_Reference (ATEH_Instance));

      Current_Source :=
        new String'(Test.Harness.Source_Table.Next_Non_Processed_Source);
      while Current_Source.all /= "" loop
         Unit :=
           Get_From_File
             (Context,
              Test.Harness.Source_Table.Get_Source_Full_Name
                (Current_Source.all));

         if Unit.Has_Diagnostics then

            Test.Common.Report_Err
              ("gnattest: Error loading "
               & Current_Source.all
               & " to search"
               & " for additional tests. Make sure the project passed to"
               & " --additional-tests depends on ""aunit.gpr"" and that it can"
               & " be compiled. The errors are:");
            for Diag of Unit.Diagnostics loop
               Test.Common.Report_Err (Unit.Format_GNU_Diagnostic (Diag));
            end loop;
            Free (Current_Source);
            Cmd_Error_No_Tool_Name ("");  -- aka abort

         end if;

         Test.Harness.Process_Source (Unit);

         Free (Current_Source);
         Current_Source :=
           new String'(Test.Harness.Source_Table.Next_Non_Processed_Source);
      end loop;
      Free (Current_Source);
   exception
      when
        Exc :
          Langkit_Support.Errors.Property_Error
          | Langkit_Support.Errors.Precondition_Failure
      =>
         declare
            Src_Name : constant String := Current_Source.all;
         begin
            Free (Current_Source);
            Test.Common.Report_Err
              ("Error processing additional tests in "
               & Src_Name
               & ". Ensure the project passed to --additional-tests depends on"
               & " ""aunit.gpr"" and that it can be compiled.");
            Test.Common.Report_Ex (Exc);
            Cmd_Error_No_Help ("");  --  aka abort
         end;
   end Process_Additional_Tests;

   ----------------------------
   -- Process_Exclusion_List --
   ----------------------------

   procedure Process_Exclusion_List
     (Value : String; From_Project : Boolean := False)
   is
      use Ada.Text_IO;
      use Ada.Strings.Fixed;
      First     : constant Natural := Value'First;
      Colon_Idx : constant Natural := Index (Value, ":");

      F : File_Type;

      Exclude_For_One_UUT : constant Boolean :=
        Value'Length > 3 and then Colon_Idx > First + 1;
      --  For the new interface (=spec:file instead of :spec=file), the equal
      --  sign is eaten by the argument processing.

      S : String_Access;

      function Is_Comment (S : String) return Boolean
      is (S'Length >= 2 and then S (S'First .. S'First + 1) = "--");

      use Test.Common;
   begin
      if Exclude_For_One_UUT then
         declare
            Unit   : constant String := Value (First .. Colon_Idx - 1);
            F_Path : constant String :=
              Normalize_Pathname
                (Name           => Value (Colon_Idx + 1 .. Value'Last),
                 Resolve_Links  => False,
                 Case_Sensitive => False);
         begin
            if not Is_Regular_File (F_Path) then
               Cmd_Error_No_Help ("cannot find " & F_Path);
            end if;

            if From_Project
              and then Test.Common.Stub_Exclusion_Lists.Contains (Unit)
            then
               return;
            end if;

            Open (F, In_File, F_Path);
            while not End_Of_File (F) loop
               S := new String'(Get_Line (F));
               if not Is_Comment (S.all) then
                  Test.Common.Store_Excluded_Stub (Unit, S.all);
               end if;
               Free (S);
            end loop;
            Close (F);
         end;
         return;
      end if;

      if From_Project
        and then not Test.Common.Default_Stub_Exclusion_List.Is_Empty
      then
         return;
      end if;

      declare
         F_Path : constant String :=
           Normalize_Pathname
             (Name => Value, Resolve_Links => False, Case_Sensitive => False);
      begin
         if not Is_Regular_File (F_Path) then
            Cmd_Error_No_Help ("cannot find " & F_Path);
         end if;
         Open (F, In_File, F_Path);
         while not End_Of_File (F) loop
            S := new String'(Get_Line (F));
            if not Is_Comment (S.all) then
               Test.Common.Store_Default_Excluded_Stub (S.all);
            end if;
            Free (S);
         end loop;
         Close (F);
      end;

   end Process_Exclusion_List;

   ---------------------------
   -- Non_Null_Intersection --
   ---------------------------

   function Non_Null_Intersection
     (Left : File_Array_Access; Right : File_Array) return Boolean is
   begin
      for J in Left'Range loop
         declare
            Left_Str : constant String :=
              Normalize_Pathname
                (Name           => Left.all (J).Display_Full_Name,
                 Resolve_Links  => False,
                 Case_Sensitive => False);
         begin
            for K in Right'Range loop

               if Left_Str
                 = Normalize_Pathname
                     (Name           => Right (K).Display_Full_Name,
                      Resolve_Links  => False,
                      Case_Sensitive => False)
               then
                  Test.Common.Report_Std
                    ("gnattest: "
                     & Left_Str
                     & " is used for more than one purpose");
                  return True;
               end if;
            end loop;
         end;
      end loop;

      return False;
   end Non_Null_Intersection;

   ------------------
   -- Check_Direct --
   ------------------

   procedure Check_Direct is
      use Test.Common;

      TD_Name        : constant Virtual_File :=
        GNATCOLL.VFS.Create (+Test_Dir_Name.all);
      Future_Dirs    : File_Array_Access := new File_Array'(Empty_File_Array);
      Harness_Dir_Ar : constant File_Array (1 .. 1) :=
        [1 => Create (+(Harness_Dir_Str.all))];

      All_Source_Locations : constant File_Array :=
        To_File_Array (Recursive_Source_Dirs);
   begin
      if TD_Name.Is_Absolute_Path then
         Append (Future_Dirs, GNATCOLL.VFS.Create (+Test_Dir_Name.all));
      else
         for View of Project_Tree.Ordered_Views loop
            if View.Kind in With_Object_Dir_Kind then
               Append
                 (Future_Dirs,
                  GNATCOLL.VFS.Create
                    (GNATCOLL.VFS."+"
                       (View.Object_Directory.String_Value
                        & Directory_Separator
                        & Test_Dir_Name.all)));
            end if;
         end loop;
      end if;

      if Non_Null_Intersection (Future_Dirs, All_Source_Locations) then
         Cmd_Error_No_Help
           ("invalid output directory, cannot mix up " & "tests and sources");
      end if;

      if Non_Null_Intersection (Future_Dirs, Harness_Dir_Ar) then
         Cmd_Error_No_Help
           ("invalid output directory, cannot mix up "
            & "tests and infrastructure");
      end if;

      Unchecked_Free (Future_Dirs);

      Test.Skeleton.Source_Table.Set_Direct_Output;
   end Check_Direct;

   ------------------
   -- Check_Subdir --
   ------------------

   procedure Check_Subdir is
      use Test.Common;

      Future_Dirs : File_Array_Access := new File_Array'(Empty_File_Array);
      --  List of dirs to be generated. The list is checked for intersections
      --  with source dirs before any new directories are created.

      Harness_Dir_Ar : constant File_Array (1 .. 1) :=
        [1 => Create (+(Harness_Dir_Str.all))];

      All_Source_Locations : constant File_Array :=
        To_File_Array (Recursive_Source_Dirs);

   begin
      for Loc of All_Source_Locations loop
         Append (Future_Dirs, Loc / (+Test_Subdir_Name.all));
      end loop;

      if Non_Null_Intersection (Future_Dirs, All_Source_Locations) then
         Cmd_Error_No_Help
           ("invalid output directory, cannot mix up " & "tests and sources");
      end if;

      if Non_Null_Intersection (Future_Dirs, Harness_Dir_Ar) then
         Cmd_Error_No_Help
           ("invalid output directory, cannot mix up "
            & "tests and infrastructure");
      end if;

      Test.Skeleton.Source_Table.Set_Subdir_Output;
   end Check_Subdir;

   -------------------------
   -- Check_Separate_Root --
   -------------------------

   procedure Check_Separate_Root is
      use Test.Common;

      Root_Dir_VF : constant Virtual_File :=
        GNATCOLL.VFS.Create (+Separate_Root_Dir.all);
      --  Virtual file corresponding to the value passed to --tests-root

      Tmp, Buff : String_Access;

      Maximin_Root : String_Access;
      --  Longest common prefix for all source files. If Root_Dir_VF is an
      --  absolute path this is computed taking into account all source files,
      --  otherwise this is computed per-project.
      --
      --  For instance, if we have two files in the project tree, one at
      --  /foo/bar/baz/qux.ads and the other one at /foo/bar/baz-top/blop.ads,
      --  this should be computed to /foo/bar/

      Root_Length : Integer;
      --  Shortcut for Maximin_Root.all'Length.

      Future_Dirs : File_Array_Access := new File_Array'(Empty_File_Array);
      --  List of dirs to be generated. The list is checked for intersections
      --  with source dirs before any new directories are created.

      Harness_Dir_Ar : constant File_Array (1 .. 1) :=
        [1 => Create (+(Harness_Dir_Str.all))];

      All_Source_Locations : constant GNATCOLL.VFS.File_Array :=
        To_File_Array (Recursive_Source_Dirs);

      Files : GPR2.Build.Source.Sets.Object;

      Local_Separate_Root_Dir : String_Access;

      function Common_Root (Left : String; Right : String) return String;
      --  Returns the coincident beginning of both paths or an empty string.

      -------------------
      --  Common_Root  --
      -------------------

      function Common_Root (Left : String; Right : String) return String is
         Idxl : Integer := Left'First;
         Idxr : Integer := Right'First;

         Last_Dir_Sep_Index : Integer := Idxl - 1;
         --  We need to check for the following:
         --  ...somepath/dir/
         --  ...somepath/directory/

      begin
         if Left = "" or Right = "" then
            return "";
         end if;

         loop
            if Left (Idxl) = Directory_Separator
              and then Right (Idxr) = Directory_Separator
            then
               Last_Dir_Sep_Index := Idxl;
            end if;

            if Left (Idxl) /= Right (Idxr) then
               return Left (Left'First .. Last_Dir_Sep_Index);
            end if;

            exit when Idxl = Left'Last or Idxr = Right'Last;

            Idxl := Idxl + 1;
            Idxr := Idxr + 1;
         end loop;

         return Left (Left'First .. Idxl);
      end Common_Root;

   begin
      if Root_Dir_VF.Is_Absolute_Path then

         --  Absolute path passed to `--tests-root`.
         --
         --  Compute the common path for all sources <root>. All sources are
         --  thus of the form <root>/<unique_part>/simple_name.
         --
         --  The test for each source will thus be placed in
         --  Root_Dir_VF/<unique_part>
         --
         --  For instance, if we have a project with a source
         --  /foo/bar/baz/src/qux.ads and another one with a source
         --  /foo/bar/mlem/src/plop.ads,
         --  then the <common_part> would be /foo/bar/, and the <unique_part>
         --  would be baz/src for the first source, and mlem/src for
         --  the second.

         Test.Skeleton.Source_Table.Reset_Location_Iterator;
         Tmp := new String'(Test.Skeleton.Source_Table.Next_Source_Location);
         Maximin_Root := new String'(Tmp.all);

         loop
            Tmp :=
              new String'(Test.Skeleton.Source_Table.Next_Source_Location);
            exit when Tmp.all = "";

            Buff := new String'(Common_Root (Tmp.all, Maximin_Root.all));

            if Buff.all = "" then
               Cmd_Error_No_Help
                 ("gnattest: sources have different root dirs, "
                  & "cannot apply separate root output");
            end if;

            Free (Maximin_Root);
            Maximin_Root := new String'(Buff.all);
            Free (Buff);
            Free (Tmp);
         end loop;

         Root_Length := Maximin_Root.all'Length;

         Separate_Root_Dir :=
           new String'
             (Normalize_Pathname
                (Name           => Separate_Root_Dir.all,
                 Resolve_Links  => False,
                 Case_Sensitive => False));

         Test.Skeleton.Source_Table.Reset_Location_Iterator;

         loop
            Tmp :=
              new String'(Test.Skeleton.Source_Table.Next_Source_Location);
            exit when Tmp.all = "";

            Append
              (Future_Dirs,
               GNATCOLL.VFS.Create
                 (+(Separate_Root_Dir.all
                    & Directory_Separator
                    & Tmp.all (Root_Length + 1 .. Tmp.all'Last))));

            Free (Tmp);
         end loop;

         if Non_Null_Intersection (Future_Dirs, All_Source_Locations) then
            Cmd_Error_No_Help
              ("invalid output directory, cannot mix up "
               & "tests and sources");
         end if;

         if Non_Null_Intersection (Future_Dirs, Harness_Dir_Ar) then
            Cmd_Error_No_Help
              ("invalid output directory, cannot mix up "
               & "tests and infrastructure");
         end if;

         Test.Skeleton.Source_Table.Set_Separate_Root (Maximin_Root.all);
      else

         --  Same idea as the absolute path, except we only need to compute the
         --  common part among the sources of a single project. The Root_Dir_VF
         --  path is interpreted relative to the object directory of each
         --  project.

         for View of Project_Tree.Ordered_Views loop

            --  Skip externally built and abstract projects

            if View.Is_Externally_Built or else View.Kind = K_Abstract then
               goto Next;
            end if;

            --  As the test root is local to each project, reset it as well as
            --  the length of each project to ensure we don't have any funny
            --  business.

            if Maximin_Root /= null then
               Free (Maximin_Root);
            end if;
            Root_Length := 0;

            --  First check wether some source directory contains all the
            --  others. If so, use that as starting root candidate to ensure
            --  we fully replicate the source directory nesting.

            declare
               Common_Root_Dir : String_Access;
               Dirs            : constant GPR2.Path_Name.Set.Object :=
                 View.Source_Directories;
            begin
               Common_Root_Dir := new String'(Dirs.First_Element.String_Value);

               for Dir of Dirs loop
                  Tmp := new String'(Dir.String_Value);
                  Buff :=
                    new String'(Common_Root (Tmp.all, Common_Root_Dir.all));

                  if Buff.all = "" then
                     Cmd_Error_No_Help
                       ("gnattest: sources have different root dirs, "
                        & "cannot apply separate root output");
                  end if;

                  Free (Common_Root_Dir);
                  Common_Root_Dir := new String'(Buff.all);
                  Free (Buff);
                  Free (Tmp);
               end loop;

               for Dir of Dirs loop
                  if Dir.String_Value = Common_Root_Dir.all then
                     Maximin_Root := Common_Root_Dir;
                     exit;
                  end if;
               end loop;
            end;

            --  Refine the root, in case there was no nesting between all the
            --  source dirs, or a source file lives outside of one of the
            --  source dirs.

            Files := View.Sources;
            for F of Files loop
               if Maximin_Root = null then
                  Maximin_Root := new String'(F.Path_Name.String_Value);
               end if;
               Tmp := new String'(F.Path_Name.String_Value);
               Buff := new String'(Common_Root (Tmp.all, Maximin_Root.all));

               if Buff.all = "" then
                  Cmd_Error_No_Help
                    ("gnattest: sources have different root dirs, "
                     & "cannot apply separate root output");
               end if;

               Free (Maximin_Root);
               Maximin_Root := new String'(Buff.all);
               Free (Buff);
               Free (Tmp);
            end loop;

            Root_Length := Maximin_Root.all'Length;

            Local_Separate_Root_Dir :=
              new String'
                (Normalize_Pathname
                   (Name           =>
                      View.Object_Directory.String_Value
                      & Directory_Separator
                      & Separate_Root_Dir.all,
                    Case_Sensitive => False));

            for F of Files loop
               if F.Unit.Kind = S_Spec
                 and then Test.Skeleton.Source_Table.Source_Present
                            (F.Path_Name.String_Value)
               then
                  Tmp :=
                    new String'(F.Path_Name.Virtual_File.Display_Dir_Name);

                  Append
                    (Future_Dirs,
                     GNATCOLL.VFS.Create
                       (+(Local_Separate_Root_Dir.all
                          & Directory_Separator
                          & Tmp.all (Root_Length + 1 .. Tmp.all'Last))));

                  Test.Skeleton.Source_Table.Set_Output_Dir
                    (F.Path_Name.String_Value,
                     Local_Separate_Root_Dir.all
                     & Directory_Separator
                     & Tmp.all (Root_Length + 1 .. Tmp.all'Last));
               end if;
            end loop;

            <<Next>>
         end loop;

         if Non_Null_Intersection (Future_Dirs, All_Source_Locations) then
            Cmd_Error_No_Help
              ("invalid output directory, cannot mix up "
               & "tests and sources");
         end if;

         if Non_Null_Intersection (Future_Dirs, Harness_Dir_Ar) then
            Cmd_Error_No_Help
              ("invalid output directory, cannot mix up "
               & "tests and infrastructure");
         end if;

      end if;

   end Check_Separate_Root;

   ----------------
   -- Check_Stub --
   ----------------

   procedure Check_Stub is
      use Test.Common;

      Tmp         : String_Access;
      SD_Name     : constant Virtual_File :=
        GNATCOLL.VFS.Create (+Stub_Dir_Name.all);
      Future_Dirs : File_Array_Access := new File_Array'(Empty_File_Array);

      All_Source_Locations : constant File_Array :=
        To_File_Array (Recursive_Source_Dirs);
   begin
      --  Look for collisions with source dirs

      if SD_Name.Is_Absolute_Path then
         Append (Future_Dirs, GNATCOLL.VFS.Create (+Test_Dir_Name.all));
      else
         for View of Project_Tree.Ordered_Views loop
            if View.Kind in With_Object_Dir_Kind then
               Append
                 (Future_Dirs,
                  GNATCOLL.VFS.Create
                    (+Normalize_Pathname
                        (View.Object_Directory.String_Value
                         & Directory_Separator
                         & Stub_Dir_Name.all,
                         Resolve_Links  => False,
                         Case_Sensitive => False)));
            end if;
         end loop;
      end if;

      if Non_Null_Intersection (Future_Dirs, All_Source_Locations) then
         Cmd_Error_No_Help
           ("gnattest: invalid stub directory, cannot mix up "
            & "stubs and source files");
      end if;

      Test.Skeleton.Source_Table.Set_Direct_Stub_Output;

      --  Once stub dirs are set we can compare them with test dirs per source.
      Test.Skeleton.Source_Table.Reset_Source_Iterator;
      Tmp := new String'(Test.Skeleton.Source_Table.Next_Source_Name);
      while Tmp.all /= "" loop
         if Test.Skeleton.Source_Table.Get_Source_Output_Dir (Tmp.all)
           = Test.Skeleton.Source_Table.Get_Source_Stub_Dir (Tmp.all)
         then
            Test.Common.Report_Std
              ("gnattest: "
               & Test.Skeleton.Source_Table.Get_Source_Stub_Dir (Tmp.all)
               & " is used for more than one purpose");
            Cmd_Error_No_Help
              ("gnattest: invalid stub directory, cannot mix up "
               & "stubs and tests");
         end if;
         Free (Tmp);
         Tmp := new String'(Test.Skeleton.Source_Table.Next_Source_Name);
      end loop;

      Test.Skeleton.Source_Table.Reset_Source_Iterator;
   end Check_Stub;
end Test.Actions;
