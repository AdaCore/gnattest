------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                       Copyright (C) 2025, AdaCore                        --
--                                                                          --
-- TGen  is  free software; you can redistribute it and/or modify it  under --
-- under  terms of  the  GNU General  Public License  as  published by  the --
-- Free  Software  Foundation;  either version 3, or  (at your option)  any --
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

with Ada.Text_IO;
with Ada.Text_IO.Unbounded_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body TGen.JSON.Test_Cases is

   ----------------------
   --  Load_From_File  --
   ----------------------

   function Load_From_File (File_Path : String) return JSON_Test_Cases is
      File_Content : constant String := Read_Whole_File (File_Path);
      Root         : constant JSON_Value :=
        TGen.JSON.Read (File_Content, File_Path);
   begin
      return JSON_Test_Cases'(Root => Root);
   end Load_From_File;

   ---------------
   -- Bind_JSON --
   ---------------

   procedure Bind_JSON (Self : in out JSON_Test_Cases; New_JSON : JSON_Value)
   is
   begin
      Self.Root := New_JSON;
   end Bind_JSON;

   -------------------
   -- Write_To_File --
   -------------------

   procedure Write_To_File (Self : JSON_Test_Cases; File_Path : String) is
      use Ada.Text_IO;

      FT : File_Type;
   begin
      Open (FT, Mode => Out_File, Name => File_Path);
      Put_Line (FT, Self.Root.Write (Compact => False));
      Close (FT);
   end Write_To_File;

   -----------------------------------
   --  Add_Subprogram_To_JSON_File  --
   -----------------------------------

   procedure Add_Subprogram_To_JSON_File
     (Self            : in out JSON_Test_Cases;
      Subprogram_Hash : String;
      Subp_Test_Cases : Subprogram_Test_Case) is
   begin
      Self.Root.Set_Field (Subprogram_Hash, Subp_Test_Cases.Subp_Root);
   end Add_Subprogram_To_JSON_File;

   ----------------------
   --  Has_Subprogram  --
   ----------------------

   function Has_Subprogram
     (Self : JSON_Test_Cases; Subp_Hash : String) return Boolean
   is (Self.Root.Has_Field (Field => Subp_Hash));

   ----------------------
   --  Get_Subprogram  --
   ----------------------

   function Get_Subprogram
     (Self : JSON_Test_Cases; Subp_Hash : String) return Subprogram_Test_Case
   is (Subprogram_Test_Case'(Subp_Root => Self.Root.Get (Subp_Hash)));

   -----------------------------
   --  Get_Subprogram_Vector  --
   -----------------------------

   function Get_Subprogram_Vector
     (Self : Subprogram_Test_Case) return Subprogram_Test_Vector
   is (Subprogram_Test_Vector'(Values => Self.Subp_Root.Get ("test_vectors")));

   ------------------------------------------
   --  Get_Subprogram_Full_Qualified_Name  --
   ------------------------------------------

   function Get_Subprogram_Full_Qualified_Name
     (Self : Subprogram_Test_Case) return String
   is (Self.Subp_Root.Get ("fully_qualified_name"));

   ------------------------------
   --  Is_Generation_Complete  --
   ------------------------------

   function Is_Generation_Complete (Self : Subprogram_Test_Case) return Boolean
   is (Self.Subp_Root.Has_Field ("generation_complete")
       and then Self.Subp_Root.Get ("generation_complete"));

   -------------------
   --  Is_Function  --
   -------------------

   function Is_Function (Self : Subprogram_Test_Case) return Boolean
   is (Self.Subp_Root.Has_Field ("return_type"));

   ----------------------------------
   --  Get_Subprogram_Return_Type  --
   ----------------------------------

   function Get_Subprogram_Return_Type
     (Self : Subprogram_Test_Case) return String
   is (Self.Subp_Root.Get ("return_type"));

   ---------------------------
   --  Get_Subprogram_Name  --
   ---------------------------

   function Get_Subprogram_Name (Self : Subprogram_Test_Case) return String
   is (Self.Subp_Root.Get ("name"));

   ---------------------------------
   -- Create_Subprogram_Test_Case --
   ---------------------------------

   function Create_Subprogram_Test_Case
     (Qualified_Name : String; Return_Type_Name : String := "")
      return Subprogram_Test_Case
   is
      FQN             : constant Unbounded_String :=
        To_Unbounded_String (Qualified_Name);
      Simple_Name_Idx : constant Natural :=
        Ada.Strings.Unbounded.Index (FQN, ".", Going => Ada.Strings.Backward);
      Subp_Root       : constant JSON_Value := Create_Object;
   begin
      if Simple_Name_Idx = 0 then
         raise Program_Error
           with
             "Could not deduce subprogram simple name from qualified name: "
             & Qualified_Name;
      end if;
      Subp_Root.Set_Field
        ("name",
         Create (Unbounded_Slice (FQN, Simple_Name_Idx + 1, Length (FQN))));
      Subp_Root.Set_Field ("fully_qualified_name", FQN);
      Subp_Root.Set_Field ("test_vectors", TGen.JSON.Empty_Array);
      if Return_Type_Name'Length /= 0 then
         Subp_Root.Set_Field ("return_type", Create (Return_Type_Name));
      end if;
      Subp_Root.Set_Field ("generation_complete", Create (True));
      return Subprogram_Test_Case'(Subp_Root => Subp_Root);
   end Create_Subprogram_Test_Case;

   --------------
   -- Add_Test --
   --------------

   procedure Add_Test
     (Self : in out Subprogram_Test_Case; New_Test : Subprogram_Test)
   is
      Subp_Tests : JSON_Array;
   begin
      if Self.Subp_Root.Has_Field ("test_vectors") then
         Subp_Tests := Self.Subp_Root.Get ("test_vectors");
      end if;
      Append (Subp_Tests, New_Test.Root);
      Self.Subp_Root.Set_Field ("test_vectors", Subp_Tests);
   end Add_Test;

   ----------------------------
   -- Create_Subprogram_Test --
   ----------------------------

   function Create_Subprogram_Test
     (Param_Values : Subprogram_Parameter_Vector;
      Origin       : String;
      Globals      : Subprogram_Parameter_Vector := Empty_Parameter_Vector)
      return Subprogram_Test
   is
      Res : constant JSON_Value := Create_Object;
   begin
      Res.Set_Field ("param_values", Param_Values.Values);
      Res.Set_Field ("origin", Create (Origin));
      if Length (Globals.Values) /= 0 then
         Res.Set_Field ("global_values", Globals.Values);
      end if;
      return Subprogram_Test'(Root => Res);
   end Create_Subprogram_Test;

   -----------------------------
   --  Get_Subprogram_Origin  --
   -----------------------------

   function Get_Subprogram_Origin (Self : Subprogram_Test) return String
   is (Self.Root.Get ("origin"));

   ---------------------------------
   --  Get_Subprogram_Parameters  --
   ---------------------------------

   function Get_Subprogram_Parameters
     (Self : Subprogram_Test) return Subprogram_Parameter_Vector
   is (Subprogram_Parameter_Vector'(Values => Self.Root.Get ("param_values")));

   ------------------------------------
   --  Get_Subprogram_Global_Values  --
   ------------------------------------

   function Get_Subprogram_Global_Values
     (Self : Subprogram_Test) return Subprogram_Parameter_Vector
   is (Subprogram_Parameter_Vector'
         (Values => Self.Root.Get ("global_values")));

   -------------------------
   --  Has_Global_Values  --
   -------------------------

   function Has_Global_Values (Self : Subprogram_Test) return Boolean
   is (Self.Root.Has_Field ("global_values"));

   --------------------------
   --  Get_Parameter_Name  --
   --------------------------

   function Get_Parameter_Name (Self : Subprogram_Parameter) return String
   is (Self.Parameter_Root.Get ("name"));

   -------------------------------
   --  Get_Parameter_Type_Name  --
   -------------------------------

   function Get_Parameter_Type_Name (Self : Subprogram_Parameter) return String
   is (Self.Parameter_Root.Get ("type_name"));

   ---------------------------
   --  Get_Parameter_Value  --
   ---------------------------

   function Get_Parameter_Value (Self : Subprogram_Parameter) return JSON_Value
   is (Self.Parameter_Root.Get ("value"));

   ----------------------------------------
   --  Subprogram Test Vector Iteration  --
   ----------------------------------------

   ------------------------------------
   --  Subprogram_Test_Vector_First  --
   ------------------------------------

   function Subprogram_Test_Vector_First
     (Arr : Subprogram_Test_Vector) return Test_Vector_Cursor
   is (Array_First (Arr.Values));

   -----------------------------------
   --  Subprogram_Test_Vector_Next  --
   -----------------------------------

   function Subprogram_Test_Vector_Next
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor)
      return Test_Vector_Cursor
   is (Test_Vector_Cursor (Array_Next (Arr.Values, Index)));

   ------------------------------------------
   --  Subprogram_Test_Vector_Has_Element  --
   ------------------------------------------

   function Subprogram_Test_Vector_Has_Element
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor) return Boolean
   is (Array_Has_Element (Arr.Values, Index));

   --------------------------------------
   --  Subprogram_Test_Vector_Element  --
   --------------------------------------

   function Subprogram_Test_Vector_Element
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor)
      return Subprogram_Test
   is (Subprogram_Test'(Root => Array_Element (Arr.Values, Index)));

   ----------------------------------------------
   --  Subprogram Parameters Vector Iteration  --
   ----------------------------------------------

   -----------------------------------------
   --  Subprogram_Parameter_Vector_First  --
   -----------------------------------------

   function Subprogram_Parameter_Vector_First
     (Arr : Subprogram_Parameter_Vector) return Test_Vector_Cursor
   is (Array_First (Arr.Values));

   ----------------------------------------
   --  Subprogram_Parameter_Vector_Next  --
   ----------------------------------------

   function Subprogram_Parameter_Vector_Next
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Test_Vector_Cursor
   is (Array_Next (Arr.Values, Index));

   -----------------------------------------------
   --  Subprogram_Parameter_Vector_Has_Element  --
   -----------------------------------------------

   function Subprogram_Parameter_Vector_Has_Element
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Boolean
   is (Array_Has_Element (Arr.Values, Index));

   -------------------------------------------
   --  Subprogram_Parameter_Vector_Element  --
   -------------------------------------------

   function Subprogram_Parameter_Vector_Element
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Subprogram_Parameter
   is (Subprogram_Parameter'
         (Parameter_Root => Array_Element (Arr.Values, Index)));

   ----------------------------------------
   -- Subprogram_Parameter_Vector_Length --
   ----------------------------------------

   function Subprogram_Parameter_Vector_Length
     (Arr : Subprogram_Parameter_Vector) return Natural
   is (Length (Arr.Values));

   ----------------------------------
   -- Create_Subprogram_Parameters --
   ----------------------------------

   function Create_Subprogram_Parameters return Subprogram_Parameter_Vector
   is (Subprogram_Parameter_Vector'(Values => Empty_Array));

   ----------------------
   -- Append_Parameter --
   ----------------------

   procedure Append_Parameter
     (Self : in out Subprogram_Parameter_Vector; Value : Subprogram_Parameter)
   is
   begin
      Append (Self.Values, Value.Parameter_Root);
   end Append_Parameter;

   ----------------------
   -- Create_Parameter --
   ----------------------

   function Create_Parameter
     (Name : String; Type_Name : String; Value : JSON_Value)
      return Subprogram_Parameter is
   begin
      return
         Res : constant Subprogram_Parameter :=
           (Parameter_Root => Create_Object)
      do
         Res.Parameter_Root.Set_Field ("name", Create (Name));
         Res.Parameter_Root.Set_Field ("type_name", Create (Type_Name));
         Res.Parameter_Root.Set_Field ("value", Value);
      end return;
   end Create_Parameter;

   -----------------------
   --  Read_Whole_File  --
   -----------------------

   function Read_Whole_File (Filename : String) return String is
      use Ada.Text_IO;

      FT     : File_Type;
      Result : Unbounded_String;
      Line   : Unbounded_String;
   begin
      Open (FT, Mode => In_File, Name => Filename);

      while not End_Of_File (FT) loop
         Unbounded_IO.Get_Line (FT, Line);
         Append (Result, Line);
      end loop;

      Close (FT);
      return To_String (Result);
   end Read_Whole_File;

   -----------
   -- Clone --
   -----------

   function Clone (Val : JSON_Test_Cases) return JSON_Test_Cases
   is (JSON_Test_Cases'(Root => Val.Root.Clone));

   function Clone (Val : Subprogram_Test_Case) return Subprogram_Test_Case
   is (Subprogram_Test_Case'(Subp_Root => Val.Subp_Root.Clone));

   function Clone (Val : Subprogram_Test) return Subprogram_Test
   is (Subprogram_Test'(Root => Val.Root.Clone));

   function Clone (Val : Subprogram_Parameter) return Subprogram_Parameter
   is (Subprogram_Parameter'(Parameter_Root => Val.Parameter_Root.Clone));

end TGen.JSON.Test_Cases;
