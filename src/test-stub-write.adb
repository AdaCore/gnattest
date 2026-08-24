with Ada.Directories;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with GNATCOLL.Traces; use GNATCOLL.Traces;
with GNATCOLL.VFS;    use GNATCOLL.VFS;

with GNAT.Directory_Operations; use GNAT.Directory_Operations;

with Libadalang.Common; use Libadalang.Common;

with Utils.Command_Lines; use Utils.Command_Lines;
with Utils.Environment;

with Test.Command_Lines;
with Test.Mapping; use Test.Mapping;

package body Test.Stub.Write is

   Me : constant Trace_Handle := Create ("Stubs.Write");

   Level        : Integer := 0;
   --  Nesting level of a spec being processed
   Indent_Level : constant Natural := 3;
   --  Indentation level

   procedure Put_Lines (MD : Markered_Data_Type; Comment_Out : Boolean);
   --  Print lines of MD to Output_File. If Comment_Out is True, force the
   --  lines to be commented out (prefixed with "--  ").

   procedure Put_Stub_Header
     (Unit_Name      : String;
      Stub_Data      : Boolean := True;
      Limited_Withed : String_Set.Set);
   --  Puts header of generated stub explaining where user code should be put

   procedure Put_Import_Section
     (Markered_Data        : in out Markered_Data_Maps.Map;
      Add_Import           : Boolean := False;
      Add_Language_Version : Boolean := False;
      Tasks_Present        : Boolean := False);
   --  Puts or regenerates markered section for with clauses
   --
   --  The included version is the one defined through the Ada_Version_Switch
   --  argument, if defined, or Ada_2012 otherwise.

   function Contains_Then_Emit
     (MD_Id : Markered_Data_Id; Map : in out MD_Map) return Boolean;
   --  Check if Markered_Data contains MD_Id. If True, emit the lines
   --  of the corresponding Markered_Data_Type, remove the entry from
   --  Map, and return True. Otherwise, do nothing and return False.

   procedure Process_Siblings (Cursor : Element_Node_Trees.Cursor);

   procedure Process_Node (Cursor : Element_Node_Trees.Cursor);

   procedure Generate_Package_Body
     (Node : Element_Node; Cursor : Element_Node_Trees.Cursor);

   procedure Generate_Protected_Body
     (Node : Element_Node; Cursor : Element_Node_Trees.Cursor);

   procedure Generate_Procedure_Body (Node : Element_Node);

   procedure Generate_Function_Body (Node : Element_Node);

   procedure Generate_Entry_Body (Node : Element_Node);

   procedure Generate_Task_Body (Node : Element_Node);

   procedure Generate_Full_Type_Declaration (Node : Element_Node);

   procedure Put_Dangling_Elements;

   ------------------------
   -- Generate_Body_Stub --
   ------------------------

   procedure Generate_Body_Stub (Body_File_Name : String; Data : Stubbing_Data)
   is

      Tmp_File_Name : constant String :=
        Ada.Directories.Compose
          (Utils.Environment.Tool_Temp_Dir.all, "gnattest_tmp_stub_body");
      Success       : Boolean;
   begin
      Trace (Me, "generating body of " & Body_File_Name);
      Increase_Indent (Me);

      Create (Tmp_File_Name);
      Reset_Line_Counter;

      Put_Stub_Header
        (Element_Node_Trees.Element (First_Child (Data.Elem_Tree.Root))
           .Spec_Name.all,
         not Data.Flat_List.Is_Empty,
         Data.Limited_Withed_Units);
      Put_Import_Section
        (Markered_Data,
         Add_Import    => True,
         Tasks_Present => Data.Tasks_Present);

      Process_Siblings (First_Child (Data.Elem_Tree.Root));

      Close_File;

      declare
         F : File_Array_Access;
      begin
         Append (F, Dir (GNATCOLL.VFS.Create (+(Body_File_Name))));
         Create_Dirs (F);
      end;

      --  At this point temp package is coplete and it is safe
      --  to replace the old one with it.
      if Is_Regular_File (Body_File_Name) then
         Delete_File (Body_File_Name, Success);
         if not Success then
            Cmd_Error_No_Help ("cannot delete " & Body_File_Name);
         end if;
      end if;
      Copy_File (Tmp_File_Name, Body_File_Name, Success);
      if not Success then
         Cmd_Error_No_Help
           ("cannot copy tmp test package to " & Body_File_Name);
      end if;
      Delete_File (Tmp_File_Name, Success);
      if not Success then
         Cmd_Error_No_Help ("cannot delete tmp test package");
      end if;
      Decrease_Indent (Me);
   end Generate_Body_Stub;

   ------------------------
   -- Generate_Stub_Data --
   ------------------------

   procedure Generate_Stub_Data
     (Stub_Data_File_Spec : String;
      Stub_Data_File_Body : String;
      Data                : Stubbing_Data)
   is
      Root_Node : constant Element_Node :=
        Element_Node_Trees.Element (First_Child (Data.Elem_Tree.Root));

      Tmp_File_Name : constant String :=
        Ada.Directories.Compose
          (Utils.Environment.Tool_Temp_Dir.all, "gnattest_tmp_stub_body");
      Success       : Boolean;

      ID : Markered_Data_Id;
      MD : Markered_Data_Type;

      Markered_Subp_Data : MD_Map;

   begin
      --  Spec
      Gather_Markered_Data (Stub_Data_File_Spec, Markered_Subp_Data);
      Trace
        (Me,
         "generating stub data spec for "
         & Root_Node.Spec_Name.all
         & "."
         & Stub_Data_Unit_Name);
      Increase_Indent (Me);
      Create (Tmp_File_Name);
      Reset_Line_Counter;

      Put_Import_Section (Markered_Subp_Data, Add_Language_Version => True);

      S_Put
        (0,
         "package "
         & Root_Node.Spec_Name.all
         & "."
         & Stub_Data_Unit_Name
         & " is");
      New_Line_Count;

      for E of Dictionary loop
         S_Put (3, E.Entry_Str.all);
         New_Line_Count;
      end loop;

      New_Line_Count;

      for Node of Data.Flat_List loop
         S_Put (0, GT_Marker_Begin);
         New_Line_Count;
         S_Put (3, Generate_MD_Id_String (Node.Spec));
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;

         ID := Generate_MD_Id (Node.Spec);
         if not Contains_Then_Emit (ID, Markered_Subp_Data) then
            Generate_Default_Setter_Spec (Node);
         end if;

         S_Put (0, GT_Marker_Begin);
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;
         New_Line_Count;
      end loop;

      if not Markered_Subp_Data.Is_Empty then

         Report_Std
           (" warning: (gnattest) "
            & Root_Node.Spec_Name.all
            & "."
            & Stub_Data_Unit_Name
            & " has dangling setter spec(s)");

         S_Put (3, "----------------------");
         New_Line_Count;
         S_Put (3, "--  Unused Setters  --");
         New_Line_Count;
         S_Put (3, "----------------------");
         New_Line_Count;
         New_Line_Count;

         for MD_Cur in Markered_Subp_Data.Iterate loop

            ID := Markered_Data_Maps.Key (MD_Cur);
            MD := Markered_Subp_Data.Constant_Reference (MD_Cur);

            S_Put (0, GT_Marker_Begin);
            New_Line_Count;
            S_Put (3, Generate_MD_Id_String (ID));
            New_Line_Count;
            S_Put (0, GT_Marker_End);
            New_Line_Count;

            Put_Lines (MD, Comment_Out => True);

            S_Put (0, GT_Marker_Begin);
            New_Line_Count;
            S_Put (0, GT_Marker_End);
            New_Line_Count;
            New_Line_Count;
         end loop;

      end if;

      S_Put
        (0,
         "end " & Root_Node.Spec_Name.all & "." & Stub_Data_Unit_Name & ";");
      New_Line_Count;

      Close_File;
      Markered_Subp_Data.Clear;

      --  At this point temp package is coplete and it is safe
      --  to replace the old one with it.
      if Is_Regular_File (Stub_Data_File_Spec) then
         Delete_File (Stub_Data_File_Spec, Success);
         if not Success then
            Cmd_Error_No_Help ("cannot delete " & Stub_Data_File_Spec);
         end if;
      end if;
      Copy_File (Tmp_File_Name, Stub_Data_File_Spec, Success);
      if not Success then
         Cmd_Error_No_Help
           ("cannot copy tmp test package to " & Stub_Data_File_Spec);
      end if;
      Delete_File (Tmp_File_Name, Success);
      if not Success then
         Cmd_Error_No_Help ("cannot delete tmp test package");
      end if;
      Decrease_Indent (Me);

      --  Body
      Gather_Markered_Data (Stub_Data_File_Body, Markered_Subp_Data);
      Trace
        (Me,
         "generating stub data body for "
         & Root_Node.Spec_Name.all
         & "."
         & Stub_Data_Unit_Name);
      Increase_Indent (Me);
      Create (Tmp_File_Name);
      Reset_Line_Counter;

      Put_Import_Section (Markered_Subp_Data);

      S_Put
        (0,
         "package body "
         & Root_Node.Spec_Name.all
         & "."
         & Stub_Data_Unit_Name
         & " is");
      New_Line_Count;

      for Node of Data.Flat_List loop
         S_Put (0, GT_Marker_Begin);
         New_Line_Count;
         S_Put (3, Generate_MD_Id_String (Node.Spec));
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;

         Update_Local_Entity_With_Setter (Node, New_Line_Counter, 4);

         ID := Generate_MD_Id (Node.Spec);
         if not Contains_Then_Emit (ID, Markered_Subp_Data) then
            Generate_Default_Setter_Body (Node);
         end if;

         S_Put (0, GT_Marker_Begin);
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;
         New_Line_Count;
      end loop;

      if not Markered_Subp_Data.Is_Empty then

         Report_Std
           (" warning: (gnattest) "
            & Root_Node.Spec_Name.all
            & "."
            & Stub_Data_Unit_Name
            & " has dangling setter body(ies)");

         S_Put (3, "----------------------");
         New_Line_Count;
         S_Put (3, "--  Unused Setters  --");
         New_Line_Count;
         S_Put (3, "----------------------");
         New_Line_Count;
         New_Line_Count;

         for MD_Cur in Markered_Subp_Data.Iterate loop

            ID := Markered_Data_Maps.Key (MD_Cur);
            MD := Markered_Subp_Data.Constant_Reference (MD_Cur);

            S_Put (0, GT_Marker_Begin);
            New_Line_Count;
            Local_Stub_Unit_Mapping.D_Setters.Append ((New_Line_Counter, 0));
            S_Put (3, Generate_MD_Id_String (ID));
            New_Line_Count;
            S_Put (0, GT_Marker_End);
            New_Line_Count;

            Put_Lines (MD, Comment_Out => True);

            S_Put (0, GT_Marker_Begin);
            New_Line_Count;
            S_Put (0, GT_Marker_End);
            New_Line_Count;
            New_Line_Count;
         end loop;

      end if;

      S_Put
        (0,
         "end " & Root_Node.Spec_Name.all & "." & Stub_Data_Unit_Name & ";");
      New_Line_Count;

      Close_File;

      --  At this point temp package is coplete and it is safe
      --  to replace the old one with it.
      if Is_Regular_File (Stub_Data_File_Body) then
         Delete_File (Stub_Data_File_Body, Success);
         if not Success then
            Cmd_Error_No_Help ("cannot delete " & Stub_Data_File_Body);
         end if;
      end if;
      Copy_File (Tmp_File_Name, Stub_Data_File_Body, Success);
      if not Success then
         Cmd_Error_No_Help
           ("cannot copy tmp test package to " & Stub_Data_File_Body);
      end if;
      Delete_File (Tmp_File_Name, Success);
      if not Success then
         Cmd_Error_No_Help ("cannot delete tmp test package");
      end if;
      Decrease_Indent (Me);

   end Generate_Stub_Data;

   ---------------
   -- Put_Lines --
   ---------------

   procedure Put_Lines (MD : Markered_Data_Type; Comment_Out : Boolean) is

      function Comment_Line (S : String) return String
      is ("--  " & S);
      function Uncomment_Line (S : String) return String;

      --------------------
      -- Uncomment_Line --
      --------------------

      function Uncomment_Line (S : String) return String is
      begin
         if S = "--  " then
            return "";
         end if;

         if S'Length < 5 then
            return S;
         end if;

         if S (S'First .. S'First + 3) = "--  " then
            return S (S'First + 4 .. S'Last);
         end if;

         return S;
      end Uncomment_Line;

   begin

      if MD.Commented_Out = Comment_Out then
         for I in MD.Lines.First_Index .. MD.Lines.Last_Index loop
            S_Put (0, MD.Lines.Element (I));
            New_Line_Count;
         end loop;
      else
         if Comment_Out then
            for I in MD.Lines.First_Index .. MD.Lines.Last_Index loop
               S_Put (0, Comment_Line (MD.Lines.Element (I)));
               New_Line_Count;
            end loop;
         else
            for I in MD.Lines.First_Index .. MD.Lines.Last_Index loop
               S_Put (0, Uncomment_Line (MD.Lines.Element (I)));
               New_Line_Count;
            end loop;
         end if;
      end if;

   end Put_Lines;

   ---------------------
   -- Put_Stub_Header --
   ---------------------

   procedure Put_Stub_Header
     (Unit_Name      : String;
      Stub_Data      : Boolean := True;
      Limited_Withed : String_Set.Set)
   is
      use String_Set;
   begin
      S_Put
        (0, "--  This package has been generated automatically by GNATtest.");
      New_Line_Count;
      S_Put
        (0,
         "--  You are allowed to add your code to designated areas between"
         & " read-only");
      New_Line_Count;
      S_Put
        (0,
         "--  sections. Such changes will be kept during further regeneration"
         & " of this");
      New_Line_Count;
      S_Put
        (0,
         "--  file. All code placed outside of such areas will be lost"
         & " during");
      New_Line_Count;
      S_Put (0, "--  regeneration of this package.");
      New_Line_Count;
      New_Line_Count;
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      if Stub_Data then
         S_Put
           (0,
            "with "
            & Unit_Name
            & "."
            & Stub_Data_Unit_Name
            & "; use "
            & Unit_Name
            & "."
            & Stub_Data_Unit_Name
            & ";");
      end if;
      New_Line_Count;

      --  We need to put a regular with into the body for every limited with
      --  from the spec.

      for LW of Limited_Withed loop
         S_Put (0, "with " & LW & ";");
         New_Line_Count;
      end loop;

      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;
   end Put_Stub_Header;

   ------------------------
   -- Put_Import_Section --
   ------------------------

   procedure Put_Import_Section
     (Markered_Data        : in out Markered_Data_Maps.Map;
      Add_Import           : Boolean := False;
      Add_Language_Version : Boolean := False;
      Tasks_Present        : Boolean := False)
   is
      use Test.Command_Lines;

      ID : constant Markered_Data_Id :=
        (Import_MD,
         new String'(""),
         new String'(""),
         new String'(Hash_Version),
         new String'(""));
      MD : Markered_Data_Type;
   begin
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put
        (0,
         "--  id:" & Hash_Version & "/" & MD_Kind_To_String (Import_MD) & "/");
      --  No need for hashes here

      New_Line_Count;
      S_Put (0, "--");
      New_Line_Count;
      S_Put
        (0, "--  This section can be used to add with clauses if necessary.");
      New_Line_Count;
      S_Put (0, "--");
      New_Line_Count;
      S_Put (0, GT_Marker_End);

      New_Line_Count;

      if Markered_Data.Contains (ID) then
         --  Extract importing MD
         MD := Markered_Data.Element (ID);
         Put_Lines (MD, Comment_Out => False);
         Markered_Data.Delete (ID);
      else
         New_Line_Count;
         if Add_Import and then Tasks_Present then
            S_Put (3, "with Ada.Real_Time;");
            New_Line_Count;
         end if;
         if Add_Language_Version then
            S_Put
              (0,
               "pragma "
               & (case Test.Common.Lang_Version is
                    when Ada_83   => "Ada_83",
                    when Ada_95   => "Ada_95",
                    when Ada_2005 => "Ada_2005",
                    when Ada_2012 => "Ada_2012",
                    when Ada_2022 => "Ada_2022")
               & ";");
            New_Line_Count;
         end if;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

   end Put_Import_Section;

   function Contains_Then_Emit
     (MD_Id : Markered_Data_Id; Map : in out MD_Map) return Boolean
   is
      MD : Markered_Data_Type;
   begin
      if Map.Contains (MD_Id) then
         MD := Map.Element (MD_Id);
         Put_Lines (MD, Comment_Out => False);
         Map.Delete (MD_Id);
         return True;
      end if;
      return False;
   end Contains_Then_Emit;

   ----------------------
   -- Process_Siblings --
   ----------------------

   procedure Process_Siblings (Cursor : Element_Node_Trees.Cursor) is
      Cur : Element_Node_Trees.Cursor := Cursor;
   begin
      while Cur /= Element_Node_Trees.No_Element loop
         Process_Node (Cur);
         Next_Sibling (Cur);
      end loop;
   end Process_Siblings;

   ------------------
   -- Process_Node --
   ------------------

   procedure Process_Node (Cursor : Element_Node_Trees.Cursor) is
      Node      : constant Element_Node := Element_Node_Trees.Element (Cursor);
      Node_Kind : constant Ada_Node_Kind_Type := Node.Spec.Kind;
   begin

      case Node_Kind is
         when Ada_Package_Decl | Ada_Generic_Package_Decl                =>
            Generate_Package_Body (Node, Cursor);

         when Ada_Subp_Decl                                              =>
            if Node
                 .Spec
                 .As_Basic_Subp_Decl
                 .P_Subp_Decl_Spec
                 .As_Subp_Spec
                 .F_Subp_Kind
              = Ada_Subp_Kind_Function
            then
               Generate_Function_Body (Node);
            else
               Generate_Procedure_Body (Node);
            end if;

         when Ada_Generic_Subp_Decl                                      =>
            if Node
                 .Spec
                 .As_Generic_Subp_Decl
                 .F_Subp_Decl
                 .As_Basic_Subp_Decl
                 .P_Subp_Decl_Spec
                 .As_Subp_Spec
                 .F_Subp_Kind
              = Ada_Subp_Kind_Function
            then
               Generate_Function_Body (Node);
            else
               Generate_Procedure_Body (Node);
            end if;

         when Ada_Entry_Decl                                             =>
            Generate_Entry_Body (Node);

         when Ada_Single_Protected_Decl | Ada_Protected_Type_Decl        =>
            Generate_Protected_Body (Node, Cursor);

         when Ada_Single_Task_Decl | Ada_Task_Type_Decl                  =>
            Generate_Task_Body (Node);

         when Ada_Incomplete_Type_Decl | Ada_Incomplete_Tagged_Type_Decl =>
            Generate_Full_Type_Declaration (Node);

         when others                                                     =>
            null;
      end case;
   end Process_Node;

   ---------------------------
   -- Generate_Package_Body --
   ---------------------------

   procedure Generate_Package_Body
     (Node : Element_Node; Cursor : Element_Node_Trees.Cursor)
   is
      Cur : constant Element_Node_Trees.Cursor := Cursor;
      ID  : Markered_Data_Id := Generate_MD_Id (Node.Spec);
   begin
      if Is_Leaf (Cur) and then not Is_Root (Parent (Cur)) then
         --  Nothing to worry about
         return;
      end if;

      Trace (Me, "Generating package body for " & Node.Spec_Name.all);

      --  Put local declaration section
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      S_Put (Level * Indent_Level, "package body " & Node.Spec_Name.all);
      New_Line_Count;

      Level := Level + 1;
      S_Put ((Level) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level) * Indent_Level,
         "--  This section can be used for local declarations.");
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put bodies

      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put ((Level - 1) * Indent_Level, "is");
         New_Line_Count;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

      if not Is_Leaf (Cur) then
         Process_Siblings (First_Child (Cur));
      end if;

      --  Put possible Elab sections
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      ID.Kind := Elaboration_MD;
      S_Put ((Level) * Indent_Level, Generate_MD_Id_String (ID));
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        (Level * Indent_Level,
         "--  This section can be used for elaboration statements.");
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;

      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
      end if;

      --  Put end package
      Level := Level - 1;
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put (Level * Indent_Level, "end " & Node.Spec_Name.all & ";");
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

      --  If we are in the root package, we have to print all the dangling
      --  elements (if any).
      if Is_Root (Parent (Cur)) then
         if not Markered_Data.Is_Empty then
            Report_Std
              (" warning: (gnattest) "
               & Node.Spec_Name.all
               & " has dangling element(s)");

            Put_Dangling_Elements;
         end if;
      end if;

   end Generate_Package_Body;

   -----------------------------
   -- Generate_Protected_Body --
   -----------------------------

   procedure Generate_Protected_Body
     (Node : Element_Node; Cursor : Element_Node_Trees.Cursor)
   is
      Cur : constant Element_Node_Trees.Cursor := Cursor;
   begin
      Trace (Me, "Generating protected body for " & Node.Spec_Name.all);

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      S_Put
        (Level * Indent_Level, "protected body " & Node.Spec_Name.all & " is");
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

      Level := Level + 1;
      if not Is_Leaf (Cur) then
         Process_Siblings (First_Child (Cur));
      end if;

      Level := Level - 1;
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put (Level * Indent_Level, "end " & Node.Spec_Name.all & ";");
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

   end Generate_Protected_Body;

   -----------------------------
   -- Generate_Procedure_Body --
   -----------------------------

   procedure Generate_Procedure_Body (Node : Element_Node) is
      ID : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);

      Arg_Kind   : constant Ada_Node_Kind_Type := Node.Spec.Kind;
      Spec       : constant Base_Subp_Spec'Class :=
        (if Arg_Kind = Ada_Generic_Subp_Decl
         then Node.Spec.As_Generic_Subp_Decl.F_Subp_Decl.P_Subp_Decl_Spec
         else Node.Spec.As_Basic_Subp_Decl.P_Subp_Decl_Spec);
      Parameters : constant Param_Spec_Array := Spec.P_Params;

      Param_List : constant Stubbed_Parameter_Lists.List :=
        Get_Args_List (Node);

      Suffix : constant String := Hash_Suffix (ID);

      Not_Empty_Stub : constant Boolean :=
        Arg_Kind = Ada_Subp_Decl
        and then  --  Not generic
        not Node.Inside_Generic
        and then not Node.Inside_Protected;

      Has_Limited_Params      : Boolean := False;
      Has_Limited_View_Params : Boolean := False;
      Has_Private_Params      : Boolean := False;
   begin
      Trace (Me, "Generating procedure body for " & Node.Spec_Name.all);
      Increase_Indent (Me);
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      if Arg_Kind = Ada_Subp_Decl then
         case Node.Spec.As_Classic_Subp_Decl.F_Overriding.Kind is
            when Ada_Overriding_Overriding     =>
               S_Put (Level * Indent_Level, "overriding");
               New_Line_Count;

            when Ada_Overriding_Not_Overriding =>
               S_Put (Level * Indent_Level, "not overriding");
               New_Line_Count;

            when others                        =>
               null;
         end case;
      end if;

      S_Put (Level * Indent_Level, "procedure " & Node.Spec_Name.all);

      if Parameters'Length = 0 then
         S_Put (0, " is");
         New_Line_Count;
      else
         New_Line_Count;
         S_Put (Level * Indent_Level + 2, "(");

         for I in Parameters'Range loop
            if I = Parameters'First then
               S_Put (0, Node_Image (Parameters (I)));
            else
               S_Put ((Level + 1) * Indent_Level, Node_Image (Parameters (I)));
            end if;

            if I = Parameters'Last then
               S_Put (0, ") is");
            else
               S_Put (0, ";");
            end if;
            New_Line_Count;
         end loop;
      end if;

      S_Put ((Level + 1) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level + 1) * Indent_Level,
         "--  This section can be used to change the procedure body.");
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put body
      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put ((Level) * Indent_Level, "begin");
         New_Line_Count;
         if Not_Empty_Stub then
            New_Line_Count;
            S_Put
              (6,
               Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & Stub_Counter_Var
               & " := "
               & Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & Stub_Counter_Var
               & " + 1;");
            New_Line_Count;
            if not Param_List.Is_Empty then
               for SP of Param_List loop
                  if Is_Only_Limited_Withed (SP.Type_Elem.As_Type_Expr) then
                     Has_Limited_View_Params := True;
                  elsif Is_Limited (SP.Type_Elem.As_Type_Expr) then
                     Has_Limited_Params := True;
                  elsif Is_Fully_Private (SP.Type_Elem.As_Type_Expr) then
                     Has_Private_Params := True;
                  else

                     case SP.Kind is
                        when Constrained     =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & " := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ";");

                        when Not_Constrained =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & " := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ".all;");

                        when Access_Kind     =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & ".all := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ".all;");
                     end case;

                     New_Line_Count;

                  end if;
               end loop;
            end if;
         else
            S_Put ((Level + 1) * Indent_Level, "pragma Compile_Time_Warning");
            New_Line_Count;
            S_Put ((Level + 1) * Indent_Level + 2, "(Standard.True,");
            New_Line_Count;
            S_Put
              ((Level + 2) * Indent_Level,
               """Stub for " & Node.Spec_Name.all & " is unimplemented,""");
            New_Line_Count;
            S_Put
              ((Level + 2) * Indent_Level,
               "& "" this might affect some tests"");");
            New_Line_Count;
            S_Put ((Level + 1) * Indent_Level, "null;");
            New_Line_Count;
         end if;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "end " & Node.Spec_Name.all & ";");
      New_Line_Count;
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

      if Has_Limited_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has limited type parameter, generated setter is incomplete");
      end if;

      if Has_Limited_View_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has parameter of a limited view type, "
            & "generated setter is incomplete");
      end if;

      if Has_Private_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has private type parameter, generated setter is incomplete");
      end if;

      Decrease_Indent (Me);

   end Generate_Procedure_Body;

   ----------------------------
   -- Generate_Function_Body --
   ----------------------------

   procedure Generate_Function_Body (Node : Element_Node) is
      ID : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);

      Arg_Kind : constant Ada_Node_Kind_Type := Node.Spec.Kind;

      Spec : constant Base_Subp_Spec'Class :=
        (if Arg_Kind = Ada_Generic_Subp_Decl
         then Node.Spec.As_Generic_Subp_Decl.F_Subp_Decl.P_Subp_Decl_Spec
         else Node.Spec.As_Basic_Subp_Decl.P_Subp_Decl_Spec);

      Parameters  : constant Param_Spec_Array := Spec.P_Params;
      Res_Profile : constant Type_Expr := Spec.As_Subp_Spec.F_Subp_Returns;

      Param_List : constant Stubbed_Parameter_Lists.List :=
        Get_Args_List (Node);

      SP : Stubbed_Parameter;

      Suffix : constant String := Hash_Suffix (ID);

      Not_Empty_Stub : constant Boolean :=
        Arg_Kind = Ada_Subp_Decl
        and then  --  Not generic
        not Node.Inside_Generic
        and then not Node.Inside_Protected;

      Has_Limited_Params      : Boolean := False;
      Has_Limited_View_Params : Boolean := False;
      Has_Private_Params      : Boolean := False;

      procedure Output_Fake_Parameters;
      --  Prints out the fake parameters of the fake recursive call of the
      --  function to itself.

      procedure Output_Fake_Parameters is
         Idx : Positive;
      begin
         S_Put (0, " (");

         for J in Parameters'Range loop

            declare
               Formal_Names : constant Defining_Name_List :=
                 F_Ids (Parameters (J));
            begin
               Idx := Formal_Names.Defining_Name_List_First;

               loop
                  S_Put
                    (0,
                     Node_Image (Formal_Names.Defining_Name_List_Element (Idx))
                     & " => "
                     & Node_Image
                         (Formal_Names.Defining_Name_List_Element (Idx)));
                  Idx := Formal_Names.Defining_Name_List_Next (Idx);
                  if Formal_Names.Defining_Name_List_Has_Element (Idx)
                    or else J /= Parameters'Last
                  then
                     S_Put (0, ", ");
                  end if;

                  exit when
                    not Formal_Names.Defining_Name_List_Has_Element (Idx);
               end loop;

            end;

         end loop;

         S_Put (0, ");");

      end Output_Fake_Parameters;
   begin
      Trace (Me, "Generating function body for " & Node.Spec_Name.all);
      Increase_Indent (Me);
      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      if Arg_Kind = Ada_Subp_Decl then
         case Node.Spec.As_Classic_Subp_Decl.F_Overriding.Kind is
            when Ada_Overriding_Overriding     =>
               S_Put (Level * Indent_Level, "overriding");
               New_Line_Count;

            when Ada_Overriding_Not_Overriding =>
               S_Put (Level * Indent_Level, "not overriding");
               New_Line_Count;

            when others                        =>
               null;
         end case;
      end if;

      S_Put
        (Level * Indent_Level,
         "function " & Node_Image (Node.Spec.As_Basic_Decl.P_Defining_Name));

      if Parameters'Length = 0 then
         S_Put (0, " return " & Node_Image (Res_Profile) & " is");
         New_Line_Count;
      else
         New_Line_Count;
         S_Put (Level * Indent_Level + 2, "(");

         for I in Parameters'Range loop
            if I = Parameters'First then
               S_Put (0, Node_Image (Parameters (I)));
            else
               S_Put ((Level + 1) * Indent_Level, Node_Image (Parameters (I)));
            end if;

            if I = Parameters'Last then
               S_Put (0, ") return " & Node_Image (Res_Profile) & " is");
            else
               S_Put (0, ";");
            end if;
            New_Line_Count;
         end loop;
      end if;

      S_Put ((Level + 1) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level + 1) * Indent_Level,
         "--  This section can be used to change the function body.");
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put body
      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put ((Level) * Indent_Level, "begin");
         New_Line_Count;
         if Not_Empty_Stub then
            New_Line_Count;
            S_Put
              (6,
               Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & Stub_Counter_Var
               & " := "
               & Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & Stub_Counter_Var
               & " + 1;");
            New_Line_Count;

            if not Param_List.Is_Empty then
               for Cur in Param_List.Iterate loop
                  exit when Cur = Param_List.Last;
                  SP := Param_List.Constant_Reference (Cur);
                  if Is_Only_Limited_Withed (SP.Type_Elem.As_Type_Expr) then
                     Has_Limited_View_Params := True;
                  elsif Is_Limited (SP.Type_Elem.As_Type_Expr) then
                     Has_Limited_Params := True;
                  elsif Is_Fully_Private (SP.Type_Elem.As_Type_Expr) then
                     Has_Private_Params := True;
                  else

                     case SP.Kind is
                        when Constrained     =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & " := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ";");

                        when Not_Constrained =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & " := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ".all;");

                        when Access_Kind     =>
                           S_Put
                             ((Level + 1) * Indent_Level,
                              SP.Name.all
                              & ".all := "
                              & Stub_Data_Unit_Name
                              & "."
                              & Stub_Object_Prefix
                              & Node.Spec_Name.all
                              & Suffix
                              & "."
                              & SP.Name.all
                              & ".all;");
                     end case;

                     New_Line_Count;

                  end if;
               end loop;
            end if;

            --  Processing result profile
            SP := Param_List.Last_Element;

            if Is_Only_Limited_Withed (SP.Type_Elem.As_Type_Expr)
              or else Is_Abstract (SP.Type_Elem.As_Type_Expr)
              or else Is_Limited (SP.Type_Elem.As_Type_Expr)
              or else Is_Fully_Private (SP.Type_Elem.As_Type_Expr)
              or else Is_Anon_Access_To_Subp (SP.Type_Elem.As_Type_Expr)
            then
               S_Put
                 ((Level + 1) * Indent_Level, "pragma Compile_Time_Warning");
               New_Line_Count;
               S_Put ((Level + 1) * Indent_Level + 2, "(Standard.True,");
               New_Line_Count;
               S_Put
                 ((Level + 2) * Indent_Level,
                  """Stub for " & Node.Spec_Name.all & " is unimplemented,""");
               New_Line_Count;
               S_Put
                 ((Level + 2) * Indent_Level,
                  "& "" this might affect some tests"");");
               New_Line_Count;
               S_Put
                 ((Level + 1) * Indent_Level,
                  "raise Program_Error with ""Unimplemented stub for function "
                  & Node.Spec_Name.all
                  & """;");
               New_Line_Count;
               S_Put
                 ((Level + 1) * Indent_Level,
                  "return "
                  & Node_Image (Node.Spec.As_Basic_Decl.P_Defining_Name));
               if Parameters'Length = 0 then
                  S_Put (0, ";");
               else
                  Output_Fake_Parameters;
               end if;
            else
               case SP.Kind is
                  when Constrained | Access_Kind =>
                     S_Put
                       ((Level + 1) * Indent_Level,
                        "return "
                        & Stub_Data_Unit_Name
                        & "."
                        & Stub_Object_Prefix
                        & Node.Spec_Name.all
                        & Suffix
                        & "."
                        & SP.Name.all
                        & ";");

                  when Not_Constrained           =>
                     S_Put
                       ((Level + 1) * Indent_Level,
                        "return "
                        & Stub_Data_Unit_Name
                        & "."
                        & Stub_Object_Prefix
                        & Node.Spec_Name.all
                        & Suffix
                        & "."
                        & SP.Name.all
                        & ".all;");
               end case;
            end if;
            New_Line_Count;
         else
            S_Put ((Level + 1) * Indent_Level, "pragma Compile_Time_Warning");
            New_Line_Count;
            S_Put ((Level + 1) * Indent_Level + 2, "(Standard.True,");
            New_Line_Count;
            S_Put
              ((Level + 2) * Indent_Level,
               """Stub for " & Node.Spec_Name.all & " is unimplemented,""");
            New_Line_Count;
            S_Put
              ((Level + 2) * Indent_Level,
               "& "" this might affect some tests"");");
            New_Line_Count;
            S_Put
              ((Level + 1) * Indent_Level,
               "raise Program_Error with ""Unimplemented stub for function "
               & Node.Spec_Name.all
               & """;");
            New_Line_Count;
            S_Put
              ((Level + 1) * Indent_Level,
               "return "
               & Node_Image (Node.Spec.As_Basic_Decl.P_Defining_Name));
            if Parameters'Length = 0 then
               S_Put (0, ";");
            else
               Output_Fake_Parameters;
            end if;
            New_Line_Count;
         end if;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put
        ((Level) * Indent_Level,
         "end " & Node_Image (Node.Spec.As_Basic_Decl.P_Defining_Name) & ";");
      New_Line_Count;
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;

      if Has_Limited_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has limited type parameter, generated setter is incomplete");
      end if;

      if Has_Limited_View_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has parameter of a limited view type, "
            & "generated setter is incomplete");
      end if;

      if Has_Private_Params then
         Report_Std
           ("warning: (gnattest) "
            & Base_Name (Node.Spec.Unit.Get_Filename)
            & ":"
            & Trim (First_Line_Number (Node.Spec)'Img, Both)
            & ":"
            & Trim (First_Column_Number (Node.Spec)'Img, Both)
            & ": "
            & Node.Spec_Name.all
            & " has private type parameter, generated setter is incomplete");
      end if;

      Decrease_Indent (Me);
   end Generate_Function_Body;

   -------------------------
   -- Generate_Entry_Body --
   -------------------------

   procedure Generate_Entry_Body (Node : Element_Node) is
      ID : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);

      Parameters : constant Param_Spec_Array :=
        Node.Spec.As_Basic_Subp_Decl.P_Subp_Decl_Spec.P_Params;
      Family_Def : constant Ada_Node :=
        Node.Spec.As_Entry_Decl.F_Spec.F_Family_Type;
   begin
      Trace (Me, "Generating entry body for " & Node.Spec_Name.all);

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      S_Put (Level * Indent_Level, "entry " & Node.Spec_Name.all);
      if not Family_Def.Is_Null then
         S_Put (0, " (for I in " & Node_Image (Family_Def) & ")");
      end if;
      New_Line_Count;

      if Parameters'Length > 0 then
         S_Put (Level * Indent_Level + 2, "(");

         for I in Parameters'Range loop
            if I = Parameters'First then
               S_Put (0, Node_Image (Parameters (I)));
            else
               S_Put ((Level + 1) * Indent_Level, Node_Image (Parameters (I)));
            end if;

            if I = Parameters'Last then
               S_Put (0, ") when");
            else
               S_Put (0, ";");
            end if;
            New_Line_Count;
         end loop;
      else
         S_Put (Level * Indent_Level + 2, "when");
         New_Line_Count;
      end if;

      S_Put ((Level + 1) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level + 1) * Indent_Level,
         "--  This section can be used to change entry body.");
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put body
      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put (Level * Indent_Level + 2, " Standard.True");
         New_Line_Count;
         S_Put (Level * Indent_Level, "is");
         New_Line_Count;
         S_Put ((Level) * Indent_Level, "begin");
         New_Line_Count;
         S_Put ((Level + 1) * Indent_Level, "null;");
         New_Line_Count;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "end " & Node.Spec_Name.all & ";");
      New_Line_Count;
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;
   end Generate_Entry_Body;

   ------------------------
   -- Generate_Task_Body --
   ------------------------

   procedure Generate_Task_Body (Node : Element_Node) is
      ID : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);
   begin
      Trace (Me, "Generating task body for " & Node.Spec_Name.all);

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      S_Put (Level * Indent_Level, "task body " & Node.Spec_Name.all & " is");
      New_Line_Count;

      S_Put ((Level + 1) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level + 1) * Indent_Level,
         "--  This section can be used to change task body.");
      New_Line_Count;
      S_Put ((Level + 1) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put body
      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put ((Level) * Indent_Level, "begin");
         New_Line_Count;
         S_Put
           ((Level + 1) * Indent_Level,
            "delay until Ada.Real_Time.Time_Last;");
         New_Line_Count;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "end " & Node.Spec_Name.all & ";");
      New_Line_Count;
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;
   end Generate_Task_Body;

   ------------------------------------
   -- Generate_Full_Type_Declaration --
   ------------------------------------

   procedure Generate_Full_Type_Declaration (Node : Element_Node) is
      Discr_Part : constant Discriminant_Part :=
        Node.Spec.As_Incomplete_Type_Decl.F_Discriminants;
      Is_Tagged  : constant Boolean :=
        Node.Spec.Kind = Ada_Incomplete_Tagged_Type_Decl;

      ID : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);
   begin
      Trace (Me, "Generating full type declaration for " & Node.Spec_Name.all);

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;

      Add_Entity_To_Local_List (Node, New_Line_Counter, Level * Indent_Level);

      S_Put (Level * Indent_Level, "type " & Node.Spec_Name.all & " ");
      if not Discr_Part.Is_Null
        and then Discr_Part.Kind = Ada_Known_Discriminant_Part
      then
         S_Put (0, Node_Image (Discr_Part) & " ");
      end if;
      S_Put (0, "is");
      if Is_Tagged then
         S_Put (0, " tagged");
      end if;
      New_Line_Count;

      S_Put ((Level) * Indent_Level, Generate_MD_Id_String (Node.Spec));
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;
      S_Put
        ((Level) * Indent_Level,
         "--  This section can be used for changing type completion.");
      New_Line_Count;
      S_Put ((Level) * Indent_Level, "--");
      New_Line_Count;

      S_Put (0, GT_Marker_End);
      New_Line_Count;

      --  Put bodies

      if not Contains_Then_Emit (ID, Markered_Data) then
         New_Line_Count;
         S_Put ((Level) * Indent_Level + 2, "null record;");
         New_Line_Count;
         New_Line_Count;
      end if;

      S_Put (0, GT_Marker_Begin);
      New_Line_Count;
      S_Put (0, GT_Marker_End);
      New_Line_Count;
      New_Line_Count;
   end Generate_Full_Type_Declaration;

   ---------------------------
   -- Put_Dangling_Elements --
   ---------------------------

   procedure Put_Dangling_Elements is
      ID : Markered_Data_Id;
      MD : Markered_Data_Type;
   begin

      S_Put (3, "-------------------");
      New_Line_Count;
      S_Put (3, "-- Unused Bodies --");
      New_Line_Count;
      S_Put (3, "-------------------");
      New_Line_Count;
      New_Line_Count;

      for MD_Cur in Markered_Data.Iterate loop

         ID := Markered_Data_Maps.Key (MD_Cur);
         MD := Markered_Data.Constant_Reference (MD_Cur);

         if not (ID.Kind in Subprogram_MD | Task_MD | Entry_MD) then
            goto END_DANGLING;
         end if;

         S_Put (0, GT_Marker_Begin);
         New_Line_Count;

         case ID.Kind is
            when Subprogram_MD =>
               S_Put
                 (Indent_Level,
                  "--  procedure/function " & ID.Name.all & " is");

            when Task_MD       =>
               S_Put (3, "--  task body " & ID.Name.all & " is");

            when Entry_MD      =>
               S_Put (3, "--  entry " & ID.Name.all & " when");

            when others        =>
               null;
         end case;

         New_Line_Count;

         Local_Stub_Unit_Mapping.D_Bodies.Append ((New_Line_Counter, 0));

         S_Put
           (2 * Indent_Level,
            Generate_MD_Id_String (ID, Commented_Out => True));
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;

         Put_Lines (MD, Comment_Out => True);

         S_Put (0, GT_Marker_Begin);
         New_Line_Count;
         S_Put (Indent_Level, "--  end " & ID.Name.all & ";");
         New_Line_Count;
         S_Put (0, GT_Marker_End);
         New_Line_Count;
         New_Line_Count;

         <<END_DANGLING>>
      end loop;
   end Put_Dangling_Elements;
end Test.Stub.Write;
