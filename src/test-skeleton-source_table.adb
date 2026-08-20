------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2011-2022, AdaCore                    --
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
with Ada.Containers.Indefinite_Ordered_Maps;

with GNAT.OS_Lib;               use GNAT.OS_Lib;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;

with GNATCOLL.VFS;    use GNATCOLL.VFS;
with GNATCOLL.Traces; use GNATCOLL.Traces;

with GPR2; use GPR2;
with GPR2.Build.Compilation_Unit;
with GPR2.Build.Source;
with GPR2.Path_Name;
with GPR2.Project.Attribute;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Tree;
with GPR2.Project.View;

with Utils.Projects; use Utils.Projects;

package body Test.Skeleton.Source_Table is
   Dir_Sep : Character renames GNAT.OS_Lib.Directory_Separator;

   Me         : constant Trace_Handle :=
     Create ("Skeletons.Sources", Default => Off);
   Me_Verbose : constant Trace_Handle :=
     Create ("Skeletons.Sources_Verbose", Default => Off);

   -----------------------
   -- Source File table --
   -----------------------

   Sources_Left  : Natural := 0;
   Total_Sources : Natural := 0;

   type SF_Record;

   type SF_Record is record

      Full_Source_Name : String_Access;
      --  This field stores the source name with full directory information
      --  in absolute form

      Suffixless_Name : String_Access;
      --  The source name without directory information and suffix (if any)
      --  is used to create the names of the tree file and ALI files

      Test_Destination : String_Access;
      --  The path to the corresponding test unit location.

      Stub_Destination : String_Access;
      --  The path to the corresponding stub unit location.

      Status : SF_Status;
      --  Status of the given source. Initially is set to Waiting, then is
      --  changed according to the results of the metrics computation

      Corresponding_Body : String_Access := null;
      --  Set in Stub Mode for package specs.

      Theoretical_Body : String_Access := null;
      --  Set for creating an instrumented body in case a bodyless spec would
      --  need a body due to expression functions.

      Stub_Data_Base_Spec : String_Access;
      Stub_Data_Base_Body : String_Access;
      --  Different projects in the hierarchy may have different naming
      --  schemes, but we won't have the access to this info once ASIS context
      --  is generated, so we need to calculate those names beforehand.

      Stub_Created : Boolean := False;

      Project_Name : String_Access;
      --  Name of corresponding project. Only relevant for bodies.
      Unit_Name    : String_Access := null;

      Inst_Dir : String_Access;
      --  Directory for overriding instrumented sources
   end record;

   package Source_File_Table is new
     Ada.Containers.Indefinite_Ordered_Maps (String, SF_Record);

   Current_Source : String_Access := null;

   use String_Set;

   use Source_File_Table;

   package Source_File_Locations renames String_Set;

   SF_Table : Source_File_Table.Map;
   --  Source Table itself

   SFL_Table : Source_File_Locations.Set;
   --  A set of paths to source files. Used for creation of project file.

   SF_Process_Iterator : Source_File_Table.Cursor;
   SF_Access_Iterator  : Source_File_Table.Cursor;
   SFL_Iterator        : Source_File_Locations.Cursor;

   Short_Source_Name_String : String_Access;
   Full_Source_Name_String  : String_Access;

   procedure Reset_Source_Process_Iterator;
   --  Sets SF_Iterator to the begining of SF_Table.

   function Normalize_Source_Name (Source_Name : String) return String;
   --  Normalize a source name using standard options (no link resolution,
   --  case insensitive). This is used consistently throughout the package.

   procedure Initialize_Source_Name_Strings (Fname : String);
   --  Initialize Short_Source_Name_String and Full_Source_Name_String
   --  from a given file name.

   procedure Cleanup_Source_Name_Strings;
   --  Free Short_Source_Name_String and Full_Source_Name_String.

   procedure Set_SF_Record_Suffixless_Name (SF_Rec : in out SF_Record);
   --  Extract and set the suffixless name in the SF_Record based on
   --  Short_Source_Name_String.

   procedure Update_SF_Record
     (Source_Name : String;
      Updater     : access procedure (SF_Rec : in out SF_Record));
   --  Retrieve an SF_Record from the table, apply the updater procedure,
   --  and replace it back in the table.

   procedure Extract_Last_Name_Index
     (Name : String_Access; First_Idx : out Natural; Last_Idx : out Natural);
   --  Extract the indexes o the last name of a full qualified name string.
   --  First_Idx is the index pointing to the begining of the last name.
   --  Last_Idx is the index pointing to the end of the last name.

   function Get_GPR2_Owning_View_From_Name
     (Name : String_Access) return Project.View.Object
   is (Project_Tree.Root_Project.Visible_Source
         (GPR2.Path_Name.Create (GNATCOLL.VFS.Create (+Name.all)))
         .Owning_View);
   --  Helper function. Return a GPR2 owned project view for a given name.

   ---------------------------
   -- Normalize_Source_Name --
   ---------------------------

   function Normalize_Source_Name (Source_Name : String) return String is
   begin
      return
        Normalize_Pathname
          (Name           => Source_Name,
           Resolve_Links  => False,
           Case_Sensitive => False);
   end Normalize_Source_Name;

   ------------------------------------
   -- Initialize_Source_Name_Strings --
   ------------------------------------

   procedure Initialize_Source_Name_Strings (Fname : String) is
   begin
      Short_Source_Name_String := new String'(Base_Name (Fname));
      Full_Source_Name_String := new String'(Normalize_Source_Name (Fname));
   end Initialize_Source_Name_Strings;

   ----------------------------------
   -- Cleanup_Source_Name_Strings --
   ----------------------------------

   procedure Cleanup_Source_Name_Strings is
   begin
      Free (Short_Source_Name_String);
      Free (Full_Source_Name_String);
   end Cleanup_Source_Name_Strings;

   ------------------------------------
   -- Set_SF_Record_Suffixless_Name --
   ------------------------------------

   procedure Set_SF_Record_Suffixless_Name (SF_Rec : in out SF_Record) is
      First_Idx : Natural;
      Last_Idx  : Natural;
   begin
      Extract_Last_Name_Index (Short_Source_Name_String, First_Idx, Last_Idx);
      SF_Rec.Suffixless_Name :=
        new String'(Short_Source_Name_String.all (First_Idx .. Last_Idx));
   end Set_SF_Record_Suffixless_Name;

   ----------------------
   -- Update_SF_Record --
   ----------------------

   procedure Update_SF_Record
     (Source_Name : String;
      Updater     : access procedure (SF_Rec : in out SF_Record))
   is
      SF_Rec : SF_Record;
      SN     : constant String := Normalize_Source_Name (Source_Name);
   begin
      SF_Rec := Source_File_Table.Element (SF_Table, SN);
      Updater (SF_Rec);
      Replace (SF_Table, SN, SF_Rec);
   end Update_SF_Record;

   -----------------------------
   -- Extract_Last_Name_Index --
   -----------------------------

   procedure Extract_Last_Name_Index
     (Name : String_Access; First_Idx : out Natural; Last_Idx : out Natural) is
   begin
      First_Idx := Name'First;
      Last_Idx := Name'Last;

      for J in reverse First_Idx + 1 .. Last_Idx loop

         if Name (J) = '.' then
            Last_Idx := J - 1;
            exit;
         end if;

      end loop;
   end Extract_Last_Name_Index;

   procedure Generate_Stub_Extension_Project
     (Proj             : String;
      Current_Infix    : String;
      Subroot_Stub_Prj : String;
      Get_Sources      :
        access procedure
          (Proj : String; Current_Proj_Present_Sources : out String_Set.Set));
   --  Create a extending project tree rooted at Proj, overriding the default
   --  sources in the tree with the required stubs and helper units.
   --  Get_Sources is a callback to get the list of sources that should be part
   --  of the extending project for Proj.
   --
   --  This is a helper for Enforce_Custom_Project_Extension and
   --  Enforce_Project_Extension.

   type Project_Record is record
      Path : String_Access;

      Stub_Dir : String_Access;
      --  Directory in which the stubbed sources must be generated

      Importing_List : List_Of_Strings.List;
      --  List of projects that depend on this project. This may be directly,
      --  or through project extensions.

      Imported_List : List_Of_Strings.List;
      --  List of projects that this project imports, either directly, or
      --  through dependencies of the extended projects. Note that this
      --  contains limited with-ed projects.

      Limited_Withed : String_Set.Set;
      --  Set of projects that are limited with'ed by this projects

      Is_Externally_Built  : Boolean := False;
      Is_Library           : Boolean := False;
      Needed_For_Extension : Boolean := False;

      Aggregate_Lib : Boolean := False;
      --  Whether this project is an aggregate library project. As an aggregate
      --  library project does not have sources itself and thus cannot "with"
      --  other projects, we'll use the Imported_List to represent the
      --  aggregated projects.

   end record;
   --  Representation of the important attributes of a project

   use List_Of_Strings;

   package Project_File_Table is new
     Ada.Containers.Indefinite_Ordered_Maps (String, Project_Record);
   use Project_File_Table;

   PF_Table : Project_File_Table.Map;

   function Is_Body (Source_Name : String) return Boolean;

   -----------------------------
   --  Add_Source_To_Process  --
   -----------------------------

   procedure Add_Source_To_Process (Fname : String) is
      New_SF_Record : SF_Record;
   begin
      Trace (Me, "adding source: " & Fname);

      if not Is_Regular_File (Fname) then
         Report_Std ("gnattest: " & Fname & " not found");
         return;
      end if;

      --  Check if we already have a file with the same short name:
      Initialize_Source_Name_Strings (Fname);

      if Source_Present (Full_Source_Name_String.all)
        and then Get_Source_Status (Full_Source_Name_String.all)
                 = Body_Reference
      then
         Trace (Me, "...replacing body reference");
         New_SF_Record := SF_Table.Element (Full_Source_Name_String.all);
         SF_Table.Delete (Full_Source_Name_String.all);
         New_SF_Record.Status := Waiting;
         Insert (SF_Table, Full_Source_Name_String.all, New_SF_Record);
         return;
      elsif Source_Present (Full_Source_Name_String.all) then
         --  Duplicate, just ignore it
         return;
      end if;

      --  Making the new SF_Record
      New_SF_Record.Full_Source_Name :=
        new String'(Full_Source_Name_String.all);

      Set_SF_Record_Suffixless_Name (New_SF_Record);

      New_SF_Record.Status := Waiting;

      if Stub_Mode_ON then
         declare
            Unit_Name : constant Optional_Name_Type :=
              Project_Tree.Root_Project.Visible_Source
                (GPR2.Path_Name.Create
                   (GNATCOLL.VFS.Create (GNATCOLL.VFS."+" (Fname))))
                .Unit
                .Name;
            Unit      : constant GPR2.Build.Compilation_Unit.Object :=
              Unit_Name_To_Unit (String (Unit_Name));

            Stub_Unit_Name : constant Name_Type :=
              Name_Type (String (Unit_Name) & "." & Stub_Data_Unit_Name);

            P : GPR2.Project.View.Object := Unit.Owning_View;
         begin
            if Unit.Has_Part (S_Body) then
               New_SF_Record.Corresponding_Body :=
                 new String'(Unit.Main_Body.Source.String_Value);
            end if;

            New_SF_Record.Stub_Data_Base_Spec :=
              new String'
                (String (P.Filename_For_Unit (Stub_Unit_Name, S_Spec)));

            New_SF_Record.Stub_Data_Base_Body :=
              new String'
                (String (P.Filename_For_Unit (Stub_Unit_Name, S_Body)));

            P := Outermost_Extending (P);
            New_SF_Record.Project_Name := new String'(String (P.Name));
         end;

      end if;

      if Instrument then
         declare
            Unit_Name : constant Optional_Name_Type :=
              Project_Tree.Root_Project.Visible_Source
                (GPR2.Path_Name.Create
                   (GNATCOLL.VFS.Create (GNATCOLL.VFS."+" (Fname))))
                .Unit
                .Name;
            Unit      : constant GPR2.Build.Compilation_Unit.Object :=
              Unit_Name_To_Unit (String (Unit_Name));

            P : constant GPR2.Project.View.Object := Unit.Owning_View;
         begin
            New_SF_Record.Inst_Dir :=
              new String'
                (P.Object_Directory.String_Value
                 & Dir_Sep
                 & To_Lower (String (P.Name))
                 & Instr_Suffix);

            if Unit.Has_Part (S_Body) then
               New_SF_Record.Corresponding_Body :=
                 new String'(Unit.Main_Body.Source.String_Value);
            else
               New_SF_Record.Theoretical_Body :=
                 new String'(String (P.Filename_For_Unit (Unit_Name, S_Body)));
            end if;
         end;
      end if;

      Insert (SF_Table, Full_Source_Name_String.all, New_SF_Record);

      Include
        (SFL_Table,
         Normalize_Pathname
           (Name           => Dir_Name (Full_Source_Name_String.all),
            Resolve_Links  => False,
            Case_Sensitive => False));

      Sources_Left := Sources_Left + 1;
      Total_Sources := Total_Sources + 1;

      Cleanup_Source_Name_Strings;

   end Add_Source_To_Process;

   -------------------------
   -- Add_Body_To_Process --
   -------------------------

   procedure Add_Body_To_Process
     (Fname : String; Pname : String; Uname : String)
   is
      New_SF_Record : SF_Record;
   begin
      Trace (Me, "adding " & Fname & " from project " & Pname);
      --  Check if we already have a file with the same short name:
      Initialize_Source_Name_Strings (Fname);

      --  Making the new SF_Record
      New_SF_Record.Full_Source_Name :=
        new String'(Full_Source_Name_String.all);

      Set_SF_Record_Suffixless_Name (New_SF_Record);

      New_SF_Record.Status := To_Stub_Body;

      New_SF_Record.Project_Name := new String'(Pname);
      New_SF_Record.Unit_Name := new String'(Uname);

      Insert (SF_Table, Full_Source_Name_String.all, New_SF_Record);

      Include
        (SFL_Table,
         Normalize_Pathname
           (Name           => Dir_Name (Full_Source_Name_String.all),
            Resolve_Links  => False,
            Case_Sensitive => False));

      Cleanup_Source_Name_Strings;
   end Add_Body_To_Process;

   ------------------------
   -- Add_Body_Reference --
   ------------------------

   procedure Add_Body_Reference (Fname : String) is
      New_SF_Record : SF_Record;
   begin
      Trace (Me, "adding source (as reference): " & Fname);

      if not Is_Regular_File (Fname) then
         Report_Std ("gnattest: " & Fname & " not found");
         return;
      end if;

      Initialize_Source_Name_Strings (Fname);

      --  Already present specs should not be overridden
      if SF_Table.Find (Full_Source_Name_String.all)
        /= Source_File_Table.No_Element
      then
         return;
      end if;

      --  Making the new SF_Record
      New_SF_Record.Full_Source_Name :=
        new String'(Full_Source_Name_String.all);

      Set_SF_Record_Suffixless_Name (New_SF_Record);

      New_SF_Record.Status := Body_Reference;

      declare
         Unit_Name      : constant Optional_Name_Type :=
           Project_Tree.Root_Project.Visible_Source
             (GPR2.Path_Name.Create
                (GNATCOLL.VFS.Create (GNATCOLL.VFS."+" (Fname))))
             .Unit
             .Name;
         Unit           : constant GPR2.Build.Compilation_Unit.Object :=
           Unit_Name_To_Unit (String (Unit_Name));
         Stub_Unit_Name : constant Name_Type :=
           Name_Type (String (Unit_Name) & "." & Stub_Data_Unit_Name);

         P : GPR2.Project.View.Object := Unit.Owning_View;
      begin
         if Unit.Has_Part (S_Body) then
            New_SF_Record.Corresponding_Body :=
              new String'(Unit.Main_Body.Source.String_Value);
         end if;

         New_SF_Record.Stub_Data_Base_Spec :=
           new String'(String (P.Filename_For_Unit (Stub_Unit_Name, S_Spec)));
         New_SF_Record.Stub_Data_Base_Body :=
           new String'(String (P.Filename_For_Unit (Stub_Unit_Name, S_Body)));

         P := Outermost_Extending (P);

         New_SF_Record.Project_Name := new String'(String (P.Name));
         New_SF_Record.Unit_Name := new String'(String (Unit_Name));
      end;
      Insert (SF_Table, Full_Source_Name_String.all, New_SF_Record);

      Cleanup_Source_Name_Strings;
   end Add_Body_Reference;

   ----------------------------------
   -- Add_Body_For_Instrumentation --
   ----------------------------------

   procedure Add_Body_For_Instrumentation (Fname : String) is
      New_SF_Record : SF_Record;
   begin
      Trace (Me, "adding source for instrumentation: " & Fname);

      if not Is_Regular_File (Fname) then
         Report_Std ("gnattest: " & Fname & " not found");
         return;
      end if;

      Full_Source_Name_String :=
        new String'
          (Normalize_Pathname
             (Fname, Resolve_Links => False, Case_Sensitive => False));

      --  Making the new SF_Record
      New_SF_Record.Full_Source_Name :=
        new String'(Full_Source_Name_String.all);

      declare
         Given_File : constant GNATCOLL.VFS.Virtual_File := Create (+Fname);
         Src        : constant GPR2.Build.Source.Object :=
           Project_Tree.Root_Project.Visible_Source
             (GPR2.Path_Name.Create (Given_File));
         P          : constant GPR2.Project.View.Object := Src.Owning_View;
      begin
         New_SF_Record.Inst_Dir :=
           new String'
             (P.Object_Directory.String_Value
              & Dir_Sep
              & To_Lower (String (P.Name))
              & Instr_Suffix);
      end;
      Insert (SF_Table, Full_Source_Name_String.all, New_SF_Record);
      Free (Full_Source_Name_String);
   end Add_Body_For_Instrumentation;

   ----------------------
   --  SF_Table_Empty  --
   ----------------------

   function SF_Table_Empty return Boolean is
      Empty : constant Boolean := Is_Empty (SF_Table);
   begin
      return
        Empty or else (for all SF of SF_Table => SF.Status = To_Stub_Body);
   end SF_Table_Empty;

   ---------------------------
   -- Get_Imported_Projects --
   ---------------------------

   function Get_Imported_Projects
     (Project_Name : String) return List_Of_Strings.List is
   begin
      return Project_File_Table.Element (PF_Table, Project_Name).Imported_List;
   end Get_Imported_Projects;

   ----------------------------
   -- Get_Importing_Projects --
   ----------------------------

   function Get_Importing_Projects
     (Project_Name : String) return List_Of_Strings.List is
   begin
      return
        Project_File_Table.Element (PF_Table, Project_Name).Importing_List;
   end Get_Importing_Projects;

   ----------------------
   -- Get_Project_Path --
   ----------------------

   function Get_Project_Path (Project_Name : String) return String is
   begin
      return Project_File_Table.Element (PF_Table, Project_Name).Path.all;
   end Get_Project_Path;

   --------------------------
   -- Get_Project_Stub_Dir --
   --------------------------

   function Get_Project_Stub_Dir (Project_Name : String) return String is
   begin
      return Project_File_Table.Element (PF_Table, Project_Name).Stub_Dir.all;
   end Get_Project_Stub_Dir;

   ---------------------
   -- Get_Source_Body --
   ---------------------

   function Get_Source_Body (Source_Name : String) return String is
      SN  : constant String := Normalize_Source_Name (Source_Name);
      SFR : SF_Record;
   begin
      if Source_Present (SN) then
         SFR := Source_File_Table.Element (SF_Table, SN);
      else
         Report_Std
           ("warning: (gnattest) "
            & Source_Name
            & " is not a source of argument project, cannot create stub");

         return "";
      end if;

      if SFR.Corresponding_Body = null then
         return "";
      else
         return SFR.Corresponding_Body.all;
      end if;
   end Get_Source_Body;

   ---------------------------
   -- Get_Source_Instr_Body --
   ---------------------------

   function Get_Source_Instr_Body (Source_Name : String) return String is
      SN  : constant String := Normalize_Source_Name (Source_Name);
      SFR : SF_Record;
   begin
      SFR := Source_File_Table.Element (SF_Table, SN);

      if SFR.Theoretical_Body = null then
         return "";
      else
         return SFR.Theoretical_Body.all;
      end if;
   end Get_Source_Instr_Body;

   -----------------------------
   --  Get_Source_Output_Dir  --
   -----------------------------

   function Get_Source_Output_Dir (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
      SR : constant SF_Record := Source_File_Table.Element (SF_Table, SN);
   begin
      if SR.Test_Destination = null then
         return "";
      else
         return SR.Test_Destination.all;
      end if;
   end Get_Source_Output_Dir;

   ------------------------
   -- Get_Source_Project --
   ------------------------

   function Get_Source_Project_Name (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Project_Name.all;
   end Get_Source_Project_Name;

   --------------------------
   -- Get_Source_Unit_Name --
   --------------------------

   function Get_Source_Unit_Name (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Unit_Name.all;
   end Get_Source_Unit_Name;

   -------------------------
   -- Get_Source_Stub_Dir --
   -------------------------

   function Get_Source_Stub_Dir (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Stub_Destination.all;
   end Get_Source_Stub_Dir;

   -------------------------------
   -- Get_Source_Stub_Data_Body --
   -------------------------------

   function Get_Source_Stub_Data_Body (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Stub_Data_Base_Body.all;
   end Get_Source_Stub_Data_Body;

   -------------------------------
   -- Get_Source_Stub_Data_Spec --
   -------------------------------

   function Get_Source_Stub_Data_Spec (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Stub_Data_Base_Spec.all;
   end Get_Source_Stub_Data_Spec;

   -------------------------
   --  Get_Source_Status  --
   -------------------------
   function Get_Source_Status (Source_Name : String) return SF_Status is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Status;
   end Get_Source_Status;

   ----------------------------------
   --  Get_Source_Suffixless_Name  --
   ----------------------------------
   function Get_Source_Suffixless_Name (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Suffixless_Name.all;
   end Get_Source_Suffixless_Name;

   --------------------------
   -- Get_Source_Instr_Dir --
   --------------------------

   function Get_Source_Instr_Dir (Source_Name : String) return String is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Inst_Dir.all;
   end Get_Source_Instr_Dir;

   ------------------------------
   -- Initialize_Project_Table --
   ------------------------------

   procedure Initialize_Project_Table is
   begin
      Trace (Me, "Initialize_Project_Table");
      Increase_Indent (Me);
      for View of Project_Tree.Ordered_Views loop
         Trace (Me, "processing " & String (View.Name));

         --  Skip extended projects

         if View.Is_Extended then
            goto Next_Project;
         end if;

         declare
            PR : Project_Record;
         begin
            if View.Is_Externally_Built then
               PR.Is_Externally_Built := True;
               --  Nothing should be done for sources of externally built
               --  projects, so no point in calculating obj dirs and so on.
               goto Add_Project;
            end if;
            PR.Is_Externally_Built := False;
            PR.Aggregate_Lib := View.Kind = K_Aggregate_Library;
            PR.Is_Library := View.Kind in Library_Kind;

            if View.Is_Namespace_Root then
               PR.Needed_For_Extension := True;
            end if;

            PR.Path := new String'(View.Path_Name.String_Value);
            if Is_Absolute_Path (Stub_Dir_Name.all) then
               PR.Stub_Dir :=
                 new String'(Stub_Dir_Name.all & Dir_Sep & String (View.Name));
            elsif View.Kind in With_Object_Dir_Kind then
               PR.Stub_Dir :=
                 new String'
                   (Normalize_Pathname
                      (View.Object_Directory.String_Value
                       & Dir_Sep
                       & Stub_Dir_Name.all
                       & Dir_Sep
                       & String (View.Name),
                       Resolve_Links  => False,
                       Case_Sensitive => False));
            end if;

            Increase_Indent (Me, "imported projects:");

            --  Add the with-ed projects to the imported list

            for Withed_View of View.Imports loop
               PR.Imported_List.Append (String (Withed_View.Name));
            end loop;

            --  .. also add the aggregated projects to the imported list

            if View.Kind in Aggregate_Kind then
               for Aggr of View.Aggregated loop
                  PR.Imported_List.Append (String (Aggr.Name));
               end loop;
            end if;

            --  .. and the limited with-ed projects to both the imported list
            --  and the limited withed list.

            for Limited_Withed_View of View.Limited_Imports loop
               PR.Imported_List.Append (String (Limited_Withed_View.Name));
               PR.Limited_Withed.Include (String (Limited_Withed_View.Name));
            end loop;
            Decrease_Indent (Me);

            <<Add_Project>>
            PF_Table.Include (String (View.Name), PR);
         end;
         <<Next_Project>>
      end loop;

      --  Then, compute importing lists after each project has been inserted in
      --  the PF_Table.

      for View of Project_Tree.Ordered_Views loop
         if not View.Is_Extended and then not View.Is_Externally_Built then
            declare
               --  The set of importing projects consists of projects with-ing,
               --  limiting with-ing or aggregating this project.

               View_Cur    : constant Project_File_Table.Cursor :=
                 PF_Table.Find (String (View.Name));
               View_Entry  : constant Project_Record := Element (View_Cur);
               All_Imports : List_Of_Strings.List := View_Entry.Imported_List;
            begin
               Increase_Indent (Me, "importing projects:");
               for P of View_Entry.Limited_Withed loop
                  All_Imports.Append (P);
               end loop;

               for Import of All_Imports loop
                  PF_Table.Reference (PF_Table.Find (Import))
                    .Importing_List
                    .Append (String (View.Name));
               end loop;
               Decrease_Indent (Me);
            end;
         end if;
      end loop;

      Decrease_Indent (Me);
   end Initialize_Project_Table;

   ------------------------------------
   -- Get_Circular_Dependency_Chain --
   ------------------------------------

   function Get_Circular_Dependency_Chain return String is

      function Path_To
        (From : String; Target : String; Seen : in out String_Set.Set)
         return String;
      --  Following import edges (both regular and "limited with"), return a
      --  textual path "From -> ... -> Target", or the empty string if Target
      --  cannot be reached from From.

      -------------
      -- Path_To --
      -------------

      function Path_To
        (From : String; Target : String; Seen : in out String_Set.Set)
         return String
      is
         Cur : constant Project_File_Table.Cursor := PF_Table.Find (From);
      begin
         if From = Target then
            return Target;
         end if;

         --  Projects absent from the table (e.g. externally built ones) have
         --  no outgoing edges we know of.

         if not Has_Element (Cur) or else Seen.Contains (From) then
            return "";
         end if;

         Seen.Include (From);

         for Dep of Element (Cur).Imported_List loop
            declare
               Sub : constant String := Path_To (Dep, Target, Seen);
            begin
               if Sub /= "" then
                  return From & " -> " & Sub;
               end if;
            end;
         end loop;

         return "";
      end Path_To;

   begin
      --  A circular project dependency only breaks stub generation when the
      --  cycle goes through a regular "with": extending the importing project
      --  then drags in the original of an imported project that is itself
      --  extended, yielding an illegal "extends an already imported project".
      --  A cycle made exclusively of "limited with" edges is handled fine and
      --  must not be reported. We therefore look for a regular edge X -> Y
      --  whose target Y can reach X again, which closes such a cycle.

      for C in PF_Table.Iterate loop
         declare
            X : constant String := Key (C);
         begin
            for Y of Element (C).Imported_List loop
               if not Element (C).Limited_Withed.Contains (Y) then
                  declare
                     Seen : String_Set.Set;
                     Back : constant String := Path_To (Y, X, Seen);
                  begin
                     if Back /= "" then
                        return X & " -> " & Back;
                     end if;
                  end;
               end if;
            end loop;
         end;
      end loop;

      return "";
   end Get_Circular_Dependency_Chain;

   -------------
   -- Is_Body --
   -------------

   function Is_Body (Source_Name : String) return Boolean is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return
        Source_File_Table.Element (SF_Table, SN).Corresponding_Body = null;
   end Is_Body;

   ----------------------------------------
   -- Mark_Projects_With_Stubbed_Sources --
   ----------------------------------------

   procedure Mark_Projects_With_Stubbed_Sources is
      PR : Project_Record;

      Processed_Projects : String_Set.Set;

      procedure Process_Project (S : String);

      procedure Process_Project (S : String) is
         Local_PR : Project_Record;
      begin
         Trace (Me, "Process_Project " & S);
         if Processed_Projects.Contains (S) then
            return;
         end if;

         Processed_Projects.Include (S);

         if PF_Table.Element (S).Is_Externally_Built then
            --  Nothing to do for those.
            return;
         end if;

         Local_PR := PF_Table.Element (S);
         Local_PR.Needed_For_Extension := True;
         PF_Table.Replace (S, Local_PR);

         for P of Local_PR.Importing_List loop
            Process_Project (P);
         end loop;
      end Process_Project;

   begin
      Trace (Me, "Mark_Projects_With_Stubbed_Sources");
      Increase_Indent (Me);

      --  First, mark all projects that have sources that have been stubbed
      for SF of SF_Table loop
         if SF.Stub_Created then
            PR := PF_Table.Element (SF.Project_Name.all);
            PR.Needed_For_Extension := True;
            Trace (Me, SF.Project_Name.all & " has stubbed sources");
            PF_Table.Replace (SF.Project_Name.all, PR);
         end if;
      end loop;

      --  Now we need to also mark all projects that are imported by any
      --  of already marked ones.

      for P_Cur in PF_Table.Iterate loop
         if not Processed_Projects.Contains (Project_File_Table.Key (P_Cur))
           and then PF_Table.Constant_Reference (P_Cur).Needed_For_Extension
         then
            Process_Project (Project_File_Table.Key (P_Cur));
         end if;
      end loop;

      Decrease_Indent (Me);
   end Mark_Projects_With_Stubbed_Sources;

   -------------------------
   -- Mark_Sourse_Stubbed --
   -------------------------

   procedure Mark_Sourse_Stubbed (Source_Name : String) is
      procedure Set_Stub_Created (SF_Rec : in out SF_Record);
      --  Set Stub_Created flag to `True` in the source file record.

      ----------------------
      -- Set_Stub_Created --
      ----------------------

      procedure Set_Stub_Created (SF_Rec : in out SF_Record) is
      begin
         SF_Rec.Stub_Created := True;
      end Set_Stub_Created;
   begin
      Update_SF_Record (Source_Name, Set_Stub_Created'Access);
   end Mark_Sourse_Stubbed;

   ---------------------------------
   --  Next_Non_Processed_Source  --
   ---------------------------------

   function Next_Non_Processed_Source return String is
      Cur : Source_File_Table.Cursor := Source_File_Table.No_Element;
   begin
      Reset_Source_Process_Iterator;

      loop
         if Cur = Source_File_Table.No_Element
           and then Source_File_Table.Element (SF_Process_Iterator).Status
                    = Pending
         then
            Cur := SF_Process_Iterator;
         end if;
         if Source_File_Table.Element (SF_Process_Iterator).Status = Waiting
         then
            Free (Current_Source);
            Current_Source := new String'(Key (SF_Process_Iterator));
            return Key (SF_Process_Iterator);
         end if;

         Next (SF_Process_Iterator);
         exit when SF_Process_Iterator = Source_File_Table.No_Element;
      end loop;

      if Cur /= Source_File_Table.No_Element then
         Free (Current_Source);
         Current_Source := new String'(Key (Cur));
         return Key (Cur);
      end if;

      Free (Current_Source);
      return "";
   end Next_Non_Processed_Source;

   -----------------------------
   -- Get_Current_Source_Spec --
   -----------------------------

   function Get_Current_Source_Spec return String is
   begin
      if Current_Source = null then
         return "";
      else
         return Current_Source.all;
      end if;
   end Get_Current_Source_Spec;

   ----------------------------
   --  Next_Source_Location  --
   ----------------------------

   function Next_Source_Location return String is
      Cur : Source_File_Locations.Cursor;
   begin
      if SFL_Iterator /= Source_File_Locations.No_Element then
         Cur := SFL_Iterator;
         Source_File_Locations.Next (SFL_Iterator);
         return Source_File_Locations.Element (Cur);
      else
         return "";
      end if;
   end Next_Source_Location;

   ------------------------
   --  Next_Source_Name  --
   ------------------------

   function Next_Source_Name return String is
      Cur : Source_File_Table.Cursor;
   begin
      if SF_Access_Iterator /= Source_File_Table.No_Element then
         Cur := SF_Access_Iterator;
         Source_File_Table.Next (SF_Access_Iterator);
         return Key (Cur);
      else
         return "";
      end if;
   end Next_Source_Name;

   ----------------------
   -- Project_Extended --
   ----------------------

   function Project_Extended (Project_Name : String) return Boolean is
   begin
      return
        Project_File_Table.Element (PF_Table, Project_Name)
          .Needed_For_Extension;
   end Project_Extended;

   ------------------------
   -- Project_Is_Library --
   ------------------------

   function Project_Is_Library (Project_Name : String) return Boolean is
   begin
      return Project_File_Table.Element (PF_Table, Project_Name).Is_Library;
   end Project_Is_Library;

   -------------------------------
   --  Reset_Location_Iterator  --
   -------------------------------
   procedure Reset_Location_Iterator is
   begin
      SFL_Iterator := First (SFL_Table);
   end Reset_Location_Iterator;

   -----------------------------
   --  Reset_Source_Iterator  --
   -----------------------------
   procedure Reset_Source_Iterator is
   begin
      SF_Access_Iterator := First (SF_Table);
   end Reset_Source_Iterator;

   -------------------------------------
   --  Reset_Source_Process_Iterator  --
   -------------------------------------
   procedure Reset_Source_Process_Iterator is
   begin
      SF_Process_Iterator := First (SF_Table);
   end Reset_Source_Process_Iterator;

   -------------------------
   --  Set_Source_Status  --
   -------------------------

   procedure Set_Source_Status (Source_Name : String; New_Status : SF_Status)
   is
      procedure Set_Status (SF_Rec : in out SF_Record);
      --  Set the status to `New_Status` in the source file record.

      ------------------
      --  Set_Status  --
      ------------------

      procedure Set_Status (SF_Rec : in out SF_Record) is
      begin
         SF_Rec.Status := New_Status;
      end Set_Status;
   begin
      Update_SF_Record (Source_Name, Set_Status'Access);
   end Set_Source_Status;

   -------------------------
   --  Set_Subdir_Output  --
   -------------------------

   procedure Set_Subdir_Output is
      SF_Rec     : SF_Record;
      Tmp_Str    : String_Access;
      SF_Rec_Key : String_Access;
   begin
      Increase_Indent (Me, "Set_Subdir_Output");

      for Cur in SF_Table.Iterate loop
         SF_Rec := Source_File_Table.Element (Cur);
         SF_Rec_Key := new String'(Key (Cur));

         Trace (Me, "processing: " & SF_Rec_Key.all);

         Tmp_Str := new String'(Dir_Name (SF_Rec.Full_Source_Name.all));

         SF_Rec.Test_Destination :=
           new String'(Tmp_Str.all & Test_Subdir_Name.all & Dir_Sep);

         Replace (SF_Table, SF_Rec_Key.all, SF_Rec);
         Free (SF_Rec_Key);
         Free (Tmp_Str);
      end loop;

      Decrease_Indent (Me);

   end Set_Subdir_Output;

   -------------------------
   --  Set_Separate_Root  --
   -------------------------

   procedure Set_Separate_Root (Max_Common_Root : String) is
      SF_Rec     : SF_Record;
      Tmp_Str    : String_Access;
      SF_Rec_Key : String_Access;

      Idx : Integer;
   begin
      Increase_Indent (Me, "Set_Separate_Root");

      for Cur in SF_Table.Iterate loop
         SF_Rec := Source_File_Table.Element (Cur);
         SF_Rec_Key := new String'(Key (Cur));

         Trace (Me, "processing: " & SF_Rec_Key.all);

         Tmp_Str := new String'(Dir_Name (SF_Rec.Full_Source_Name.all));

         Idx := Max_Common_Root'Last + 1;

         SF_Rec.Test_Destination :=
           new String'
             (Separate_Root_Dir.all
              & Dir_Sep
              & Tmp_Str.all (Idx .. Tmp_Str.all'Last));

         Replace (SF_Table, SF_Rec_Key.all, SF_Rec);

         Free (SF_Rec_Key);
         Free (Tmp_Str);
      end loop;

      Decrease_Indent (Me);

   end Set_Separate_Root;

   -----------------------
   -- Set_Direct_Output --
   -----------------------

   procedure Set_Direct_Output is
      SF_Rec : SF_Record;

      View : GPR2.Project.View.Object;

      TD_Name : constant Virtual_File :=
        GNATCOLL.VFS.Create (+Test_Dir_Name.all);
   begin
      for Cur in SF_Table.Iterate loop
         SF_Rec := Source_File_Table.Element (Cur);

         if TD_Name.Is_Absolute_Path then
            SF_Rec.Test_Destination := new String'(Test_Dir_Name.all);
         else
            View := Get_GPR2_Owning_View_From_Name (SF_Rec.Full_Source_Name);
            SF_Rec.Test_Destination :=
              new String'
                (View.Object_Directory.String_Value
                 & Dir_Sep
                 & Test_Dir_Name.all);
         end if;

         Replace (SF_Table, Key (Cur), SF_Rec);
      end loop;
   end Set_Direct_Output;

   ----------------------------
   -- Set_Direct_Stub_Output --
   ----------------------------

   procedure Set_Direct_Stub_Output is
      SF_Rec : SF_Record;

      View : GPR2.Project.View.Object;

      TD_Name : constant Virtual_File :=
        GNATCOLL.VFS.Create (+Stub_Dir_Name.all);
   begin
      for Cur in SF_Table.Iterate loop
         SF_Rec := Source_File_Table.Element (Cur);

         View := Get_GPR2_Owning_View_From_Name (SF_Rec.Full_Source_Name);
         View := Outermost_Extending (View);

         --  Better use subdirs to separate stubs from different projects.

         if TD_Name.Is_Absolute_Path then
            SF_Rec.Stub_Destination :=
              new String'(Stub_Dir_Name.all & Dir_Sep & String (View.Name));
         else
            SF_Rec.Stub_Destination :=
              new String'
                (Normalize_Pathname
                   (View.Object_Directory.String_Value
                    & Dir_Sep
                    & Stub_Dir_Name.all
                    & Dir_Sep
                    & String (View.Name),
                    Resolve_Links  => False,
                    Case_Sensitive => False));
         end if;

         Replace (SF_Table, Source_File_Table.Key (Cur), SF_Rec);
      end loop;
   end Set_Direct_Stub_Output;

   --------------------
   -- Set_Output_Dir --
   --------------------

   procedure Set_Output_Dir (Source_Name : String; Output_Dir : String) is
      procedure Set_Destination (SF_Rec : in out SF_Record);
      --  Set destination to `Output_Dir` in the source file record.
      --  `Output_Dir` is copied and heap allocated.

      ---------------------
      -- Set_Destination --
      ---------------------

      procedure Set_Destination (SF_Rec : in out SF_Record) is
      begin
         SF_Rec.Test_Destination := new String'(Output_Dir);
      end Set_Destination;
   begin
      Trace (Me, "Set_Output_Dir for " & Source_Name);
      Update_SF_Record (Source_Name, Set_Destination'Access);
   end Set_Output_Dir;

   ----------------------
   --  Source_Present  --
   ----------------------

   function Source_Present (Source_Name : String) return Boolean is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Contains (SF_Table, SN);
   end Source_Present;

   --------------------
   -- Source_Stubbed --
   --------------------

   function Source_Stubbed (Source_Name : String) return Boolean is
      SN : constant String := Normalize_Source_Name (Source_Name);
   begin
      return Source_File_Table.Element (SF_Table, SN).Stub_Created;
   end Source_Stubbed;

   -------------------------------------
   -- Generate_Stub_Extension_Project --
   -------------------------------------

   procedure Generate_Stub_Extension_Project
     (Proj             : String;
      Current_Infix    : String;
      Subroot_Stub_Prj : String;
      Get_Sources      :
        access procedure
          (Proj : String; Current_Proj_Present_Sources : out String_Set.Set))
   is
      Processed_Projects : String_Set.Set := String_Set.Empty_Set;

      Current_Proj_Present_Sources : String_Set.Set := String_Set.Empty_Set;

      procedure Generate_Stub_Extension_Project_Aux (Proj : String);
      --  Recursive helper

      -----------------------------------------
      -- Generate_Stub_Extension_Project_Aux --
      -----------------------------------------

      procedure Generate_Stub_Extension_Project_Aux (Proj : String) is
         Arg_Proj : Project_Record;

         Relative_P_Path, Relative_I_Path : String_Access;

         Resolved_Dep_List : List_Of_Strings.List;
         --  List of relative paths to the stub project dependencies of Proj

         Sources_Names : String_Set.Set := String_Set.Empty_Set;
         --  Used to store the names of all sources of this project to be able
         --  to add those needed in the interface if the project is a library.
      begin
         if Processed_Projects.Contains (Proj) then
            return;
         end if;
         Processed_Projects.Include (Proj);
         Arg_Proj := PF_Table.Element (Proj);

         if Proj = Generate_Stub_Extension_Project.Proj then
            --  The root of the subtree is extended by the test driver project.
            goto Process_Imported;
         end if;

         if Arg_Proj.Needed_For_Extension then

            declare
               F : File_Array_Access;
            begin
               Append (F, GNATCOLL.VFS.Create (+(Arg_Proj.Stub_Dir.all)));
               Append
                 (F,
                  GNATCOLL.VFS.Create
                    (+(Arg_Proj.Stub_Dir.all
                       & Dir_Sep
                       & Unit_To_File_Name
                           (Stub_Project_Prefix & Current_Infix & Proj))));

               if Arg_Proj.Is_Library then
                  Append
                    (F,
                     GNATCOLL.VFS.Create
                       (+(Arg_Proj.Stub_Dir.all
                          & Dir_Sep
                          & Unit_To_File_Name
                              (Stub_Project_Prefix
                               & Current_Infix
                               & Proj
                               & "_lib"))));
               end if;
               Create_Dirs (F);
            end;

            Relative_P_Path :=
              new String'
                (+Relative_Path
                    (Create (+Arg_Proj.Path.all),
                     Create (+Arg_Proj.Stub_Dir.all)));

            Trace
              (Me,
               "Creating "
               & Arg_Proj.Stub_Dir.all
               & Dir_Sep
               & Unit_To_File_Name (Stub_Project_Prefix & Current_Infix & Proj)
               & ".gpr");
            Create
              (Arg_Proj.Stub_Dir.all
               & Dir_Sep
               & Unit_To_File_Name (Stub_Project_Prefix & Current_Infix & Proj)
               & ".gpr");

            --  Generate the list of stubbed projects on which Proj depends.
            --  If Proj is not an aggregate library project, the list will
            --  consist of
            --    [limited] with "rel/path/to/dep.gpr";
            --  otherwise the list will be the plain list of relative paths,
            --  with surrounding quotes.

            for P of Arg_Proj.Imported_List loop
               if PF_Table.Constant_Reference (P).Needed_For_Extension then
                  declare
                     Imported_Sub_Project : constant String :=
                       PF_Table.Constant_Reference (P).Stub_Dir.all
                       & Dir_Sep
                       & To_Lower (Stub_Project_Prefix & Current_Infix & P)
                       & ".gpr";
                  begin
                     if P = Generate_Stub_Extension_Project.Proj then
                        Relative_I_Path :=
                          new String'
                            (+Relative_Path
                                (Create (+Subroot_Stub_Prj),
                                 Create (+Arg_Proj.Stub_Dir.all)));
                     else
                        Relative_I_Path :=
                          new String'
                            (+Relative_Path
                                (Create (+Imported_Sub_Project),
                                 Create (+Arg_Proj.Stub_Dir.all)));
                     end if;
                  end;
                  if Arg_Proj.Aggregate_Lib then
                     Resolved_Dep_List.Append
                       ("""" & Relative_I_Path.all & """");

                  elsif Arg_Proj.Limited_Withed.Contains (P) then
                     Resolved_Dep_List.Append
                       ("limited with """ & Relative_I_Path.all & """;");
                  else
                     Resolved_Dep_List.Append
                       ("with """ & Relative_I_Path.all & """;");
                  end if;
               end if;
            end loop;

            --  Output the resolved dependency list in the non-aggregate
            --  library project case.

            if not Arg_Proj.Aggregate_Lib then
               for Str of Resolved_Dep_List loop
                  S_Put (0, Str);
                  Put_New_Line;
               end loop;
            end if;

            S_Put (0, "with ""aunit"";");
            Put_New_Line;
            Put_New_Line;

            if Arg_Proj.Aggregate_Lib then
               S_Put (0, "aggregate library ");
            end if;

            S_Put
              (0,
               "project "
               & Stub_Project_Prefix
               & Current_Infix
               & Proj
               & " extends """
               & Relative_P_Path.all
               & """ is");
            Put_New_Line;

            if not Arg_Proj.Aggregate_Lib then
               S_Put (3, "for Source_Dirs use (""."");");
               Put_New_Line;

               Get_Sources (Proj, Current_Proj_Present_Sources);

               if Current_Proj_Present_Sources.Is_Empty then
                  S_Put (3, "for Source_Files use ();");
                  Put_New_Line;
               else
                  S_Put (3, "for Source_Files use (");
                  Put_New_Line;
               end if;

               for Cur in Current_Proj_Present_Sources.Iterate loop
                  declare
                     Source         : constant String :=
                       Current_Proj_Present_Sources.Constant_Reference (Cur);
                     Stub_Data_Spec : constant String :=
                       Get_Source_Stub_Data_Spec (Source);
                     Stub_Data_Body : constant String :=
                       Get_Source_Stub_Data_Body (Source);
                  begin
                     if not Excluded_Test_Data_Files.Contains (Stub_Data_Spec)
                     then
                        S_Put (6, """" & Base_Name (Stub_Data_Spec) & """,");
                        Sources_Names.Include (Base_Name (Stub_Data_Spec));
                        Put_New_Line;
                     end if;

                     if not Excluded_Test_Data_Files.Contains (Stub_Data_Body)
                     then
                        S_Put (6, """" & Base_Name (Stub_Data_Body) & """,");
                        Sources_Names.Include (Base_Name (Stub_Data_Body));
                        Put_New_Line;
                     end if;

                     S_Put
                       (6, """" & Base_Name (Get_Source_Body (Source)) & """");
                     Sources_Names.Include (Base_Name (Source));

                     S_Put
                       (0,
                        (if Cur = Current_Proj_Present_Sources.Last
                         then ");"
                         else ","));
                     Put_New_Line;
                  end;
               end loop;
            end if;

            --  Add stubbed aggregated projects if this is an aggregate library
            --  project.

            if Arg_Proj.Aggregate_Lib then
               S_Put (3, "for Project_Files use (");
               Put_New_Line;
               for I_Cur in Resolved_Dep_List.Iterate loop
                  S_Put (6, Element (I_Cur));
                  if I_Cur = Resolved_Dep_List.Last then
                     S_Put (0, ");");
                  else
                     S_Put (0, ",");
                  end if;
                  Put_New_Line;
               end loop;
               Put_New_Line;
            end if;

            S_Put
              (3,
               "for Object_Dir use """
               & Unit_To_File_Name (Stub_Project_Prefix & Current_Infix & Proj)
               & """;");
            Put_New_Line;
            if Arg_Proj.Is_Library then
               S_Put
                 (3,
                  "for Library_Dir use """
                  & Unit_To_File_Name
                      (Stub_Project_Prefix & Current_Infix & Proj & "_lib")
                  & """;");
               Put_New_Line;
               S_Put
                 (3,
                  "for Library_Name use """
                  & Unit_To_File_Name
                      (Stub_Project_Prefix & Current_Infix & Proj)
                  & """;");
               Put_New_Line;

               Put_Interface_For_Project (Proj, Sources_Names);

            end if;
            Put_New_Line;

            if not Arg_Proj.Aggregate_Lib then
               if not Current_Proj_Present_Sources.Is_Empty then
                  S_Put (3, "package Coverage is");
                  Put_New_Line;
                  S_Put (6, "for Excluded_Units use (");
                  Put_New_Line;

                  for Cur in Current_Proj_Present_Sources.Iterate loop
                     S_Put
                       (9,
                        """"
                        & Get_Source_Unit_Name
                            (Get_Source_Body
                               (Current_Proj_Present_Sources.Constant_Reference
                                  (Cur)))
                        & """");
                     if Cur = Current_Proj_Present_Sources.Last then
                        S_Put (0, ");");
                     else
                        S_Put (0, ",");
                     end if;
                     Put_New_Line;
                  end loop;
                  S_Put (3, "end Coverage;");
                  Put_New_Line;
               end if;
            end if;

            S_Put
              (0, "end " & Stub_Project_Prefix & Current_Infix & Proj & ";");

            Close_File;
         end if;

         <<Process_Imported>>

         for P of Arg_Proj.Imported_List loop
            Generate_Stub_Extension_Project_Aux (P);
         end loop;
      end Generate_Stub_Extension_Project_Aux;

      --  Start of processing for Generate_Stub_Extension_Project
   begin
      Generate_Stub_Extension_Project_Aux (Proj);
   end Generate_Stub_Extension_Project;

   --------------------------------------
   -- Enforce_Custom_Project_Extension --
   --------------------------------------

   procedure Enforce_Custom_Project_Extension
     (File_Name            : String;
      Subroot_Stub_Prj     : String;
      Current_Source_Infix : String)
   is
      Short_Name : constant String := Base_Name (File_Name);

      Subroot_Prj_Name : constant String :=
        Get_Source_Project_Name (File_Name);

      procedure Set_Present_Subset_For_Project
        (Proj : String; Current_Proj_Present_Sources : out String_Set.Set);

      ------------------------------------
      -- Set_Present_Subset_For_Project --
      ------------------------------------

      procedure Set_Present_Subset_For_Project
        (Proj : String; Current_Proj_Present_Sources : out String_Set.Set) is
      begin
         Current_Proj_Present_Sources.Clear;

         for Cur in SF_Table.Iterate loop
            declare
               Key : constant String := Source_File_Table.Key (Cur);
            begin
               if SF_Table.Constant_Reference (Cur).Project_Name.all = Proj
                 and then not Is_Body (Key)
                 and then Source_Stubbed (Key)
                 and then Has_Stub (Base_Name (File_Name), Base_Name (Key))
               then
                  Current_Proj_Present_Sources.Include (Key);
               end if;
            end;
         end loop;
      end Set_Present_Subset_For_Project;

      --  Start of processing for Enforce_Custom_Project_Extension
   begin
      Trace
        (Me, "Creating extending project subtree for source " & Short_Name);

      if Me_Verbose.Is_Active then
         Trace (Me_Verbose, "Current infix is " & Current_Source_Infix);
         Trace (Me_Verbose, "Root of subtree is " & Subroot_Prj_Name);
         Decrease_Indent (Me_Verbose);
      end if;

      Generate_Stub_Extension_Project
        (Subroot_Prj_Name,
         Current_Source_Infix,
         Subroot_Stub_Prj,
         Set_Present_Subset_For_Project'Access);

   end Enforce_Custom_Project_Extension;

   -------------------------------
   -- Enforce_Project_Extension --
   -------------------------------

   procedure Enforce_Project_Extension
     (Prj_Name              : String;
      Subroot_Stub_Prj      : String;
      Current_Project_Infix : String)
   is
      procedure Set_Present_Subset_For_Project
        (Proj : String; Current_Proj_Present_Sources : out String_Set.Set);

      ------------------------------------
      -- Set_Present_Subset_For_Project --
      ------------------------------------

      procedure Set_Present_Subset_For_Project
        (Proj : String; Current_Proj_Present_Sources : out String_Set.Set) is
      begin
         Current_Proj_Present_Sources.Clear;

         for Cur in SF_Table.Iterate loop
            declare
               Key : constant String := Source_File_Table.Key (Cur);
            begin
               if SF_Table.Constant_Reference (Cur).Project_Name.all = Proj
                 and then not Is_Body (Key)
                 and then Source_Stubbed (Key)
                 and then Has_Stub (Base_Name (Key))
               then
                  Current_Proj_Present_Sources.Include (Key);
               end if;
            end;
         end loop;
      end Set_Present_Subset_For_Project;

      --  Start of processing for Enforce_Project_Extension
   begin
      Generate_Stub_Extension_Project
        (Prj_Name,
         Current_Project_Infix,
         Subroot_Stub_Prj,
         Set_Present_Subset_For_Project'Access);
   end Enforce_Project_Extension;

   -------------------------------
   -- Put_Interface_For_Project --
   -------------------------------

   procedure Put_Interface_For_Project
     (Project_Name : String; Source_List : String_Set.Set)
   is
      View : constant GPR2.Project.View.Object := View_For (Project_Name);
   begin
      if View.Has_Attribute (GPR2.Project.Registry.Attribute.Library_Interface)
        or else View.Has_Attribute (GPR2.Project.Registry.Attribute.Interfaces)
      then
         S_Put (3, "for Interfaces use (");

         --  Go through all files exposed in the interface and
         --  add them to the driver's interface.
         declare
            Exposed_List : constant GPR2.Project.Attribute.Object :=
              View.Attribute (GPR2.Project.Registry.Attribute.Interfaces);
         begin
            if Exposed_List.Is_Defined then
               for Source of Exposed_List.Values loop
                  S_Put (0, """" & String (Source.Text) & """,");
               end loop;
            end if;
         end;

         --  Do the same for the library interface attribute. The
         --  difference between the two is that Interfaces lists
         --  filenames, whereas the Library_Interface lists units,
         --  which we'll need to translate to spec filenames.

         declare
            Exposed_List : constant GPR2.Project.Attribute.Object :=
              View.Attribute
                (GPR2.Project.Registry.Attribute.Library_Interface);
         begin
            if Exposed_List.Is_Defined then
               for Unit of Exposed_List.Values loop
                  S_Put
                    (0,
                     """"
                     & String
                         (View.Filename_For_Unit
                            (Name_Type (Unit.Text), S_Spec))
                     & """,");
               end loop;
            end if;
         end;

         --  Include all sources in the interface

         if not Source_List.Is_Empty then
            for Cur in Source_List.Iterate loop
               S_Put (0, """" & String_Set.Element (Cur) & """");
               if Cur /= Source_List.Last then
                  S_Put (0, ",");
               end if;
            end loop;
         end if;
         S_Put (3, ");");
      end if;
   end Put_Interface_For_Project;

end Test.Skeleton.Source_Table;
