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

   -----------------------------------
   --  Add_Subprogram_To_JSON_File  --
   -----------------------------------

   procedure Add_Subprogram_To_JSON_File
     (Self : in out JSON_Test_Cases; Subprogram_Hash : String)
   is
      Subp_Root : constant TGen.JSON.JSON_Value := TGen.JSON.Create;
   begin
      Subp_Root.Set_Field ("test_vectors", TGen.JSON.Empty_Array);
      Self.Root.Set_Field (Subprogram_Hash, Subp_Root);
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

   -----------------------------
   --  Get_Subprogram_Origin  --
   -----------------------------

   function Get_Subprogram_Origin (Self : Subprogram_Test) return String
   is (Self.Root.Get ("origin"));

   ---------------------------
   --  Get_Subprogram_Name  --
   ---------------------------

   function Get_Subprogram_Name (Self : Subprogram_Test_Case) return String
   is (Self.Subp_Root.Get ("name"));

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
     (Self : Subprogram_Test) return JSON_Array
   is (Self.Root.Get ("global_values"));

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

end TGen.JSON.Test_Cases;
