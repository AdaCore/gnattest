------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2014-2022, AdaCore                    --
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

with GNATCOLL.Traces; use GNATCOLL.Traces;

with Test.Skeleton.Source_Table;

with Libadalang.Common;    use Libadalang.Common;
with Langkit_Support.Errors;
with Langkit_Support.Text; use Langkit_Support.Text;

with GNAT.SHA1;
with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with GNAT.Traceback.Symbolic;

with Ada.Exceptions;
with Ada.Text_IO;             use Ada.Text_IO;
with Ada.Strings;             use Ada.Strings;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;
with Ada.Characters.Handling; use Ada.Characters.Handling;

with Utils.String_Utilities;

with Test.Stub.Write; use Test.Stub.Write;

package body Test.Stub is
   Me         : constant Trace_Handle := Create ("Stubs", Default => Off);
   Me_Mapping : constant Trace_Handle :=
     Create ("Stubs.Mapping", Default => Off);

   procedure Gather_Data (The_Unit : Ada_Node; Data : out Stubbing_Data);
   --  Gathers all LAL info for stub generation

   function Filter_Private_Parameters
     (Param_List : Stubbed_Parameter_Lists.List)
      return Stubbed_Parameter_Lists.List;
   --  Filer out parameters of private types.

   function Requires_Body (N : Ada_Node) return Boolean;
   --  Checks if a body sample should be created for an element

   ------------------
   -- Process_Unit --
   ------------------

   procedure Process_Unit
     (Pack                : Libadalang.Analysis.Ada_Node;
      Body_File_Name      : String;
      Stub_Data_File_Spec : String;
      Stub_Data_File_Body : String)
   is
      Data          : Stubbing_Data;
      Markered_Data : MD_Map;

      procedure Cleanup;
      --  Frees global and temporary variables

      procedure Report_And_Exclude (Ex : Ada.Exceptions.Exception_Occurrence);
      --  Reports problematic source with exception information and exludes
      --  the source from furter attempts at stubbing it.

      -------------
      -- Cleanup --
      -------------

      procedure Cleanup is
      begin
         Dictionary.Clear;
         Free (Local_Stub_Unit_Mapping.Stub_Data_File_Name);
         Free (Local_Stub_Unit_Mapping.Orig_Body_File_Name);
         Free (Local_Stub_Unit_Mapping.Stub_Body_File_Name);
         Local_Stub_Unit_Mapping.Entities.Clear;
         Local_Stub_Unit_Mapping.D_Setters.Clear;
         Local_Stub_Unit_Mapping.D_Bodies.Clear;

         Data.Elem_Tree.Clear;
         Data.Flat_List.Clear;
         Data.Limited_Withed_Units.Clear;

         Close_File;
      end Cleanup;

      ------------------------
      -- Report_And_Exclude --
      ------------------------

      procedure Report_And_Exclude (Ex : Ada.Exceptions.Exception_Occurrence)
      is
      begin
         if Strict_Execution then
            Report_Err
              (Ada.Exceptions.Exception_Name (Ex)
               & " : "
               & Ada.Exceptions.Exception_Message (Ex)
               & ASCII.LF
               & GNAT.Traceback.Symbolic.Symbolic_Traceback (Ex));
         end if;

         --  If it failed once it will fail again most likely, no point
         --  in duplicating the errors. Adding the unit to default stub
         --  exclusion list to avoid further attempts to process it.
         Store_Default_Stub
           (Base_Name (Pack.Unit.Get_Filename), Excluded, Error_Out => False);
      end Report_And_Exclude;

   begin

      Gather_Data (Pack, Data);
      Gather_Markered_Data (Body_File_Name, Markered_Data);

      Local_Stub_Unit_Mapping.Stub_Data_File_Name :=
        new String'(Stub_Data_File_Body);
      Local_Stub_Unit_Mapping.Orig_Body_File_Name :=
        new String'
          (Test.Skeleton.Source_Table.Get_Source_Body
             (Pack.Unit.Get_Filename));
      Local_Stub_Unit_Mapping.Stub_Body_File_Name :=
        new String'(Body_File_Name);

      Generate_Body_Stub (Body_File_Name, Data, Markered_Data);

      --  FIXME: Understand why we call Generate_Stub_Data only when Flat_List
      --  is not Empty.
      if Data.Flat_List.Is_Empty then
         Excluded_Test_Data_Files.Include (Base_Name (Stub_Data_File_Spec));
         Excluded_Test_Data_Files.Include (Base_Name (Stub_Data_File_Body));
      else
         Generate_Stub_Data (Stub_Data_File_Spec, Stub_Data_File_Body, Data);
      end if;

      Add_Stub_List (Pack.Unit.Get_Filename, Local_Stub_Unit_Mapping);

      Cleanup;

   exception
      when Ex : Langkit_Support.Errors.Property_Error =>

         Source_Processing_Failed := True;

         Report_Err
           ("lal error while creating stub for "
            & Base_Name (Pack.Unit.Get_Filename));
         Report_Err ("source file may be incomplete/invalid");

         Report_And_Exclude (Ex);
         Cleanup;
         raise Stub_Processing_Error;

      when Ex : others =>

         Source_Processing_Failed := True;

         Report_Err
           ("unexpected error while creating stub for "
            & Base_Name (Pack.Unit.Get_Filename));

         Report_And_Exclude (Ex);
         Cleanup;
         raise Stub_Processing_Error;

   end Process_Unit;

   -----------------
   -- Gather_Data --
   -----------------

   procedure Gather_Data (The_Unit : Ada_Node; Data : out Stubbing_Data) is
      Spec_Base_File_Name : constant String := The_Unit.Unit.Get_Filename;

      Generic_Layers_Counter : Natural := 0;
      --  All subprograms inside nested generic packages cannot have setters.
      --  This counter is used to know how many nested generic packages are
      --  enclosing current element.

      State_Cur : Element_Node_Trees.Cursor;

      procedure Process_Nodes (Element : Ada_Node'Class);

      procedure Create_Element_Node
        (Element : Ada_Node'Class; Inside_Protected : Boolean := False);
      --  When visiting an Element representing something for which a body
      --  sample may be required, we check if the body is really required
      --  and insert the corresponding Element on the right place in Data
      --  if it is.

      procedure Process_Nodes (Element : Ada_Node'Class) is
         Pub_Part  : Public_Part;
         Priv_Part : Private_Part;

         Inside_Protected : Boolean := False;
      begin
         case Element.Kind is
            when Ada_Base_Package_Decl     =>
               Pub_Part := Element.As_Base_Package_Decl.F_Public_Part;
               Priv_Part := Element.As_Base_Package_Decl.F_Private_Part;

            when Ada_Generic_Package_Decl  =>
               Pub_Part :=
                 Element.As_Generic_Package_Decl.F_Package_Decl.F_Public_Part;
               Priv_Part :=
                 Element.As_Generic_Package_Decl.F_Package_Decl.F_Private_Part;

            when Ada_Protected_Type_Decl   =>
               Pub_Part :=
                 Element.As_Protected_Type_Decl.F_Definition.F_Public_Part;
               Priv_Part :=
                 Element.As_Protected_Type_Decl.F_Definition.F_Private_Part;
               Inside_Protected := True;

            when Ada_Single_Protected_Decl =>
               Pub_Part :=
                 Element.As_Single_Protected_Decl.F_Definition.F_Public_Part;
               Priv_Part :=
                 Element.As_Single_Protected_Decl.F_Definition.F_Private_Part;
               Inside_Protected := True;

            when others                    =>
               null;
         end case;

         if not Pub_Part.Is_Null then
            for El of Pub_Part.As_Declarative_Part.F_Decls loop
               Create_Element_Node (El, Inside_Protected);
            end loop;
         end if;

         if not Priv_Part.Is_Null then
            for El of Priv_Part.As_Declarative_Part.F_Decls loop
               Create_Element_Node (El, Inside_Protected);
            end loop;
         end if;

      end Process_Nodes;

      procedure Create_Element_Node
        (Element : Ada_Node'Class; Inside_Protected : Boolean := False)
      is
         Elem_Node : Element_Node := Nil_Element_Node;
         Cur       : Element_Node_Trees.Cursor;
      begin

         if Element.Kind = Ada_Generic_Package_Decl then
            Generic_Layers_Counter := Generic_Layers_Counter + 1;
         end if;

         if Element.Kind in Ada_Base_Type_Decl then
            if not Element.As_Basic_Decl.F_Aspects.Is_Null then
               for Assoc of Element.As_Basic_Decl.F_Aspects.F_Aspect_Assocs
               loop
                  if To_Lower (Node_Image (Assoc.F_Id)) = "type_invariant" then

                     Report_Std
                       ("warning: (gnattest) "
                        & Base_Name (Assoc.Unit.Get_Filename)
                        & ":"
                        & Trim (First_Line_Number (Assoc)'Img, Both)
                        & ":"
                        & Trim (First_Column_Number (Assoc)'Img, Both)
                        & ": type_invariant aspect");
                     Report_Std
                       ("this can cause circularity in the test harness", 1);
                  end if;

               end loop;
            end if;
         end if;

         Elem_Node.Inside_Protected := Inside_Protected;

         if Requires_Body (Element.As_Ada_Node) then
            Elem_Node.Spec := Element.As_Ada_Node;

            if Element.Kind = Ada_Subp_Decl then
               Elem_Node.Spec_Name := new String'(Get_Subp_Name (Element));
            else
               Elem_Node.Spec_Name :=
                 new String'
                   (Node_Image (Element.As_Basic_Decl.P_Defining_Name));
            end if;

            Elem_Node.Inside_Generic := Generic_Layers_Counter > 0;

            Data.Elem_Tree.Insert_Child
              (State_Cur, Element_Node_Trees.No_Element, Elem_Node, Cur);

            if Element.Kind = Ada_Subp_Decl
              and then Generic_Layers_Counter = 0
              and then not Inside_Protected
            then
               Data.Flat_List.Append (Elem_Node);
            end if;

            if Element.Kind in Ada_Task_Type_Decl | Ada_Single_Task_Decl then
               Data.Tasks_Present := True;
            end if;

            if Element.Kind
               in Ada_Package_Decl
                | Ada_Generic_Package_Decl
                | Ada_Protected_Type_Decl
                | Ada_Single_Protected_Decl
            then
               State_Cur := Cur;
               Process_Nodes (Element);
               State_Cur := Parent (State_Cur);
            end if;

         end if;

         if Element.Kind = Ada_Generic_Package_Decl then
            Generic_Layers_Counter := Generic_Layers_Counter - 1;
         end if;

      end Create_Element_Node;

      Clauses : constant Ada_Node_List :=
        The_Unit.Unit.Root.As_Compilation_Unit.F_Prelude;
   begin
      Trace (Me, "gathering data from " & Spec_Base_File_Name);

      for Cl of Clauses loop
         if Cl.Kind = Ada_With_Clause and then Cl.As_With_Clause.F_Has_Limited
         then
            for WN of Cl.As_With_Clause.F_Packages loop
               Data.Limited_Withed_Units.Include (Node_Image (WN));
            end loop;
         end if;
      end loop;

      Data.Tasks_Present := False;
      State_Cur := Data.Elem_Tree.Root;

      Create_Element_Node (The_Unit);
   end Gather_Data;

   -------------------
   -- Requires_Body --
   -------------------

   function Requires_Body (N : Ada_Node) return Boolean is
   begin
      case N.Kind is
         when Ada_Package_Decl
            | Ada_Generic_Package_Decl
            | Ada_Single_Protected_Decl
            | Ada_Protected_Type_Decl
            | Ada_Single_Task_Decl
            | Ada_Task_Type_Decl                                         =>
            return True;

         when Ada_Entry_Decl                                             =>
            return N.Parent.Parent.Parent.Kind = Ada_Protected_Def;

         when Ada_Subp_Decl                                              =>
            if not N.As_Subp_Decl.P_Next_Part_For_Decl.Is_Null
              and then N.As_Subp_Decl.P_Next_Part_For_Decl.Unit = N.Unit
            then
               return False;
            end if;
            return not N.As_Basic_Subp_Decl.P_Is_Imported;

         when Ada_Generic_Subp_Decl                                      =>
            return not N.As_Generic_Subp_Decl.P_Is_Imported;

         when Ada_Incomplete_Type_Decl | Ada_Incomplete_Tagged_Type_Decl =>
            declare
               Next_Part : constant Base_Type_Decl :=
                 N.As_Base_Type_Decl.P_Next_Part;
            begin
               if Next_Part.Is_Null then
                  return True;
               else
                  return N.Unit /= Next_Part.Unit;
               end if;
            end;

         when others                                                     =>
            return False;
      end case;
   end Requires_Body;

   --------------------------
   -- Gather_Markered_Data --
   --------------------------

   procedure Gather_Markered_Data (File : String; Map : in out MD_Map) is
      Line : String_Access;

      Line_Counter : Natural := 0;

      ID_Found, Commented_Out : Boolean;

      MD : Markered_Data_Type;
      ID : Markered_Data_Id := (Unknown_MD, null, null, null, null);

      Input_File : Ada.Text_IO.File_Type;

      type Parsing_Modes is (Code, Marker, Other);

      Parsing_Mode      : Parsing_Modes := Other;
      Prev_Parsing_Mode : Parsing_Modes := Other;

      function Is_Marker_Start (S : String) return Boolean
      is (Trim (S, Both) = GT_Marker_Begin);
      function Is_Marker_End (S : String) return Boolean
      is (Trim (S, Both) = GT_Marker_End);
      function Is_Id_String (S : String) return Boolean
      is (Head (Trim (S, Both), 7) = "--  id:");

      procedure Parse_Id_String
        (S : String; MD : out Markered_Data_Id; Commented_Out : out Boolean);

      procedure Parse_Id_String
        (S : String; MD : out Markered_Data_Id; Commented_Out : out Boolean)
      is
         Str        : constant String := Trim (S, Both);
         Idx1, Idx2 : Natural;
      begin
         Commented_Out := False;

         Idx1 := Str'First + 7;
         Idx2 := Index (Str, "/", Idx1 + 1);
         MD.Hash_Version := new String'(Str (Idx1 .. Idx2 - 1));

         Idx1 := Idx2 + 1;
         Idx2 := Index (Str, "/", Idx1 + 1);
         MD.Kind := MD_Kind_From_String (Str (Idx1 .. Idx2 - 1));
         if MD.Kind = Import_MD then
            --  Nothing else to parse for this type
            MD.Self_Hash := new String'("");
            MD.Nesting_Hash := new String'("");
            return;
         end if;

         Idx1 := Idx2 + 1;
         Idx2 := Index (Str, "/", Idx1 + 1);
         MD.Self_Hash := new String'(Str (Idx1 .. Idx2 - 1));

         Idx1 := Idx2 + 1;
         Idx2 := Index (Str, "/", Idx1 + 1);
         MD.Nesting_Hash := new String'(Str (Idx1 .. Idx2 - 1));

         Idx1 := Idx2 + 1;
         Idx2 := Index (Str, "/", Idx1 + 1);
         if Str (Idx1 .. Idx2 - 1) = "1" then
            Commented_Out := True;
         end if;

         Idx1 := Idx2 + 1;
         Idx2 := Index (Str, "/", Idx1 + 1);
         MD.Name := new String'(Str (Idx1 .. Idx2 - 1));
      end Parse_Id_String;
   begin
      if not Is_Regular_File (File) then
         return;
      end if;

      Open (Input_File, In_File, File);

      Trace (Me, "parsing " & File & " for markered blocks");
      Increase_Indent (Me);

      while not End_Of_File (Input_File) loop

         Line := new String'(Get_Line (Input_File));
         Line_Counter := Line_Counter + 1;

         case Parsing_Mode is
            when Code   =>
               if Is_Marker_Start (Line.all) then
                  Map.Include (ID, MD);
                  Prev_Parsing_Mode := Code;
                  Parsing_Mode := Marker;

                  MD.Lines := String_Vectors.Empty_Vector;
                  Trace
                    (Me,
                     "closing marker found at line"
                     & Natural'Image (Line_Counter));
               else
                  MD.Lines.Append (Line.all);
               end if;

            when Marker =>
               case Prev_Parsing_Mode is
                  when Other  =>
                     if Is_Id_String (Line.all) then
                        Parse_Id_String (Line.all, ID, Commented_Out);
                        MD.Commented_Out := Commented_Out;
                        ID_Found := True;
                        Trace
                          (Me,
                           "id string found at line"
                           & Natural'Image (Line_Counter));
                     end if;

                     if Is_Marker_End (Line.all) then
                        if ID_Found then
                           Prev_Parsing_Mode := Marker;
                           Parsing_Mode := Code;
                           Trace
                             (Me,
                              "switching to 'Code' at line"
                              & Natural'Image (Line_Counter));
                        else
                           Prev_Parsing_Mode := Marker;
                           Parsing_Mode := Other;
                           Trace
                             (Me,
                              "switching to 'Other' at line"
                              & Natural'Image (Line_Counter));
                        end if;
                     end if;

                  when Code   =>
                     if Is_Marker_End (Line.all) then
                        Prev_Parsing_Mode := Marker;
                        Parsing_Mode := Other;
                        Trace
                          (Me,
                           "switching to 'Other' at line"
                           & Natural'Image (Line_Counter));
                     end if;

                  when Marker =>
                     --  Can't happen.
                     null;
               end case;

            when Other  =>
               if Is_Marker_Start (Line.all) then
                  Parsing_Mode := Marker;
                  Prev_Parsing_Mode := Other;
                  ID_Found := False;
                  Trace
                    (Me,
                     "opening marker found at line"
                     & Natural'Image (Line_Counter));
               end if;
         end case;

         Free (Line);
      end loop;

      Decrease_Indent (Me);
      Close (Input_File);
   end Gather_Markered_Data;

   -------------------------
   -- MD_Kind_From_String --
   -------------------------

   function MD_Kind_From_String (Str : String) return Markered_Data_Kinds is
   begin
      if Str = "00" then
         return Import_MD;
      end if;
      if Str = "01" then
         return Type_MD;
      end if;
      if Str = "02" then
         return Task_MD;
      end if;
      if Str = "03" then
         return Package_MD;
      end if;
      if Str = "04" then
         return Subprogram_MD;
      end if;
      if Str = "05" then
         return Entry_MD;
      end if;
      if Str = "06" then
         return Elaboration_MD;
      end if;

      return Unknown_MD;
   end MD_Kind_From_String;

   -----------------------
   -- MD_Kind_To_String --
   -----------------------

   function MD_Kind_To_String (MD : Markered_Data_Kinds) return String is
   begin
      case MD is
         when Import_MD      =>
            return "00";

         when Type_MD        =>
            return "01";

         when Task_MD        =>
            return "02";

         when Package_MD     =>
            return "03";

         when Subprogram_MD  =>
            return "04";

         when Entry_MD       =>
            return "05";

         when Elaboration_MD =>
            return "06";

         when Unknown_MD     =>
            return "99";
      end case;
   end MD_Kind_To_String;

   ---------
   -- "<" --
   ---------

   function "<" (L, R : Markered_Data_Id) return Boolean is
   begin
      if L.Kind < R.Kind then
         return True;
      end if;

      if L.Kind = R.Kind then
         if L.Self_Hash.all < R.Self_Hash.all then
            return True;
         end if;

         if L.Self_Hash.all = R.Self_Hash.all then
            if L.Nesting_Hash.all < R.Nesting_Hash.all then
               return True;
            end if;

            if L.Nesting_Hash.all = R.Nesting_Hash.all then
               if L.Hash_Version.all < R.Hash_Version.all then
                  return True;
               end if;
            end if;
         end if;
      end if;
      return False;
   end "<";

   ---------------------------
   -- Generate_MD_Id_String --
   ---------------------------

   function Generate_MD_Id_String
     (Element : Ada_Node; Commented_Out : Boolean := False) return String
   is
      Id : constant Markered_Data_Id := Generate_MD_Id (Element);
   begin
      return Generate_MD_Id_String (Id, Commented_Out);
   end Generate_MD_Id_String;

   --------------------
   -- Generate_MD_Id --
   --------------------

   function Generate_MD_Id (Element : Ada_Node) return Markered_Data_Id is
      Arg_Kind : constant Ada_Node_Kind_Type := Element.Kind;
      Id       : Markered_Data_Id;
   begin
      Id.Hash_Version := new String'(Hash_Version);
      case Arg_Kind is
         when Ada_Incomplete_Type_Decl | Ada_Incomplete_Tagged_Type_Decl =>
            Id.Kind := Type_MD;
            Id.Self_Hash :=
              new String'
                (Substring_16
                   (GNAT.SHA1.Digest
                      (Node_Image (Element.As_Basic_Decl.P_Defining_Name))));

         when Ada_Task_Type_Decl | Ada_Single_Task_Decl                  =>
            Id.Kind := Task_MD;
            Id.Self_Hash :=
              new String'
                (Substring_16
                   (GNAT.SHA1.Digest
                      (Node_Image (Element.As_Basic_Decl.P_Defining_Name))));

         when Ada_Package_Decl | Ada_Generic_Package_Decl                =>
            Id.Kind := Package_MD;
            Id.Self_Hash :=
              new String'
                (Substring_16
                   (GNAT.SHA1.Digest
                      (Node_Image (Element.As_Basic_Decl.P_Defining_Name))));

         when Ada_Generic_Subp_Decl | Ada_Subp_Decl                      =>
            Id.Kind := Subprogram_MD;
            if Arg_Kind = Ada_Generic_Subp_Decl then
               Id.Self_Hash :=
                 new String'
                   (Substring_16
                      (GNAT.SHA1.Digest
                         (Node_Image
                            (Element.As_Basic_Decl.P_Defining_Name))));
            else
               Id.Self_Hash :=
                 new String'
                   (Substring_16
                      (Mangle_Hash_16 (Element, For_Stubs => True)));
            end if;

         when Ada_Entry_Decl                                             =>
            Id.Kind := Entry_MD;
            Id.Self_Hash :=
              new String'
                (Substring_16
                   (GNAT.SHA1.Digest
                      (Node_Image (Element.As_Basic_Decl.P_Defining_Name))));

         when others                                                     =>
            null;
      end case;

      Id.Nesting_Hash :=
        new String'(Substring_16 (GNAT.SHA1.Digest (Get_Nesting (Element))));
      Id.Name :=
        new String'(Node_Image (Element.As_Basic_Decl.P_Defining_Name));

      return Id;
   end Generate_MD_Id;

   ---------------------------
   -- Generate_MD_Id_String --
   ---------------------------

   function Generate_MD_Id_String
     (Id : Markered_Data_Id; Commented_Out : Boolean := False) return String
   is
      Res : constant String :=
        "--  id:"
        & Hash_Version
        & "/"
        & MD_Kind_To_String (Id.Kind)
        & "/"
        & Id.Self_Hash.all
        & "/"
        & Id.Nesting_Hash.all
        & "/"
        & (if Commented_Out then "1" else "0")
        & "/"
        & Id.Name.all
        & "/";
   begin
      return Res;
   end Generate_MD_Id_String;

   -------------------
   -- Get_Args_List --
   -------------------

   function Get_Args_List
     (Node : Element_Node) return Stubbed_Parameter_Lists.List
   is
      Result : Stubbed_Parameter_Lists.List :=
        Stubbed_Parameter_Lists.Empty_List;

      Spec : constant Base_Subp_Spec'Class :=
        (if Node.Spec.Kind = Ada_Generic_Subp_Decl
         then Node.Spec.As_Generic_Subp_Decl.F_Subp_Decl.P_Subp_Decl_Spec
         else Node.Spec.As_Basic_Subp_Decl.P_Subp_Decl_Spec);

      Parameters : constant Param_Spec_Array := Spec.P_Params;

      SP : Stubbed_Parameter;

      function Can_Declare_Variable (Param_Type : Type_Expr) return Boolean;

      function Can_Declare_Variable (Param_Type : Type_Expr) return Boolean is
         Param_Type_Name : Libadalang.Analysis.Name;
         Attr_Name       : Identifier;
         Type_Decl       : Base_Type_Decl;
      begin
         Type_Decl := Param_Type.P_Designated_Type_Decl;
         if Type_Decl.Is_Null then
            if not Quiet then
               Report_Err
                 ("Could not determine type referenced by "
                  & Param_Type.Image);
            end if;
            return False;
         end if;

         if Is_Only_Limited_Withed (Param_Type) then
            return False;
         end if;

         if Param_Type.Kind = Ada_Subtype_Indication then
            Param_Type_Name := Param_Type.As_Subtype_Indication.F_Name;
            if Param_Type_Name.Kind = Ada_Attribute_Ref then
               Attr_Name := Param_Type_Name.As_Attribute_Ref.F_Attribute;
               if To_Lower (Node_Image (Attr_Name)) = "class" then
                  return False;
               end if;
            end if;
         end if;

         return Type_Decl.P_Is_Definite_Subtype (Param_Type);
      exception
         when Ex : Property_Error =>
            if not Verbose then
               Trace
                 (Me,
                  "Could not determine if type "
                  & Param_Type.Image
                  & " is definite");
            else
               Report_Err
                 ("Could not determine if type "
                  & Param_Type.Image
                  & " is definite, assuming it is not.");
            end if;
            Report_Ex (Ex);
            return False;
      end Can_Declare_Variable;

   begin
      Trace (Me, "Getting argument list for " & Node.Spec_Name.all);
      Increase_Indent (Me);

      for J in Parameters'Range loop
         declare
            Param      : constant Param_Spec := Parameters (J);
            Name_List  : constant Defining_Name_List := F_Ids (Param);
            Param_Type : constant Type_Expr := Param.F_Type_Expr;

            Type_Of_Interest : constant Boolean :=
              Is_Only_Limited_Withed (Param_Type)
              or else not Is_Abstract (Param_Type);
            --  From limited view or else not abstract
         begin

            if Type_Of_Interest then
               if Param_Type.Kind = Ada_Anonymous_Type
                 and then Param_Type
                            .As_Anonymous_Type
                            .F_Type_Decl
                            .As_Type_Decl
                            .F_Type_Def
                            .Kind
                          = Ada_Type_Access_Def
                 and then not Param_Type
                                .As_Anonymous_Type
                                .F_Type_Decl
                                .As_Type_Decl
                                .F_Type_Def
                                .As_Type_Access_Def
                                .F_Has_Constant
                 and then not Is_Limited
                                (Param_Type
                                   .As_Anonymous_Type
                                   .F_Type_Decl
                                   .As_Type_Decl
                                   .F_Type_Def
                                   .As_Type_Access_Def
                                   .F_Subtype_Indication
                                   .As_Type_Expr)
               then
                  for N of Name_List loop
                     SP.Name := new String'(Node_Image (N));
                     SP.Type_Image := new String'(Node_Image (Param_Type));
                     SP.Type_Full_Name_Image :=
                       new String'(Get_Type_Image (Param_Type));
                     SP.Kind := Access_Kind;

                     SP.Type_Elem := Param_Type.As_Ada_Node;

                     Result.Append (SP);
                  end loop;

               elsif Param.F_Mode.Kind in Ada_Mode_In_Out | Ada_Mode_Out then
                  for N of Name_List loop
                     SP.Name := new String'(Node_Image (N));
                     SP.Type_Elem := Param_Type.As_Ada_Node;

                     if Can_Declare_Variable (Param_Type) then
                        SP.Type_Image := new String'(Node_Image (Param_Type));
                        SP.Type_Full_Name_Image :=
                          new String'(Get_Type_Image (Param_Type));
                        SP.Kind := Constrained;
                     else
                        SP.Type_Image :=
                          new String'
                            (Get_Access_Type_Name
                               (Param_Type.As_Subtype_Indication));
                        SP.Type_Full_Name_Image :=
                          new String'
                            (Get_Access_Type_Name
                               (Param_Type.As_Subtype_Indication));
                        SP.Kind := Not_Constrained;

                        if not Is_Fully_Private (Param_Type) then
                           Add_Unconstrained_Type_To_Dictionary
                             (Param_Type.As_Subtype_Indication);
                        end if;
                     end if;

                     Result.Append (SP);
                  end loop;
               end if;
            end if;
         end;
      end loop;

      if Spec.As_Subp_Spec.F_Subp_Kind.Kind = Ada_Subp_Kind_Function then
         declare
            Res_Profile : constant Type_Expr :=
              Spec.As_Subp_Spec.F_Subp_Returns;
         begin
            SP.Name := new String'(Node.Spec_Name.all & Stub_Result_Suffix);
            SP.Type_Elem := Res_Profile.As_Ada_Node;

            if Res_Profile.Kind = Ada_Anonymous_Type then
               SP.Type_Image := new String'(Node_Image (Res_Profile));
               SP.Type_Full_Name_Image :=
                 new String'(Get_Type_Image (Res_Profile));
               SP.Kind := Access_Kind;
            else
               if Can_Declare_Variable (Res_Profile) then
                  SP.Type_Image := new String'(Node_Image (Res_Profile));
                  SP.Type_Full_Name_Image :=
                    new String'(Get_Type_Image (Res_Profile));
                  SP.Kind := Constrained;
               else
                  SP.Type_Image :=
                    new String'
                      (Get_Access_Type_Name
                         (Res_Profile.As_Subtype_Indication));
                  SP.Type_Full_Name_Image :=
                    new String'
                      (Get_Access_Type_Name
                         (Res_Profile.As_Subtype_Indication));
                  SP.Kind := Not_Constrained;

                  if not Is_Fully_Private (Res_Profile) then
                     Add_Unconstrained_Type_To_Dictionary
                       (Res_Profile.As_Subtype_Indication);
                  end if;
               end if;
            end if;
         end;

         Result.Append (SP);
      end if;

      Decrease_Indent (Me);
      return Result;
   end Get_Args_List;

   -----------------
   -- Is_Abstract --
   -----------------

   function Is_Abstract (Param_Type : Type_Expr) return Boolean is
      Param_Type_Def  : Type_Def;
      Type_Decl, Decl : Base_Type_Decl;
      Subtype_Ind     : Subtype_Indication;
   begin

      if Param_Type.Kind = Ada_Anonymous_Type then
         Param_Type_Def := Param_Type.As_Anonymous_Type.F_Type_Decl.F_Type_Def;
         if Param_Type_Def.Kind = Ada_Access_To_Subp_Def then
            return False;
         else
            Subtype_Ind :=
              Param_Type_Def.As_Type_Access_Def.F_Subtype_Indication;
         end if;
      else
         Subtype_Ind := Param_Type.As_Subtype_Indication;
      end if;

      Type_Decl := Subtype_Ind.P_Designated_Type_Decl;

      if Type_Decl.Kind in Ada_Generic_Formal then
         return False;
      end if;

      if Type_Decl.Kind in Ada_Interface_Kind then
         return True;
      end if;

      Decl := Type_Decl;
      while not Decl.Is_Null loop
         if Abstract_Type (Decl) then
            return True;
         end if;
         Decl := Decl.P_Next_Part;
      end loop;
      Decl := Type_Decl.P_Previous_Part;
      while not Decl.Is_Null loop
         if Abstract_Type (Decl) then
            return True;
         end if;
         Decl := Decl.P_Previous_Part;
      end loop;

      return False;

   end Is_Abstract;

   -----------------
   -- Hash_Suffix --
   -----------------

   function Hash_Suffix (ID : Markered_Data_Id) return String is
      Self_First    : constant Integer := ID.Self_Hash.all'First;
      Self_Last     : constant Integer := ID.Self_Hash.all'First + 5;
      Nesting_First : constant Integer := ID.Nesting_Hash.all'First;
      Nesting_Last  : constant Integer := ID.Nesting_Hash.all'First + 5;
   begin
      return
        "_"
        & ID.Self_Hash.all (Self_First .. Self_Last)
        & "_"
        & ID.Nesting_Hash.all (Nesting_First .. Nesting_Last);
   end Hash_Suffix;

   --------------------------
   -- Get_Access_Type_Name --
   --------------------------

   function Get_Access_Type_Name (Elem : Subtype_Indication) return String is
      Decl      : constant Base_Type_Decl := Elem.P_Designated_Type_Decl;
      Attr_Suff : constant String :=
        (if Elem.F_Name.Kind = Ada_Attribute_Ref
         then "_" & Node_Image (Elem.F_Name.As_Attribute_Ref.F_Attribute)
         else "");

   begin
      if Get_Nesting (Decl) = "Standard" then
         return
           Utils.String_Utilities.Replace_Char
             (Node_Image (Decl.P_Defining_Name) & Attr_Suff & "_Access",
              From => '.',
              To   => '_');
      else
         return
           Utils.String_Utilities.Replace_Char
             (Encode
                (Decl.P_Defining_Name.P_Fully_Qualified_Name,
                 Decl.Unit.Get_Charset)
              & Attr_Suff
              & "_Access",
              From => '.',
              To   => '_');
      end if;

   end Get_Access_Type_Name;

   --------------------
   -- Get_Type_Image --
   --------------------

   function Get_Type_Image (Param_Type : Type_Expr) return String is
      Param_Type_Def : Type_Def;

      Subtype_Ind : Subtype_Indication;

      Decl : Base_Type_Decl;

      Enclosing_Unit_Name : constant String :=
        To_Lower
          (Node_Image
             (Param_Type
                .Unit
                .Root
                .As_Compilation_Unit
                .F_Body
                .As_Library_Item
                .F_Item
                .As_Basic_Decl
                .P_Defining_Name));

      Overall_Image : constant String := Node_Image (Param_Type);
   begin

      if Param_Type.Kind = Ada_Anonymous_Type then
         Param_Type_Def :=
           Param_Type.As_Anonymous_Type.F_Type_Decl.As_Type_Decl.F_Type_Def;
         if Param_Type_Def.Kind = Ada_Access_To_Subp_Def then
            return Overall_Image;
         else
            Subtype_Ind :=
              Param_Type_Def.As_Type_Access_Def.F_Subtype_Indication;
         end if;
      else
         Subtype_Ind := Param_Type.As_Subtype_Indication;
      end if;

      Decl := Subtype_Ind.P_Designated_Type_Decl;

      if To_Lower (Get_Nesting (Decl)) = "standard" then
         return Overall_Image;
      end if;

      declare
         Insts : constant Generic_Instantiation_Array :=
           Decl.P_Generic_Instantiations;
      begin
         if Insts'Length = 0 and then Decl.Unit /= Param_Type.Unit then
            --  Type declared in another unit, we can keep type name as is
            return Overall_Image;
         elsif Insts'Length > 0
           and then Insts (Insts'First).Unit /= Param_Type.Unit
         then
            --  Type declared in an instantiation that is declared in another
            --  unit, we can keep the type name as is.
            return Overall_Image;
         end if;
      end;

      --  At this point the type is daclared in an instantiation that itself if
      --  declared in the same unit. It may be declared in the same nested
      --  package, in that case we need to put a fully qualified name istead
      --  of the original name.

      declare
         Type_Full : constant String :=
           Encode
             (Decl.As_Basic_Decl.P_Fully_Qualified_Name,
              Decl.Unit.Get_Charset);

         Type_Nesting : constant String :=
           To_Lower
             (Type_Full
                (Type_Full'First .. Index (Type_Full, ".", Backward) - 1));

         Span_Start : constant Token_Reference := Param_Type.Token_Start;
         Span_End   : constant Token_Reference := Param_Type.Token_End;
         Type_Name  : Libadalang.Analysis.Name;
      begin

         Type_Name := Subtype_Ind.F_Name;
         if Type_Name.Kind = Ada_Attribute_Ref then
            Type_Name := Type_Name.As_Attribute_Ref.F_Prefix;
         end if;

         if Index (Type_Nesting, Enclosing_Unit_Name) /= Type_Nesting'First
           or else Type_Nesting'Length <= Enclosing_Unit_Name'Length
         then
            --  Not a nested type declaration from the same package
            return Overall_Image;
         end if;

         return
           Encode
             (Text (Span_Start, Previous (Type_Name.Token_Start)),
              Subtype_Ind.Unit.Get_Charset)
           & Type_Full
           & Encode
               (Text (Next (Type_Name.Token_End), Span_End),
                Subtype_Ind.Unit.Get_Charset);
      end;
   end Get_Type_Image;

   ----------------------
   -- Is_Fully_Private --
   ----------------------

   function Is_Fully_Private (Param_Type : Type_Expr) return Boolean is
      Param_Type_Def : Type_Def;
      Type_Decl      : Base_Type_Decl;
      Subtype_Ind    : Subtype_Indication;
   begin
      if Param_Type.Kind = Ada_Anonymous_Type then
         Param_Type_Def := Param_Type.As_Anonymous_Type.F_Type_Decl.F_Type_Def;
         if Param_Type_Def.Kind = Ada_Access_To_Subp_Def then
            --  Anonymous access to subprogram cannot be private anyway
            return False;
         else
            Subtype_Ind :=
              Param_Type_Def.As_Type_Access_Def.F_Subtype_Indication;
         end if;
      else
         Subtype_Ind := Param_Type.As_Subtype_Indication;
      end if;

      Type_Decl := Subtype_Ind.P_Designated_Type_Decl;

      if Type_Decl.Kind in Ada_Generic_Formal then
         return False;
      end if;

      while not Type_Decl.P_Previous_Part.Is_Null loop
         Type_Decl := Type_Decl.P_Previous_Part;
      end loop;

      declare
         Insts : constant Generic_Instantiation_Array :=
           Type_Decl.P_Generic_Instantiations;
      begin
         for Inst of Insts loop
            if Is_Private (Inst) then
               return True;
            end if;
         end loop;
      end;

      return Is_Private (Type_Decl);
   end Is_Fully_Private;

   ----------------
   -- Is_Limited --
   ----------------

   function Is_Limited (Param_Type : Type_Expr) return Boolean is
      Param_Type_Def  : Type_Def;
      Type_Decl, Decl : Base_Type_Decl;
      Subtype_Ind     : Subtype_Indication;

      function Limited_Type (Decl : Base_Type_Decl) return Boolean;

      function Limited_Type (Decl : Base_Type_Decl) return Boolean is
         Type_Decl : constant Base_Type_Decl := Decl;
      begin
         if Type_Decl.Kind = Ada_Incomplete_Tagged_Type_Decl
           and then Type_Decl.As_Incomplete_Tagged_Type_Decl.F_Has_Abstract
         then
            return False;
         end if;

         if Type_Decl.Kind in Ada_Type_Decl then
            Param_Type_Def := Type_Decl.As_Type_Decl.F_Type_Def;
            if Param_Type_Def.Kind = Ada_Derived_Type_Def
              and then Param_Type_Def.As_Derived_Type_Def.F_Has_Limited
            then
               return True;
            elsif Param_Type_Def.Kind = Ada_Private_Type_Def
              and then Param_Type_Def.As_Private_Type_Def.F_Has_Limited
            then
               return True;
            elsif Param_Type_Def.Kind = Ada_Record_Type_Def
              and then Param_Type_Def.As_Record_Type_Def.F_Has_Limited
            then
               return True;
            elsif Param_Type_Def.Kind = Ada_Interface_Type_Def
              and then not Param_Type_Def
                             .As_Interface_Type_Def
                             .F_Interface_Kind
                             .Is_Null
              and then Param_Type_Def.As_Interface_Type_Def.F_Interface_Kind
                       = Ada_Interface_Kind_Limited
            then
               return True;
            end if;
         end if;
         return False;
      end Limited_Type;
   begin
      if Param_Type.Kind = Ada_Anonymous_Type then
         Param_Type_Def := Param_Type.As_Anonymous_Type.F_Type_Decl.F_Type_Def;
         if Param_Type_Def.Kind = Ada_Access_To_Subp_Def then
            --  Anonymous access to subprogram cannot be private anyway
            return False;
         else
            Subtype_Ind :=
              Param_Type_Def.As_Type_Access_Def.F_Subtype_Indication;
         end if;
      else
         Subtype_Ind := Param_Type.As_Subtype_Indication;
      end if;

      Type_Decl := Subtype_Ind.P_Designated_Type_Decl.P_Canonical_Type;
      if Type_Decl.Kind = Ada_Classwide_Type_Decl then
         Type_Decl := Type_Decl.As_Classwide_Type_Decl.P_Specific_Type;
      end if;

      while not Type_Decl.Is_Null loop
         if Type_Decl.Kind in Ada_Generic_Formal then
            return False;
         end if;

         Decl := Type_Decl;
         while not Decl.Is_Null loop
            if Limited_Type (Decl) then
               return True;
            end if;
            Decl := Decl.P_Next_Part;
         end loop;
         Decl := Type_Decl.P_Previous_Part;
         while not Decl.Is_Null loop
            if Limited_Type (Decl) then
               return True;
            end if;
            Decl := Decl.P_Previous_Part;
         end loop;

         Decl := Type_Decl;
         while not Decl.P_Next_Part.Is_Null loop
            Decl := Decl.P_Next_Part;
         end loop;
         Type_Decl := Parent_Type_Declaration (Decl);

      end loop;

      return False;
   end Is_Limited;

   ----------------------------
   -- Is_Only_Limited_Withed --
   ----------------------------

   function Is_Only_Limited_Withed (Param_Type : Type_Expr) return Boolean is
      Param_Type_Def : Type_Def;
      Type_Decl      : Base_Type_Decl;
      Subtype_Ind    : Subtype_Indication;

      Origin_Unit : constant Analysis_Unit := Param_Type.Unit;
      Type_Unit   : Analysis_Unit;
      Parent_Unit : Ada_Node;

   begin
      if Param_Type.Kind = Ada_Anonymous_Type then
         Param_Type_Def := Param_Type.As_Anonymous_Type.F_Type_Decl.F_Type_Def;
         if Param_Type_Def.Kind = Ada_Access_To_Subp_Def then
            return False;
         else
            Subtype_Ind :=
              Param_Type_Def.As_Type_Access_Def.F_Subtype_Indication;
         end if;
      else
         Subtype_Ind := Param_Type.As_Subtype_Indication;
      end if;

      Type_Decl := Subtype_Ind.P_Designated_Type_Decl;

      declare
         Insts : constant Generic_Instantiation_Array :=
           Type_Decl.P_Generic_Instantiations;
      begin
         if Insts'Length > 0 then
            Type_Unit := Insts (Insts'First).Unit;
         else
            Type_Unit := Type_Decl.Unit;
         end if;
      end;

      if Type_Unit = Type_Decl.P_Standard_Unit then
         return False;
      end if;

      if Origin_Unit = Type_Unit then
         return False;
      end if;

      --  Units are different, we need to analyse with clauses of original unit
      --  and check whether it is a parent unit.

      Parent_Unit := Param_Type.P_Semantic_Parent;
      while not Parent_Unit.Is_Null
        and then Parent_Unit.Unit /= Parent_Unit.P_Standard_Unit
      loop
         if Parent_Unit.Unit = Type_Unit then
            return False;
         end if;
         Parent_Unit := Parent_Unit.P_Semantic_Parent;
      end loop;

      declare
         Clauses : constant Ada_Node_List :=
           Origin_Unit.Root.As_Compilation_Unit.F_Prelude;
      begin
         for Cl of Clauses loop
            if Cl.Kind = Ada_With_Clause
              and then not Cl.As_With_Clause.F_Has_Limited
            then
               declare
                  With_Names : constant Name_List :=
                    Cl.As_With_Clause.F_Packages;

                  Withed_Spec    : Ada_Node;
                  Type_Unit_Spec : constant Ada_Node :=
                    Type_Unit
                      .Root
                      .As_Compilation_Unit
                      .F_Body
                      .As_Library_Item
                      .F_Item
                      .As_Ada_Node;
               begin
                  for WN of With_Names loop
                     Withed_Spec := WN.As_Name.P_Referenced_Decl.As_Ada_Node;

                     if Withed_Spec.Kind = Ada_Package_Renaming_Decl then
                        --  Package renamings should be unwinded
                        Withed_Spec :=
                          Withed_Spec
                            .As_Package_Renaming_Decl
                            .F_Renames
                            .F_Renamed_Object
                            .P_Referenced_Decl
                            .As_Ada_Node;
                     end if;

                     while not Withed_Spec.Is_Null loop
                        if Withed_Spec = Type_Unit_Spec then
                           --  Parameter type declared in a unit from with
                           --  clause or one of its parent units.
                           return False;
                        end if;
                        Withed_Spec := Withed_Spec.P_Semantic_Parent;
                     end loop;
                  end loop;
               end;
            end if;
         end loop;
      end;

      return True;
   end Is_Only_Limited_Withed;

   ----------------------------
   -- Is_Anon_Access_To_Subp --
   ----------------------------

   function Is_Anon_Access_To_Subp (Param_Type : Type_Expr) return Boolean
   is (Param_Type.Kind in Ada_Anonymous_Type
       and then Param_Type.As_Anonymous_Type.F_Type_Decl.F_Type_Def.Kind
                in Ada_Access_To_Subp_Def);

   ------------------------------
   -- Add_Entity_To_Local_List --
   ------------------------------

   procedure Add_Entity_To_Local_List
     (Node : Element_Node; New_First_Line, New_First_Column : Natural)
   is
      Local_Entity : Entity_Stub_Mapping;
   begin
      Trace (Me_Mapping, "adding entry for " & Node.Spec_Name.all);
      Local_Entity.Name := new String'(Node.Spec_Name.all);
      Local_Entity.Line := Integer (First_Line_Number (Node.Spec));
      Local_Entity.Column := Integer (First_Column_Number (Node.Spec));

      Local_Entity.Stub_Body.Line := New_First_Line;
      Local_Entity.Stub_Body.Column := New_First_Column;

      Local_Entity.Setter := Nil_Entity_Sloc;

      Local_Stub_Unit_Mapping.Entities.Append (Local_Entity);
   end Add_Entity_To_Local_List;

   -------------------------------------
   -- Update_Local_Entity_With_Setter --
   -------------------------------------

   procedure Update_Local_Entity_With_Setter
     (Node : Element_Node; New_First_Line, New_First_Column : Natural)
   is
      Cur : Entity_Stub_Mapping_List.Cursor;

      Local_Entity : Entity_Stub_Mapping;
   begin
      Trace (Me_Mapping, "adding setter info for " & Node.Spec_Name.all);
      Increase_Indent (Me_Mapping);

      Local_Entity.Name := new String'(Node.Spec_Name.all);
      Local_Entity.Line := Integer (First_Line_Number (Node.Spec));
      Local_Entity.Column := Integer (First_Column_Number (Node.Spec));

      Cur := Local_Stub_Unit_Mapping.Entities.Find (Local_Entity);

      if Cur = Entity_Stub_Mapping_List.No_Element then
         Trace
           (Me_Mapping,
            "no entity found for setter ("
            & Local_Entity.Name.all
            & ":"
            & Trim (Natural'Image (Local_Entity.Line), Both)
            & ":"
            & Trim (Natural'Image (Local_Entity.Column), Both));
         return;
      end if;

      Local_Entity := Entity_Stub_Mapping_List.Element (Cur);
      Local_Entity.Setter.Line := New_First_Line;
      Local_Entity.Setter.Column := New_First_Column;

      Local_Stub_Unit_Mapping.Entities.Replace_Element (Cur, Local_Entity);
      Decrease_Indent (Me_Mapping);
   end Update_Local_Entity_With_Setter;

   ------------------------------------------
   -- Add_Unconstrained_Type_To_Dictionary --
   ------------------------------------------

   procedure Add_Unconstrained_Type_To_Dictionary (Elem : Subtype_Indication)
   is
      Encl      : Ada_Node := Elem.P_Designated_Type_Decl.As_Ada_Node;
      Dict_Elem : Access_Dictionary_Entry;
   begin
      --  Types formal or not, declared in nested generic packages should not
      --  be added to the dictionary.
      while not Encl.Is_Null loop
         if Encl.Kind in Ada_Generic_Package_Decl | Ada_Generic_Subp_Decl then
            return;
         end if;
         Encl := Encl.Parent;
      end loop;

      Dict_Elem.Type_Decl := Elem.P_Designated_Type_Decl.As_Ada_Node;

      for E of Dictionary loop
         if E.Type_Decl = Dict_Elem.Type_Decl then
            return;
         end if;
      end loop;

      Dict_Elem.Entry_Str :=
        new String'
          ("type "
           & Get_Access_Type_Name (Elem)
           & " is access all "
           & Get_Type_Image (Elem.As_Type_Expr)
           & ";");
      Dictionary.Include (Dict_Elem);
   end Add_Unconstrained_Type_To_Dictionary;

   ----------------------------------
   -- Generate_Default_Setter_Spec --
   ----------------------------------

   procedure Generate_Default_Setter_Spec (Node : Element_Node) is

      ID     : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);
      Suffix : constant String := Hash_Suffix (ID);

      Param_List : Stubbed_Parameter_Lists.List :=
        Filter_Private_Parameters (Get_Args_List (Node));

      Empty_Case : Boolean := Param_List.Is_Empty;
      Skip_Res   : constant Boolean :=
        not Empty_Case
        and then not Param_List.Last_Element.Type_Elem.Is_Null
        and then not Is_Only_Limited_Withed
                       (Param_List.Last_Element.Type_Elem.As_Type_Expr)
        and then (Is_Abstract (Param_List.Last_Element.Type_Elem.As_Type_Expr)
                  or else Is_Anon_Access_To_Subp
                            (Param_List.Last_Element.Type_Elem.As_Type_Expr));
      --  Do not generate a setter for abstract types, or anonymous access-to-
      --  subprogram types.

      Count : Natural;
   begin
      Trace (Me, "Generating default setter spec for " & Node.Spec_Name.all);
      if Skip_Res and then not Empty_Case then
         --  No need to keep it in the parameters list
         Param_List.Delete_Last;
      end if;
      Empty_Case := Param_List.Is_Empty;

      --  Stub type
      S_Put
        (3,
         "type "
         & Stub_Type_Prefix
         & Node.Spec_Name.all
         & Suffix
         & " is record");
      New_Line_Count;

      for SP of Param_List loop
         S_Put (6, SP.Name.all & " : " & SP.Type_Full_Name_Image.all & ";");
         New_Line_Count;
      end loop;

      New_Line_Count;
      S_Put (6, Stub_Counter_Var & " : Natural := 0;");
      New_Line_Count;
      S_Put (3, "end record;");
      New_Line_Count;

      --  stub object
      S_Put
        (3,
         Stub_Object_Prefix
         & Node.Spec_Name.all
         & Suffix
         & " : "
         & Stub_Type_Prefix
         & Node.Spec_Name.all
         & Suffix
         & ";");
      New_Line_Count;

      --  Setter
      S_Put (3, "procedure " & Setter_Prefix & Node.Spec_Name.all & Suffix);
      if not Empty_Case then
         New_Line_Count;
         S_Put (5, "(");

         Count := 1;
         for SP of Param_List loop
            S_Put
              ((if Count = 1 then 0 else 6),
               SP.Name.all
               & " : "
               & SP.Type_Full_Name_Image.all
               & " := "
               & Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & SP.Name.all);

            if Count = Natural (Param_List.Length) then
               S_Put (0, ");");
            else
               S_Put (0, ";");
            end if;
            New_Line_Count;

            Count := Count + 1;
         end loop;
      else
         S_Put (0, ";");
         New_Line_Count;
      end if;

      Param_List.Clear;

   end Generate_Default_Setter_Spec;

   ----------------------------------
   -- Generate_Default_Setter_Body --
   ----------------------------------

   procedure Generate_Default_Setter_Body (Node : Element_Node) is

      ID     : constant Markered_Data_Id := Generate_MD_Id (Node.Spec);
      Suffix : constant String := Hash_Suffix (ID);

      Param_List : Stubbed_Parameter_Lists.List :=
        Filter_Private_Parameters (Get_Args_List (Node));

      Empty_Case : Boolean := Param_List.Is_Empty;
      Skip_Res   : constant Boolean :=
        not Empty_Case
        and then not Param_List.Last_Element.Type_Elem.Is_Null
        and then not Is_Only_Limited_Withed
                       (Param_List.Last_Element.Type_Elem.As_Type_Expr)
        and then (Is_Abstract (Param_List.Last_Element.Type_Elem.As_Type_Expr)
                  or else Is_Anon_Access_To_Subp
                            (Param_List.Last_Element.Type_Elem.As_Type_Expr));
      --  Do not generate a setter for abstract types, or anonymous access-to-
      --  subprogram types.

      Count : Natural;

      Non_Limited_Parameters : Boolean := False;
   begin
      Trace (Me, "Generating default setter body for " & Node.Spec_Name.all);
      if Skip_Res and then not Empty_Case then

         --  No need to keep it in the parameters list

         Param_List.Delete_Last;
      end if;
      Empty_Case := Param_List.Is_Empty;

      S_Put (3, "procedure " & Setter_Prefix & Node.Spec_Name.all & Suffix);
      if not Empty_Case then
         New_Line_Count;
         S_Put (5, "(");

         --  Params declaration

         Count := 1;
         for SP of Param_List loop
            S_Put
              ((if Count = 1 then 0 else 6),
               SP.Name.all
               & " : "
               & SP.Type_Full_Name_Image.all
               & " := "
               & Stub_Object_Prefix
               & Node.Spec_Name.all
               & Suffix
               & "."
               & SP.Name.all);

            if Count = Natural (Param_List.Length) then
               S_Put (0, ") is");
            else
               S_Put (0, ";");
            end if;
            New_Line_Count;
            Count := Count + 1;
         end loop;

         S_Put (3, "begin");
         New_Line_Count;

         --  Params setting

         for SP of Param_List loop
            if not Is_Limited (SP.Type_Elem.As_Type_Expr) then
               S_Put
                 (6,
                  Stub_Object_Prefix
                  & Node.Spec_Name.all
                  & Suffix
                  & "."
                  & SP.Name.all
                  & " := "
                  & SP.Name.all
                  & ";");
               New_Line_Count;

               Non_Limited_Parameters := True;
            end if;
         end loop;
         if not Non_Limited_Parameters then
            S_Put (6, "null;");
         end if;
      else
         S_Put (1, " is");
         New_Line_Count;
         S_Put (3, "begin");
         New_Line_Count;
         S_Put (6, "null;");
         New_Line_Count;
      end if;

      New_Line_Count;

      S_Put (3, "end " & Setter_Prefix & Node.Spec_Name.all & Suffix & ";");
      New_Line_Count;
      New_Line_Count;

      Param_List.Clear;

   end Generate_Default_Setter_Body;

   -------------------------------
   -- Filter_Private_Parameters --
   -------------------------------

   function Filter_Private_Parameters
     (Param_List : Stubbed_Parameter_Lists.List)
      return Stubbed_Parameter_Lists.List
   is
      Res : Stubbed_Parameter_Lists.List := Stubbed_Parameter_Lists.Empty_List;
   begin
      for SP of Param_List loop
         if not Is_Fully_Private (SP.Type_Elem.As_Type_Expr) then
            Res.Append (SP);
         end if;
      end loop;

      return Res;
   end Filter_Private_Parameters;

end Test.Stub;
