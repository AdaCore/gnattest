------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                        Copyright (C) 2023, AdaCore                       --
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
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with GNATCOLL.JSON; use GNATCOLL.JSON;

with Test.Command_Lines; use Test.Command_Lines;
use Test.Command_Lines.Test_String_Switches;
with Test.Common;        use Test.Common;
with Test.Subprocess;    use Test.Subprocess;

with Utils.Environment; use Utils.Environment;
with Utils.Projects;
with Utils_Debug;       use Utils_Debug;

with GNATCOLL.OS.Process;
with GNATCOLL.Traces; use GNATCOLL.Traces;

with Libadalang.Common; use Libadalang.Common;

with Langkit_Support.Text;

with TGen.Libgen; use TGen.Libgen;
with TGen.Strings;

package body Test.Generation is

   Me : constant Trace_Handle := Create ("Generation", Default => Off);

   Global_Aspect_Name : constant Langkit_Support.Text.Unbounded_Text_Type :=
     Langkit_Support.Text.To_Unbounded_Text ("Global");

   function Traverse_Helper (Node : Ada_Node'Class) return Visit_Status;
   --  If node is a subprogram declaration (regular or generic instantiation),
   --  include it in the Libgen context. Otherwise keep traversing the tree.

   procedure Resolve_Generation_Runtime
     (Cmd       : Command_Line;
      Gen_RTS   : out GNAT.OS_Lib.String_Access;
      Gen_Board : out GNAT.OS_Lib.String_Access);
   --  Resolve Gen_RTS/Gen_Board for the project target from the
   --  target-to-runtime configuration: entries from --tgen-target-config
   --  take precedence over the shipped tgen_target_runtimes.json.
   --  Leaves Gen_RTS and Gen_Board to null if no config maps the target.

   ---------------------
   -- Traverse_Helper --
   ---------------------

   function Traverse_Helper (Node : Ada_Node'Class) return Visit_Status is
      use TGen.Strings;
      Diags : String_Vector;

      procedure Report_Failures;
      --  Reports processing failures and skipped subprograms to the user.

      ---------------------
      -- Report_Failures --
      ---------------------

      procedure Report_Failures is
      begin
         Report_Err
           ("Error while processing "
            & Node.Image
            & ":"
            & ASCII.LF
            & Join (Diags)
            & ASCII.LF);
      end Report_Failures;
   begin
      --  Do not traverse package bodies

      if Node.Kind in Ada_Package_Body then
         return Over;
      end if;

      --  Do not traverse private child packages

      if Node.Kind = Ada_Library_Item
        and then Node.As_Library_Item.F_Has_Private
      then
         Report_Std
           ("gnattest-tgen: "
            & Libadalang.Support.Text.Image
                (Node
                   .P_Enclosing_Compilation_Unit
                   .P_Decl
                   .P_Fully_Qualified_Name)
            & ": Test input generation not supported for private packages;"
            & " skipping");
         return Over;
      end if;

      if not Common_Subp_Node_Filter (Node) then
         return Over;
      end if;

      --  Skip any non-instantiated generic decl, they will be processed as
      --  part of a generic instantiation, if any.

      if Node.Kind in Ada_Generic_Decl
        and then Node.P_Generic_Instantiations'Length = 0
      then
         return Over;
      end if;

      --  Collect all types used as parameters in subprogram declarations.
      --  Skip generic subprogram declarations as we only care about the
      --  instantiations. Also skip subprograms with zero parameters if there
      --  is no Global aspect attached.
      --
      --  Ada_Subp_Decl designates all "regular" subprograms, excluding enum
      --  literals, entries, generic formal subprograms and abstract
      --  subprograms with the exception of expression functions, null
      --  procedures and subprogram renamings which are considered as
      --  subprogram bodies in LAL.

      if Node.Kind
         in Ada_Subp_Decl
          | Ada_Expr_Function
          | Ada_Null_Subp_Decl
          | Ada_Subp_Renaming_Decl
      then

         --  Don't do anything if the subprogram isn't allowed (in case the
         --  user is filtering test generation).

         if not Test.Common.Is_Subprogram_Allowed (Node.As_Basic_Decl) then
            Me.Trace (Node.Image & ": subprogram skipped");
            return Over;
         end if;

         --  Check, if the subprogram has zero parameters. If so, only add it
         --  to the generation context if it has a non null global annotation.

         declare
            Subp_Decl              : Basic_Decl renames Node.As_Basic_Decl;
            Has_Global_Aspect      : constant Boolean :=
              Subp_Decl.P_Has_Aspect (Global_Aspect_Name);
            Has_Null_Global_Aspect : constant Boolean :=
              (if Has_Global_Aspect
               then
                 Subp_Decl.P_Get_Aspect (Global_Aspect_Name).Value.Kind
                 = Ada_Null_Literal);
         begin
            if Subp_Decl.P_Subp_Spec_Or_Null.P_Params'Length = 0
              and then (not Has_Global_Aspect or else Has_Null_Global_Aspect)
            then
               return Over;
            end if;
         end;

         --  Register the subprogram in TGen, we only need the marshalling lib
         --  when generating binary tests (as we need the conversion tools to
         --  translate from JSON to binary).

         if not Include_Subp
                  (Test.Common.TGen_Libgen_Ctx,
                   Node.As_Basic_Decl,
                   Diags,
                   Requested_IO_Support =>
                     (if Test.Common.Gen_Bin_Tests
                      then TGen.Libgen.IO_Input
                      else TGen.Libgen.IO_None))
         then
            Report_Failures;
         end if;
         return Over;
      end if;

      --  Traverse subprogram declarations in generic package instantiations
      if Node.Kind in Ada_Generic_Package_Instantiation then
         Node
           .As_Generic_Package_Instantiation
           .P_Designated_Generic_Decl
           .As_Generic_Package_Decl
           .F_Package_Decl
           .Traverse (Traverse_Helper'Access);
         return Over;
      end if;
      return Into;
   end Traverse_Helper;

   --------------------
   -- Process_Source --
   --------------------

   procedure Process_Source (Unit : Analysis_Unit) is
   begin
      Traverse (Unit.Root, Traverse_Helper'Access);
   end Process_Source;

   --------------------------------
   -- Resolve_Generation_Runtime --
   --------------------------------

   procedure Resolve_Generation_Runtime
     (Cmd       : Command_Line;
      Gen_RTS   : out GNAT.OS_Lib.String_Access;
      Gen_Board : out GNAT.OS_Lib.String_Access)
   is
      Override : constant GNAT.OS_Lib.String_Access :=
        Arg (Cmd, TGen_Target_Config);

      function Lookup_Config (Config_File : String) return Boolean;
      --  If Config_File exists and contains an entry for
      --  Test.Common.Target_Val, set Gen_RTS (and Gen_Board if present) and
      --  return True. Return False otherwise.

      -------------------
      -- Lookup_Config --
      -------------------

      function Lookup_Config (Config_File : String) return Boolean is
         use type GNAT.OS_Lib.String_Access;
      begin
         if not Ada.Directories.Exists (Config_File) then
            return False;
         end if;

         declare
            Root, Targets, Entry_Val : JSON_Value;
         begin
            declare
               Config_Res : constant Read_Result := Read_File (Config_File);
            begin
               if not Config_Res.Success then
                  Cmd_Error_No_Help
                    ("Error loading configuration for on-targe value"
                     & " generation from "
                     & Config_File);
               else
                  Root := Config_Res.Value;
               end if;
            exception
               when GNATCOLL.JSON.Invalid_JSON_Stream =>
                  Cmd_Error_No_Help
                    ("invalid JSON in target-to-runtime configuration"
                     & " file "
                     & Config_File);
            end;

            if not Root.Has_Field ("targets") then
               return False;
            end if;
            Targets := Root.Get ("targets");
            if not Targets.Has_Field (Test.Common.Target_Val.all) then
               return False;
            end if;
            Entry_Val := Targets.Get (Test.Common.Target_Val.all);
            if not Entry_Val.Has_Field ("runtime") then
               return False;
            end if;

            Gen_RTS := new String'(Entry_Val.Get ("runtime"));
            if Entry_Val.Has_Field ("board") then
               Gen_Board := new String'(Entry_Val.Get ("board"));
            end if;
            return True;
         end;
      end Lookup_Config;

      Builtin_Config : constant String :=
        Ada.Directories.Containing_Directory
          (Ada.Directories.Containing_Directory
             (GNAT.OS_Lib.Locate_Exec_On_Path ("gnattest").all))
        & GNAT.OS_Lib.Directory_Separator
        & "share"
        & GNAT.OS_Lib.Directory_Separator
        & "tgen"
        & GNAT.OS_Lib.Directory_Separator
        & "tgen_target_runtimes.json";
   begin
      if Override not in null and then Override.all /= "" then
         if not Lookup_Config (Override.all) then
            Cmd_Error_No_Help
              ("Could not determine substitution runtime to use for on-target"
               & " value generation from the file passed to"
               & " --tgen-target-config.");
         end if;
      elsif not Lookup_Config (Builtin_Config) then
         Cmd_Error_No_Help
           ("Could not determine substitution runtime to use for on-target"
            & " value generation from the builtin configuration file. You"
            & " can provide your own configuration through"
            & " --tgen-target-config if you have a runtime that is supported"
            & " by gnatemulator.");
      end if;
   end Resolve_Generation_Runtime;

   ----------------------------
   -- Generate_Build_And_Run --
   ----------------------------

   procedure Generate_Build_And_Run (Cmd : Command_Line) is
      use GNATCOLL.OS.Process;
      use type GNAT.OS_Lib.String_Access;
      Dir_Sep : Character renames GNAT.OS_Lib.Directory_Separator;

      Build_Args  : Argument_List;
      Run_Args    : Argument_List;
      Harness_Dir : constant String :=
        Tool_Temp_Dir.all & Dir_Sep & "tgen_Harness";
      Ext_Acc     : GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Get_Executable_Suffix;
      Ext         : constant String := Ext_Acc.all;

      On_Target : constant Boolean := Test.Common.Is_Cross_Target;
      --  When targeting a cross configuration, the harness is cross-built and
      --  executed on the target through gnatemu (JSON generation only).

      Harness_Exe : constant String :=
        Harness_Dir
        & Dir_Sep
        & "obj"
        & Dir_Sep
        & "generation_main"
        & (if On_Target then "" else Ext); -- no extension needed on target

      Serial_Capture : constant String :=
        Harness_Dir & Dir_Sep & "generation_output.txt";
      --  File where the target harness JSON output is captured over the serial
      --  port by gnatemu.

      Gen_RTS   : GNAT.OS_Lib.String_Access := null;
      Gen_Board : GNAT.OS_Lib.String_Access := null;
      --  Predefined GNAT runtime and gnatemu board used to build and run the
      --  harness on target. Only the type layout (target ABI) matters for
      --  value generation, so a gnatemu-supported runtime is used regardless
      --  of the runtime the user's project declares. Resolved on demand (only
      --  when generating on target) by Resolve_Generation_Runtime; Gen_RTS
      --  stays null when the target has no mapping.

      procedure Demux_Serial_Capture;
      --  Parse the framed JSON blocks captured from the target serial port and
      --  write one JSON file per package into JSON_Test_Dir. The framing
      --  markers must stay in sync with TGen.Libgen (harness side).

      --------------------------
      -- Demux_Serial_Capture --
      --------------------------

      procedure Demux_Serial_Capture is
         use Ada.Text_IO;
         Capture : File_Type;

         function Strip_CR (S : String) return String
         is (if S'Length /= 0 and then S (S'Last) = ASCII.CR
             then S (S'First .. S'Last - 1)
             else S);

      begin
         if not Ada.Directories.Exists (Serial_Capture) then
            Report_Err
              ("The test generation harness produced no output on the"
               & " target.");
            return;
         end if;

         Ada.Directories.Create_Path (Test.Common.JSON_Test_Dir.all);

         Open (Capture, In_File, Serial_Capture);
         while not End_Of_File (Capture) loop
            declare
               Line : constant String := Strip_CR (Get_Line (Capture));
            begin
               if Line'Length >= JSON_Start_Prefix'Length
                 and then
                   Line
                     (Line'First .. Line'First + JSON_Start_Prefix'Length - 1)
                   = JSON_Start_Prefix
               then
                  declare
                     Fname   : constant String :=
                       Line
                         (Line'First + JSON_Start_Prefix'Length .. Line'Last);
                     Content : Unbounded_String;
                     Out_F   : File_Type;

                  begin
                     while not End_Of_File (Capture) loop
                        declare
                           JLine : constant String :=
                             Strip_CR (Get_Line (Capture));
                        begin
                           exit when JLine = JSON_End_Marker;
                           Append (Content, JLine);
                        end;
                     end loop;
                     Create
                       (Out_F,
                        Out_File,
                        Test.Common.JSON_Test_Dir.all & Dir_Sep & Fname);
                     Put (Out_F, To_String (Content));
                     Close (Out_F);
                  end;
               end if;
            end;
         end loop;
         Close (Capture);
      end Demux_Serial_Capture;

   begin
      GNAT.OS_Lib.Free (Ext_Acc);

      --  Check if we have a non empty list of subprograms to generate test
      --  case vectors for.

      if not Test.Common.TGen_Libgen_Ctx.Is_Generation_Required then
         Report_Std ("No subprogram supported for test case generation.");
         return;
      end if;

      --  Binary test vectors rely on per-test files and stream I/O, which
      --  cannot be transported over the serial port: reject the combination.

      if On_Target and then Test.Common.Gen_Bin_Tests then
         Report_Err
           ("Binary test vector generation (--gen-test-binary) is not"
            & " supported when targeting a cross configuration; use JSON"
            & " generation instead.");
         return;
      end if;

      --  On target, the harness is built and run with a predefined,
      --  gnatemu-supported runtime chosen from the project target (only the
      --  type layout, i.e. the target ABI, matters for value generation).
      --  Resolve it now, and fail with an error when the target is unmapped.

      if On_Target then
         Resolve_Generation_Runtime (Cmd, Gen_RTS, Gen_Board);
      end if;

      --  Generate the harness

      TGen.Libgen.Generate_Harness
        (Test.Common.TGen_Libgen_Ctx,
         Harness_Dir,
         Test.Common.JSON_Test_Dir.all,
         Test.Common.TGen_Strat_Kind,
         Test.Common.TGen_Num_Tests,
         Test.Common.Gen_Bin_Tests,
         On_Target => On_Target);

      --  Build the harness. For this, reuse the gpr options passed on the
      --  command line.

      Build_Args.Append ("gprbuild");
      if not Test.Common.Verbose and then not Debug_Flag_1 then
         Build_Args.Append ("-q");
      end if;
      Build_Args.Append ("-P");
      Build_Args.Append
        (Harness_Dir & Dir_Sep & "tgen_generation_harness.gpr");
      Populate_X_Vars (Build_Args, Cmd);

      if On_Target then

         --  On target, build for the project target but with the mapped
         --  predefined runtime (Gen_RTS), not the runtime the user's project
         --  declares. Passing --target/--RTS on the command line is what makes
         --  Project'Runtime ("Ada") reflect that runtime in the withed
         --  tgen_rts.gpr (so it excludes its host-only units and selects the
         --  embedded environment body) and overrides the user project's
         --  Runtime. The command line also requests the full profile
         --  explicitly (tgen_rts defaults to the marshalling-only subset on a
         --  non-native runtime).

         if Test.Common.Target_Val /= null
           and then Test.Common.Target_Val.all /= ""
         then
            Build_Args.Append ("--target=" & Test.Common.Target_Val.all);
         end if;
         Build_Args.Append ("--RTS=" & Gen_RTS.all);
         Build_Args.Append ("-XTGEN_RTS_PROFILE=full");

         --  Add the local copy of tgen_rts on the command line to override the
         --  restricted version the user may have installed.

         Build_Args.Append ("-aP" & Harness_Dir & Dir_Sep & "tgen_rts");

         --  Minimize the size of the executable, the full TGen runtime is
         --  quite heavy, it can be an issue on some targets.

         Build_Args.Append ("-cargs:Ada");
         Build_Args.Append ("-Os");
         Build_Args.Append ("-ffunction-sections");
         Build_Args.Append ("-largs");
         Build_Args.Append ("-Wl,--gc-sections");

      end if;

      --  Suppress all warning/info messages and style checks

      Build_Args.Append ("-cargs:ada");
      Build_Args.Append ("-gnatws");
      Build_Args.Append ("-gnatyN");

      if Debug_Flag_1 then
         Build_Args.Append ("-g");
         Build_Args.Append ("-O0");
         Build_Args.Append ("-bargs");
         Build_Args.Append ("-Es");
      end if;

      Run (Build_Args, "Build of the test generation harness");

      if On_Target then

         --  Run the harness on the emulated target and capture its JSON output
         --  over the serial port, then demux it into per-package JSON files.

         Run_Args.Append
           (Utils.Projects.Project_Tree.Root_Project.Compiler_Prefix
            & "gnatemu"
            & Ext);
         if Gen_Board /= null and then Gen_Board.all /= "" then
            Run_Args.Append ("--board=" & Gen_Board.all);
         end if;
         Run_Args.Append ("--serial=file:" & Serial_Capture);
         Run_Args.Append (Harness_Exe);
         Run (Run_Args, "Execution of the test generation harness on target");

         Demux_Serial_Capture;
      else
         Run_Args.Append (Harness_Exe);
         Run (Run_Args, "Execution of the test generation harness");
      end if;
   end Generate_Build_And_Run;

end Test.Generation;
