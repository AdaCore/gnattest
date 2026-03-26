------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                    Copyright (C) 2021-2022, AdaCore                      --
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
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings;             use Ada.Strings;
with Ada.Strings.Equal_Case_Insensitive;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;
with Ada.Text_IO;

with GNAT.Traceback.Symbolic;

with GNATCOLL.Traces;

pragma Warnings (Off);
with GPR2.Build.Source.Sets;
pragma Warnings (On);
with GPR2.Build.Unit_Info;
with GPR2.Options;
with GPR2.Project.Attribute;

with Libadalang.Analysis;         use Libadalang.Analysis;
with Libadalang.Project_Provider; use Libadalang.Project_Provider;

with Test.Command_Lines; use Test.Command_Lines;

with Utils.Environment;
with Utils.Formatted_Output;
with Utils.Projects.Aggregate;
with Utils.String_Utilities; use Utils.String_Utilities;
with Utils.Versions;

package body Utils.Projects is
   use Ada.Text_IO;

   use Source_Selection_Switches,
       Test_Boolean_Switches,
       Test_String_Switches,
       Test_String_Seq_Switches;

   package Source_Vectors is new
     Ada.Containers.Vectors
       (Element_Type => GPR2.Build.Source.Object,
        Index_Type   => Positive,
        "="          => GPR2.Build.Source."=");
   subtype Source_Vector is Source_Vectors.Vector;

   My_Project_Tree : aliased GPR2.Project.Tree.Object;
   --  Project tree for the user project

   function Has_Mains_And_Ada_Only
     (Prj : GPR2.Project.Tree.Object) return Boolean;
   --  Checks that root project has at least one main specified and all of them
   --  are Ada mains, no C/C++ or other languages.

   function Get_Main_Files
     (Prj : GPR2.Project.Tree.Object; CLI_Mains : String_Ref_Array)
      return Source_Vector;
   --  Return a list of main files, either from the CLI if provided, or from
   --  the GPR file.

   function Get_Files_From_Closure
     (Prj : GPR2.Project.Tree.Object; Mains : Source_Vector)
      return String_Vector;
   --  Provided that the tool arguments contain '-U main_unit' parameter,
   --  tries to get the full closure of main_unit and to store it as tool
   --  argument files.

   procedure Get_Sources_From_Project
     (Prj                 : GPR2.Project.Tree.Object;
      CLI_Filenames       : in out String_Ref_Vector;
      Update_All          : Boolean;
      No_Subprjs          : Boolean;
      Files_Switch_Passed : Boolean);
   --  Extracts and stores the list of sources of the project to process as
   --  tool arguments.
   --
   --  Parameters:
   --  - Prj: The project we are sourcing from.
   --  - CLI_Filenames: Filenames passed on the command line.
   --  - Update_All: True if -U was passed on the CLI.
   --  - No_Subprjs: True if --no-subprojects was passed on the CLI.
   --  - Files_Switch_Passed: True if at least one -files parameter was passed
   --                         on the CLI.
   --
   --  More documentation is needed:
   --
   --  * when we extract the sources from the project * what happens when
   --    o there is no -U option
   --    o -U option is specified, but without the main unit
   --    o -U option is specified with the main unit name
   --
   --  ??? Extended projects???

   function Extract_Gnattest_Options
     (Prj : GPR2.Project.Tree.Object; Cmd : Command_Line) return String_Vector;
   --  Extract gnattest options from the Test.Switches/Default_Switches/
   --  Gnattest_Switches project attributes.

   procedure Process_Project
     (Cmd               : in out Command_Line;
      Cmd_Args          : String_Vector;
      Global_Report_Dir : out String_Ref;
      My_Project_Tree   : out GPR2.Project.Tree.Object);

   -----------------
   -- Attr_String --
   -----------------

   function Attr_String (A : Attribute) return String is
      A_Str : constant String := A'Image;
   begin
      return A_Str (A_Str'First .. A_Str'Last - 5);
   end Attr_String;

   ---------
   -- "+" --
   ---------

   function "+" (A : Attribute) return String is
   begin
      return Test.Common.GT_Package & "." & To_Lower (Attr_String (A));
   end "+";

   function "+" (A : Attribute) return GPR2.Q_Attribute_Id is
   begin
      return (GPR2_GT_Package, GPR2."+" (GPR2.Name_Type (Attr_String (A))));
   end "+";

   -------------------------
   -- Outermost_Extending --
   -------------------------

   function Outermost_Extending
     (View : GPR2.Project.View.Object) return GPR2.Project.View.Object
   is
      Result : GPR2.Project.View.Object := View;
   begin
      while Result.Is_Extended loop
         Result := Result.Extending;
      end loop;
      return Result;
   end Outermost_Extending;

   ---------------------------
   -- Recursive_Source_Dirs --
   ---------------------------

   function Recursive_Source_Dirs return GPR2.Path_Name.Set.Object is
      Result : GPR2.Path_Name.Set.Object;
   begin
      for View of My_Project_Tree.Ordered_Views loop
         for Dir of View.Source_Directories loop
            Result.Append (Dir);
         end loop;
      end loop;
      return Result;
   end Recursive_Source_Dirs;

   ----------------
   -- Attr_Value --
   ----------------

   function Attr_Value
     (V : GPR2.Project.View.Object; Attr : Q_Attribute_Id) return String is
   begin
      return String (V.Attribute (Attr).Value.Text);
   end Attr_Value;

   ---------
   -- Src --
   ---------

   function Src (Filename : String) return GPR2.Build.Source.Object is
   begin
      return
        My_Project_Tree.Root_Project.Visible_Source
          (GPR2.Path_Name.Create (Create (+Filename)));
   end Src;

   --------------
   -- View_For --
   --------------

   function View_For (P : String) return GPR2.Project.View.Object is
   begin
      for Prj of Project_Tree.Ordered_Views loop
         if Ada.Strings.Equal_Case_Insensitive (String (Prj.Name), P) then
            return Prj;
         end if;
      end loop;
      return GPR2.Project.View.Undefined;
   end View_For;

   -------------------
   -- To_File_Array --
   -------------------

   function To_File_Array
     (Files : GPR2.Path_Name.Set.Object) return GNATCOLL.VFS.File_Array
   is
      Result : File_Array (1 .. Integer (Files.Length));
      I      : Positive := 1;
   begin
      for F of Files loop
         Result (I) := F.Virtual_File;
         I := I + 1;
      end loop;
      return Result;
   end To_File_Array;

   ------------------
   -- Load_Project --
   ------------------

   function Load_Project
     (Cmd : Command_Line; Project_File : String)
      return GPR2.Project.Tree.Object
   is
      Opts : GPR2.Options.Object;
      Tree : GPR2.Project.Tree.Object;
   begin
      Opts.Add_Switch (GPR2.Options.P, Project_File, Override => True);
      if Arg (Cmd, Target) /= null then
         Opts.Add_Switch (GPR2.Options.Target, Arg (Cmd, Target).all);
      end if;
      if Arg (Cmd, Run_Time_System) /= null then
         Opts.Add_Switch (GPR2.Options.RTS, Arg (Cmd, Run_Time_System).all);
      end if;
      if Arg (Cmd, Follow_Symbolic_Links) then
         Opts.Add_Switch (GPR2.Options.Resolve_Links);
      end if;

      --  Add scenario variables

      declare
         X_Vars : constant String_Ref_Array := Arg (Cmd, External_Variable);

         GPR_TOOL_Set : Boolean := False;
         --  True if -XGPR_TOOL=... appears on the command line

      begin
         for X of X_Vars loop

            --  X is of the form "VAR=value"

            declare
               pragma Assert (X'First = 1);
               Equal : constant Natural := Index (X.all, "=");
               X_Var : String renames X (1 .. Equal - 1);
               X_Val : String renames X (Equal + 1 .. X'Last);
            begin
               if Equal = 0 then
                  Cmd_Error ("wrong parameter of -X option: " & X.all);
               end if;
               if X_Var = "GPR_TOOL" then
                  GPR_TOOL_Set := True;
               end if;
               Opts.Add_Switch (GPR2.Options.X, X_Var & "=" & X_Val);
            end;
         end loop;

         --  Set GPR_TOOL, unless it is already set via an environment variable
         --  or on the command line.

         if not Ada.Environment_Variables.Exists ("GPR_TOOL")
           and then not GPR_TOOL_Set
         then
            Opts.Add_Switch (GPR2.Options.X, "GPR_TOOL=gnattest");
         end if;
      end;

      if not Tree.Load
               (Opts,
                With_Runtime         => True,
                Artifacts_Info_Level => GPR2.Sources_Units,
                Absent_Dir_Error     => GPR2.No_Error,
                Check_Drivers        => False)
      then
         Cmd_Error ("Could not load the project file, aborting.");
      end if;
      return Tree;
   end Load_Project;

   ---------------------
   -- Process_Project --
   ---------------------

   procedure Process_Project
     (Cmd               : in out Command_Line;
      Cmd_Args          : String_Vector;
      Global_Report_Dir : out String_Ref;
      My_Project_Tree   : out GPR2.Project.Tree.Object)
   is
      procedure Load_Tool_Project;

      procedure Load_Aggregated_Project;
      --  Loads My_Project_Tree (that is supposed to be an aggregate project),
      --  then unloads it and loads in the same environment the project passed
      --  as a parameter of '--aggregated_project_file option' (which is
      --  supposed to be a (non-aggregate) project aggregated by
      --  My_Project_Tree.

      procedure Set_Global_Result_Dirs;
      --  Sets the directory to place the global tool results into.

      -----------------------
      -- Load_Tool_Project --
      -----------------------

      procedure Load_Tool_Project is
      begin
         My_Project_Tree := Load_Project (Cmd, Arg (Cmd, Project_File).all);
         if My_Project_Tree.Root_Project.Kind = K_Aggregate then
            Aggregate.Collect_Aggregated_Projects (My_Project_Tree);
         end if;
      end Load_Tool_Project;

      -----------------------------
      -- Load_Aggregated_Project --
      -----------------------------

      procedure Load_Aggregated_Project is
         pragma Assert (Arg (Cmd, Aggregated_Project_File) /= null);

         Aggregated_Name : constant String :=
           Arg (Cmd, Aggregated_Project_File).all;
      begin
         --  Start by checking that the original project is an aggregate
         --  project.

         My_Project_Tree := Load_Project (Cmd, Arg (Cmd, Project_File).all);
         pragma Assert (My_Project_Tree.Root_Project.Kind = GPR2.K_Aggregate);
         My_Project_Tree.Unload;

         My_Project_Tree := Load_Project (Cmd, Aggregated_Name);
         pragma Assert (My_Project_Tree.Root_Project.Kind /= GPR2.K_Aggregate);
      end Load_Aggregated_Project;

      ----------------------------
      -- Set_Global_Result_Dirs --
      ----------------------------

      procedure Set_Global_Result_Dirs is
         Global_Report_Dir : Virtual_File;
         Root_Prj          : constant GPR2.Project.View.Object :=
           My_Project_Tree.Root_Project;
      begin
         --  TODO??? simplify this code and assume we always have an object
         --  directory.

         Global_Report_Dir := Root_Prj.Object_Directory.Virtual_File;

         if Global_Report_Dir = No_File then
            Global_Report_Dir :=
              GNATCOLL.VFS.Create
                (GNATCOLL.VFS."+" (String (Root_Prj.Path_Name.Dir_Name)));
         end if;
         Process_Project.Global_Report_Dir :=
           new String'(GNATCOLL.VFS."+" (Global_Report_Dir.Full_Name));
      end Set_Global_Result_Dirs;

      --  Start of processing for Process_Project

   begin
      GNATCOLL.Traces.Parse_Config_File;

      if Arg (Cmd, Aggregated_Project_File) = null then
         Load_Tool_Project;
      else
         Load_Aggregated_Project;
      end if;

      --  Error out if this is the root project is an abstract (i.e. without
      --  sources) project.

      if My_Project_Tree.Root_Project.Kind = K_Abstract then
         Cmd_Error
           ("gnattest does not support abstract projects (without sources)");
      end if;

      if My_Project_Tree.Root_Project.Kind in Aggregate_Kind then

         if Num_File_Names (Cmd) /= 0 then
            Cmd_Error
              ("argument file cannot be specified for aggregate project");
         end if;

         if Arg (Cmd) = Update_All then
            Cmd_Error ("'-U' cannot be specified for aggregate project");
         end if;

      --  Information in 'else' below is not extracted from the aggregate
      --  project itself.

      else
         Set_Global_Result_Dirs;

         declare
            In_Prj_Switches : constant String_Vector :=
              Extract_Gnattest_Options (My_Project_Tree, Cmd);
         begin
            if not In_Prj_Switches.Is_Empty then
               Parse
                 (In_Prj_Switches,
                  Cmd,
                  Phase              => Project_File,
                  Collect_File_Names => False);
            end if;
         end;

         --  Now we need to Parse again, so command-line args override project
         --  file args. This needs to be done before getting sources from the
         --  project, as -U/--no-subprojects affect source selection and may
         --  override each other.

         Parse
           (Cmd_Args, Cmd, Phase => Cmd_Line_2, Collect_File_Names => False);
      end if;
   end Process_Project;

   -------------------------------
   -- Read_File_Names_From_File --
   -------------------------------

   procedure Read_File_Names_From_File
     (Par_File_Name : String;
      Action        : not null access procedure (File_Name : String))
   is
      Arg_File    : File_Type;
      Next_Ch     : Character;
      End_Of_Line : Boolean;

      function Get_File_Name return String;
      --  Reads from Par_File_Name the name of the next file (the file to read
      --  from should exist and be opened). Returns an empty string if there is
      --  no file names in Par_File_Name any more

      function Get_File_Name return String is
         File_Name_Buffer : String (1 .. 16 * 1_024);
         File_Name_Len    : Natural := 0;
      begin
         if not End_Of_File (Arg_File) then
            Get (Arg_File, Next_Ch);

            while Next_Ch in ' ' | ASCII.HT | ASCII.LF | ASCII.CR loop
               exit when End_Of_File (Arg_File);
               Get (Arg_File, Next_Ch);
            end loop;

            --  If we are here. Next_Ch is neither a white space nor
            --  end-of-line character. Two cases are possible, they
            --  require different processing:
            --
            --  1. Next_Ch = '"', this means that the file name is surrounded
            --     by quotation marks and it can contain spaces inside.
            --
            --  2. Next_Ch /= '"', this means that the file name is bounded by
            --     a white space or end-of-line character

            if Next_Ch = '"' then

               --  We do not generate any warning for badly formatted content
               --  of the file such as
               --
               --    file_name_1
               --    "file name 2
               --    file_name_3
               --
               --  (We do not check that quotation marks correctly go by pairs)

               --  Skip leading '"'
               Get (Arg_File, Next_Ch);

               while Next_Ch not in '"' | ASCII.LF | ASCII.CR loop
                  File_Name_Len := File_Name_Len + 1;
                  File_Name_Buffer (File_Name_Len) := Next_Ch;

                  Look_Ahead (Arg_File, Next_Ch, End_Of_Line);

                  exit when End_Of_Line or else End_Of_File (Arg_File);

                  Get (Arg_File, Next_Ch);
               end loop;

               if Next_Ch = '"' and then not Ada.Text_IO.End_Of_Line (Arg_File)
               then
                  --  skip trailing '"'
                  Get (Arg_File, Next_Ch);
               end if;
            else
               while Next_Ch not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR loop
                  File_Name_Len := File_Name_Len + 1;
                  File_Name_Buffer (File_Name_Len) := Next_Ch;

                  Look_Ahead (Arg_File, Next_Ch, End_Of_Line);

                  exit when End_Of_Line or else End_Of_File (Arg_File);

                  Get (Arg_File, Next_Ch);
               end loop;
            end if;

         end if;

         return File_Name_Buffer (1 .. File_Name_Len);
      end Get_File_Name;

      --  Start of processing for Read_File_Names_From_File

   begin
      if not Is_Regular_File (Par_File_Name) then
         Cmd_Error (Par_File_Name & " does not exist");
      end if;

      Open (Arg_File, In_File, Par_File_Name);

      loop
         declare
            Tmp_Str : constant String := Get_File_Name;
         begin
            exit when Tmp_Str = "";
            Action (Tmp_Str);
         end;
      end loop;

      Close (Arg_File);
   exception
      when others =>
         Cmd_Error ("cannot read arguments from " & Par_File_Name);
   end Read_File_Names_From_File;

   -----------------------
   -- Unit_Name_To_Unit --
   -----------------------

   function Unit_Name_To_Unit
     (Unit_Name : String) return GPR2.Build.Compilation_Unit.Object
   is
      CU : GPR2.Build.Compilation_Unit.Object;
   begin
      for View of Project_Tree.Ordered_Views loop
         CU := View.Own_Unit (Name_Type (Unit_Name));
         if CU.Is_Defined then
            return CU;
         end if;
      end loop;
      return GPR2.Build.Compilation_Unit.Undefined;
   end Unit_Name_To_Unit;

   ------------------
   -- Project_Tree --
   ------------------

   function Project_Tree return GPR2.Project.Tree.Object
   is (My_Project_Tree);

   ------------
   -- Unload --
   ------------

   procedure Unload is
   begin
      My_Project_Tree.Unload;
   end Unload;

   --------------------------
   -- Process_Command_Line --
   --------------------------

   procedure Process_Command_Line
     (Cmd               : in out Command_Line;
      Global_Report_Dir : out String_Ref;
      Print_Help        : not null access procedure)
   is
      --  We have to Parse the command line BEFORE we Parse the project file,
      --  because command-line args tell us the name of the project file, and
      --  options for processing it.

      --  We have to Parse the command line AFTER we Parse the project file,
      --  because command-line switches should override those from the project
      --  file.

      --  So we do both.

      --  In addition, we parse the command line ignoring errors first, for
      --  --version and --help switches. ???This also sets debug flags, etc.

      Cmd_Args : String_Vector renames Utils.Command_Lines.Args;
   begin
      --  First, process --version or --help switches, if present

      Parse
        (Cmd_Args,
         Cmd,
         Collect_File_Names => True,
         Phase              => Cmd_Line_1,
         Ignore_Errors      => True);

      for Dbg of Arg (Cmd, Debug) loop
         Set_Debug_Options (Dbg.all);
      end loop;

      if Arg (Cmd, Version) then
         Versions.Print_Tool_Version;
         Environment.Clean_Up;
         OS_Exit (0);
      end if;

      if Arg (Cmd, Help) then
         Print_Help.all;
         Environment.Clean_Up;
         OS_Exit (0);
      end if;

      if Arg (Cmd, Verbose) and then Arg (Cmd, Aggregated_Project_File) = null
      then
         Versions.Print_Version_Info;
      end if;
      if Error_Detected (Cmd) then
         Parse
           (Cmd_Args, Cmd, Phase => Cmd_Line_1, Collect_File_Names => False);

         --  Can't get here, because Parse will have raised Command_Line_Error
         raise Program_Error;
      end if;

      declare
         procedure Update_File_Name (File_Name : in out String_Ref);
         --  Set File_Name to the full name if -P specified. If the file
         --  doesn't exist, or is not a regular file, give an error.

         procedure Append_One (File_Name : String);
         --  Append one file name onto Cmd

         ----------------------
         -- Update_File_Name --
         ----------------------

         procedure Update_File_Name (File_Name : in out String_Ref) is
            File : constant Virtual_File :=
              Create (GNATCOLL.VFS."+" (File_Name.all));
         begin
            if File.Is_Regular_File then
               return;
            end if;

            if Arg (Cmd, Project_File) /= null then
               declare
                  Res : constant GPR2.Build.Source.Object :=
                    My_Project_Tree.Root_Project.Visible_Source
                      (Simple_Name
                         (Ada.Directories.Simple_Name (File_Name.all)));
               begin
                  if not Res.Is_Defined then
                     Cmd_Error ("file not found: " & File_Name.all);
                  end if;

                  if Res.Owning_View.Is_Externally_Built then
                     Cmd_Error_No_Help
                       (File_Name.all
                        & " is from externally built project "
                        & String (Res.Owning_View.Name));
                  end if;

                  File_Name := new String'(Res.Path_Name.String_Value);
               end;
            end if;
         end Update_File_Name;

         ----------------
         -- Append_One --
         ----------------

         procedure Append_One (File_Name : String) is
         begin
            Append_File_Name (Cmd, File_Name);
         end Append_One;

      begin
         if Arg (Cmd, Project_File) /= null then

            Process_Project
              (Cmd, Cmd_Args, Global_Report_Dir, My_Project_Tree);

            if My_Project_Tree.Root_Project.Kind not in Aggregate_Kind then

               --  ??? Code detangling: in order to keep 'Cmd' from
               --  Get_Sources_From_Project, copy the File_Names field of Cmd
               --  for now. Eventually, the filenames will come from somewhere
               --  else.

               declare
                  File_List : String_Ref_Vector :=
                    Utils.Command_Lines.String_Ref_Vectors.To_Vector
                      (Cmd.File_Names);
               begin
                  Get_Sources_From_Project
                    (My_Project_Tree,
                     File_List,
                     Arg (Cmd) = Update_All,
                     Arg (Cmd) = No_Subprojects,
                     Arg_Length (Cmd, Files) > 0);
                  Cmd.Set_File_Names (File_List);
               end;

               --  Create a temporary directory when processing a non-aggregate
               --  project.

               Environment.Create_Temp_Dir
                 (My_Project_Tree.Root_Project.Object_Directory.String_Value);
            end if;
         else
            Environment.Create_Temp_Dir;
         end if;

         --  Subsequent call to Parse command line again is performed inside
         --  Process_Project to happen in time for possible closure
         --  computation. And if there is no project file we already have
         --  all the switches from the first command line parsing.

         --  The following could just as well happen before the above
         --  Cmd_Line_2 Parse, because file names and "-files=par_file_name"
         --  switches came from the Cmd_Line_1 Parse, or from the project file.

         --  We process the "-files=par_file_name" switches by reading file
         --  names from the file(s) and appending those to the command line.
         --  Then we update the file names to contain directory information
         --  if appropriate.

         for Par_File_Name of Arg (Cmd, Files) loop
            Read_File_Names_From_File (Par_File_Name.all, Append_One'Access);
         end loop;

         Sort_File_Names (Cmd);
         Iter_File_Names (Cmd, Update_File_Name'Access);
      end;
   end Process_Command_Line;

   -----------------------
   -- Coverage_Switches --
   -----------------------

   function Coverage_Switches return Q_Attribute_Id is
   begin
      return
        Q_Attribute_Id'
          (Pack => GPR2."+" (GPR2.Name_Type'("coverage")),
           Attr => GPR2."+" (GPR2.Optional_Name_Type'("switches")));
   end Coverage_Switches;

   --------------------
   -- Emulator_Board --
   --------------------

   function Emulator_Board return Q_Attribute_Id is
   begin
      return
        Q_Attribute_Id'
          (Pack => GPR2."+" (GPR2.Name_Type'("emulator")),
           Attr => GPR2."+" (GPR2.Optional_Name_Type'("board")));
   end Emulator_Board;

   ------------------------
   -- Has_Ada_Mains_Only --
   ------------------------

   function Has_Mains_And_Ada_Only
     (Prj : GPR2.Project.Tree.Object) return Boolean
   is
      Mains : constant GPR2.Build.Compilation_Unit.Unit_Location_Vector :=
        Prj.Root_Project.Mains;
   begin
      return
        Mains.Length /= 0
        --  Empty Mains assumed to be non Ada-only

        and then (for all Main of Mains =>
                    Prj.Root_Project.Visible_Source (Main.Source).Language
                    = Ada_Language);
   end Has_Mains_And_Ada_Only;

   --------------------
   -- Get_Main_Files --
   --------------------

   function Get_Main_Files
     (Prj : GPR2.Project.Tree.Object; CLI_Mains : String_Ref_Array)
      return Source_Vector
   is
      Result : Source_Vector;
   begin
      --  If we have main files given as CLI arguments, use them
      if CLI_Mains'Length > 0 then
         for F of CLI_Mains loop
            Result.Append
              (My_Project_Tree.Root_Project.Visible_Source
                 (Simple_Name (F.all)));
         end loop;
      else
         for Main of Prj.Root_Project.Mains loop
            Result.Append (Prj.Root_Project.Visible_Source (Main.Source));
         end loop;
      end if;

      return Result;
   end Get_Main_Files;

   ----------------------------
   -- Get_Files_From_Closure --
   ----------------------------

   function Get_Files_From_Closure
     (Prj : GPR2.Project.Tree.Object; Mains : Source_Vector)
      return String_Vector
   is
      Result   : String_Vector;
      Provider : constant Unit_Provider_Reference :=
        Create_Project_Unit_Provider (Tree => Prj);

      Ctx : constant Analysis_Context :=
        Create_Context (Unit_Provider => Provider);

      package Path_Sets is new
        Ada.Containers.Indefinite_Ordered_Sets
          (Element_Type => GPR2.Path_Name.Object,
           "<"          => GPR2.Path_Name."<",
           "="          => GPR2.Path_Name."=");
      subtype Path_Set is Path_Sets.Set;

      Closure_Incomplete : Boolean := False;

      Closure : Path_Set;
      --  Cumulative closure of given main(s)

      procedure Update_Closure
        (New_Source : GPR2.Path_Name.Object; View : GPR2.Project.View.Object);
      --  Calculate unit dependencies with LAL and update the source closure
      --  accordingly.

      procedure Process_CU
        (Kind     : Unit_Kind;
         View     : GPR2.Project.View.Object;
         Path     : Path_Name.Object;
         Index    : Unit_Index;
         Sep_Name : Optional_Name_Type);
      --  Callback for GPR2.Build.Compilation_Unit.For_All_Part calling
      --  Update_Closure on the given CU.

      procedure Process_Source (Src : GPR2.Build.Source.Object);
      --  Process the given source and update the source closure
      --  accordingly.

      --------------------
      -- Update_Closure --
      --------------------

      procedure Update_Closure
        (New_Source : GPR2.Path_Name.Object; View : GPR2.Project.View.Object)
      is
         Unit : Analysis_Unit;
         CU   : Compilation_Unit;
      begin
         if Closure.Contains (New_Source) or else View.Is_Externally_Built then
            return;
         end if;
         Closure.Insert (New_Source);

         Unit := Ctx.Get_From_File (String (New_Source.Name));
         CU := Unit.Root.As_Compilation_Unit;

         for Dep of CU.P_Unit_Dependencies loop
            declare
               Src : constant GPR2.Build.Source.Object :=
                 Prj.Root_Project.Visible_Source
                   (GPR2.Path_Name.Create (+Dep.Unit.Get_Filename));
            begin
               --  LAL always return a dependency to the Standard unit,
               --  which does not have a corresponding source.

               if Src.Is_Defined then
                  Process_Source (Src);
               end if;
            end;

         end loop;

      exception
         when Ex : others =>
            Closure_Incomplete := True;
            Formatted_Output.Put
              ("\1\n",
               "could not get dependencies of "
               & String (New_Source.Base_Name));
            if Debug_Flag_U then
               Formatted_Output.Put
                 ("\1\n",
                  Ada.Exceptions.Exception_Name (Ex)
                  & " : "
                  & Ada.Exceptions.Exception_Message (Ex)
                  & ASCII.LF
                  & GNAT.Traceback.Symbolic.Symbolic_Traceback (Ex));
            end if;
      end Update_Closure;

      ----------------
      -- Process_CU --
      ----------------

      procedure Process_CU
        (Kind     : Unit_Kind;
         View     : GPR2.Project.View.Object;
         Path     : Path_Name.Object;
         Index    : Unit_Index;
         Sep_Name : Optional_Name_Type)
      is
         pragma Unreferenced (Kind, Index, Sep_Name);
      begin
         Update_Closure (Path, View);
      end Process_CU;

      --------------------
      -- Process_Source --
      --------------------

      procedure Process_Source (Src : GPR2.Build.Source.Object) is
         CU : constant GPR2.Build.Compilation_Unit.Object :=
           Unit_Name_To_Unit (String (Src.Unit.Name));
      begin
         CU.For_All_Part (Process_CU'Access);
      end Process_Source;

   begin
      --  Mains on the command line take precedence over the ones specified
      --  in the project file.

      for Main of Mains loop
         Process_Source (Main);
      end loop;

      if Closure_Incomplete then
         Formatted_Output.Put ("could not get complete closure\n");
      end if;

      if Debug_Flag_U then
         Formatted_Output.Put ("Closure:\n");
      end if;
      for Src of Closure loop
         Result.Append (Src.String_Value);
         if Debug_Flag_U then
            Formatted_Output.Put ("\1\n", String (Src.Base_Name));
         end if;
      end loop;

      return Result;
   exception
      when others =>
         Cmd_Error_No_Tool_Name ("could not get closure of specified sources");
   end Get_Files_From_Closure;

   ------------------------------
   -- Get_Sources_From_Project --
   ------------------------------

   procedure Get_Sources_From_Project
     (Prj                 : GPR2.Project.Tree.Object;
      CLI_Filenames       : in out String_Ref_Vector;
      Update_All          : Boolean;
      No_Subprjs          : Boolean;
      Files_Switch_Passed : Boolean)
   is
      All_Update : constant Boolean := Update_All;

      Num_Names : constant Natural := CLI_Filenames.Last_Index;
      --  Number of File_Names on the command line

      Argument_File_Specified : constant Boolean :=
        (Files_Switch_Passed or else (not All_Update and then Num_Names > 0));
      --  True if we have source files specified on the command line. If -U
      --  (Update_All) was specified, then the "file name" (if any) is taken
      --  to be the main unit name, not a file name.

      CLI_Main_Unit_Names : constant String_Ref_Array :=
        (if All_Update and then CLI_Filenames.Length /= 0
         then Utils.Command_Lines.String_Ref_Vectors.To_Array (CLI_Filenames)
         else []);
      --  If "-U main_unit_1 main_unit_2 ..." was specified, this returns the
      --  list of main units. Otherwise (-U was not specified, or was specified
      --  without main unit names), returns empty array.

   begin
      --  We get file names from the project file if no file names were
      --  given on the command line, either directly, or via one or more
      --  "-files=par_file_name" switches.

      if Argument_File_Specified then
         return;
      end if;

      if No_Subprjs
        or else (CLI_Main_Unit_Names'Length = 0
                 and then (All_Update
                           or else not Has_Mains_And_Ada_Only (Prj)))
      then

         --  IF --no-subprojects is passed, or there is no Main provided from
         --  CLI and none is usable from the project file, THEN select all
         --  sources of the project.

         declare
            Sources : constant GPR2.Build.Source.Sets.Object :=
              (if No_Subprjs
               then Prj.Root_Project.Sources
               else Prj.Root_Project.Visible_Sources);
         begin
            for S of Sources loop
               if not S.Owning_View.Is_Externally_Built
                 and then S.Language = Ada_Language
               then
                  Utils.Command_Lines.String_Ref_Vectors.Append
                    (CLI_Filenames, new String'(S.Path_Name.String_Value));
               end if;
            end loop;
         end;

         if All_Update and then CLI_Filenames.Length = 0 then
            Cmd_Error
              (Prj.Root_Project.Path_Name.String_Value
               & " does not contain source files");
         end if;

      else

         --  ELSE, Compute the source file list from the closure of the Mains.
         --  If any, use Mains from the CLI. Otherwise use those found in the
         --  project file.

         declare
            Mains : constant Source_Vector :=
              Get_Main_Files (Prj, CLI_Main_Unit_Names);
         begin

            --  We first need to erase the main unit names from the
            --  command line to avoid duplicates.
            CLI_Filenames :=
              Utils.Command_Lines.String_Ref_Vectors.Empty_Vector;

            for Src of Get_Files_From_Closure (Prj, Mains) loop
               Utils.Command_Lines.String_Ref_Vectors.Append
                 (CLI_Filenames, new String'(Src));
            end loop;
         end;
      end if;
   end Get_Sources_From_Project;

   ------------------------------
   -- Extract_Gnattest_Options --
   ------------------------------

   function Extract_Gnattest_Options
     (Prj : GPR2.Project.Tree.Object; Cmd : Command_Line) return String_Vector
   is
      function Process_Attr
        (Id    : Q_Attribute_Id;
         Index : GPR2.Project.Attribute_Index.Object :=
           GPR2.Project.Attribute_Index.Undefined) return String_Vector;
      --  Return the list values for the given attribute Id with the given
      --  index. If the attribute is not defined for the loaded project,
      --  return an empty vector.

      ------------------
      -- Process_Attr --
      ------------------

      function Process_Attr
        (Id    : Q_Attribute_Id;
         Index : GPR2.Project.Attribute_Index.Object :=
           GPR2.Project.Attribute_Index.Undefined) return String_Vector
      is
         Attr_Value : GPR2.Project.Attribute.Object;
         Result     : String_Vector;
      begin
         if Prj.Root_Project.Check_Attribute
              (Id, Index => Index, Result => Attr_Value)
         then
            for Val of Attr_Value.Values loop
               Result.Append (String (Val.Text));
            end loop;
         end if;
         return Result;
      end Process_Attr;

      Project_Switches : String_Vector :=
        Process_Attr (+Default_Switches_Attr);
   begin
      if Num_File_Names (Cmd) = 1 then
         declare
            File_Switches : constant String_Vector :=
              Process_Attr
                (+Switches_Attr,
                 GPR2.Project.Attribute_Index.Create
                   (File_Names (Cmd) (1).all));
         begin
            if not File_Switches.Is_Empty then
               Project_Switches := File_Switches;
            end if;
         end;
      end if;

      return Project_Switches;
   end Extract_Gnattest_Options;

end Utils.Projects;
