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

--  This unit provides a unify way to load and manipulate the TGen JSON test
--  case format. In fact this package provides helpers functions to retrieve
--  fields in the TGEN JSON test cases.

with GNAT.OS_Lib;

package TGen.JSON.Test_Cases is

   type JSON_Test_Cases is private;
   --  JSON test cases instance. Represent a loaded JSON file.

   No_JSON_Test_Cases : constant JSON_Test_Cases;
   --  A JSON test case file with no test cases.

   type Subprogram_Test_Case is private;
   --  Subprogram test case.

   No_Subprogram_Test_Case : constant Subprogram_Test_Case;
   --  An empty subprogram with no test cases. This value is intended to be
   --  used as a placeholder only.

   subtype Test_Vector_Cursor is Positive;
   --  Test vector cursor.

   type Subprogram_Test is private;
   --  Represents a subprogram test

   type Subprogram_Test_Vector is private
   with
     Iterable =>
       (First       => Subprogram_Test_Vector_First,
        Next        => Subprogram_Test_Vector_Next,
        Has_Element => Subprogram_Test_Vector_Has_Element,
        Element     => Subprogram_Test_Vector_Element);
   --  Represents a subprogram vector

   Empty_Subprogram_Test_Vector : constant Subprogram_Test_Vector;
   --  An empty subprogram test vector.

   type Subprogram_Parameter is private;
   --  Represent a single subprogram parameter

   type Subprogram_Parameter_Vector is private
   with
     Iterable =>
       (First       => Subprogram_Parameter_Vector_First,
        Next        => Subprogram_Parameter_Vector_Next,
        Has_Element => Subprogram_Parameter_Vector_Has_Element,
        Element     => Subprogram_Parameter_Vector_Element);
   --  Represents subprogram parameters

   ----------------------------------------
   --  Subprogram Test Vector Iteration  --
   ----------------------------------------

   function Subprogram_Test_Vector_First
     (Arr : Subprogram_Test_Vector) return Test_Vector_Cursor;
   function Subprogram_Test_Vector_Next
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor)
      return Test_Vector_Cursor;
   function Subprogram_Test_Vector_Has_Element
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor) return Boolean;
   function Subprogram_Test_Vector_Element
     (Arr : Subprogram_Test_Vector; Index : Test_Vector_Cursor)
      return Subprogram_Test;

   ----------------------------------------------
   --  Subprogram Parameters Vector Iteration  --
   ----------------------------------------------

   function Subprogram_Parameter_Vector_First
     (Arr : Subprogram_Parameter_Vector) return Test_Vector_Cursor;
   function Subprogram_Parameter_Vector_Next
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Test_Vector_Cursor;
   function Subprogram_Parameter_Vector_Has_Element
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Boolean;
   function Subprogram_Parameter_Vector_Element
     (Arr : Subprogram_Parameter_Vector; Index : Test_Vector_Cursor)
      return Subprogram_Parameter;
   function Subprogram_Parameter_Vector_Length
     (Arr : Subprogram_Parameter_Vector) return Natural;
   --  Return the number of parameters in this test vector

   function Load_From_File (File_Path : String) return JSON_Test_Cases
   with Pre => GNAT.OS_Lib.Is_Read_Accessible_File (File_Path);
   --  Load a TGen JSON test case file and return an instance of the loaded
   --  file. This function will raise an exception
   --  (`TGen.JSON.Invalid_JSON_Stream`) if the JSON file is not valid.

   procedure Add_Subprogram_To_JSON_File
     (Self : in out JSON_Test_Cases; Subprogram_Hash : String)
   with Pre => not Has_Subprogram (Self, Subprogram_Hash);
   --  Add a subprogram entry to the test case file.

   function Has_Subprogram
     (Self : JSON_Test_Cases; Subp_Hash : String) return Boolean;
   --  Return if the loaded test cases file has test cases for a given
   --  subprogram.

   function Get_Subprogram
     (Self : JSON_Test_Cases; Subp_Hash : String) return Subprogram_Test_Case
   with Pre => Has_Subprogram (Self, Subp_Hash);
   --  Get a subprogram using a subprogram hash.

   function Get_Subprogram_Full_Qualified_Name
     (Self : Subprogram_Test_Case) return String;
   --  Retrieve the full qualified name of a subprogram

   function Get_Subprogram_Vector
     (Self : Subprogram_Test_Case) return Subprogram_Test_Vector;
   --  Get subprogram test vector

   function Is_Generation_Complete
     (Self : Subprogram_Test_Case) return Boolean;
   --  Return if generation is complete for the given subprogram

   function Is_Function (Self : Subprogram_Test_Case) return Boolean;
   --  Returns if the given subprogram is a function or a procedure

   function Get_Subprogram_Return_Type
     (Self : Subprogram_Test_Case) return String
   with Pre => Is_Function (Self);
   --  Returns the given subprogram return type

   function Get_Subprogram_Origin (Self : Subprogram_Test) return String;
   --  Returns the given subprogram origin

   function Get_Subprogram_Name (Self : Subprogram_Test_Case) return String;
   --  Returns the given subprogram name

   function Get_Subprogram_Parameters
     (Self : Subprogram_Test) return Subprogram_Parameter_Vector;
   --  Returns the list of parameters associated to the given subprogram.

   function Has_Global_Values (Self : Subprogram_Test) return Boolean;
   --  Returns if the subprogram has global values.

   function Get_Subprogram_Global_Values
     (Self : Subprogram_Test) return JSON_Array
   with Pre => Has_Global_Values (Self);
   --  Returns subprogram global values if applicable.

   function Get_Parameter_Name (Self : Subprogram_Parameter) return String;
   --  Returns the parameter name.

   function Get_Parameter_Type_Name
     (Self : Subprogram_Parameter) return String;
   --  Returns the parameter type name.

   function Get_Parameter_Value
     (Self : Subprogram_Parameter) return JSON_Value;
   --  Return the parameter value.
   --  TODO: Add parameter value abstraction.

private

   type JSON_Test_Cases is record
      Root : TGen.JSON.JSON_Value;
      --  Root of the loaded JSON document
   end record;

   type Subprogram_Test_Case is record
      Subp_Root : JSON_Value;
   end record;

   type Subprogram_Test_Vector is record
      Values : JSON_Array;
   end record;

   type Subprogram_Test is record
      Root : JSON_Value;
   end record;

   type Subprogram_Parameter_Vector is record
      Values : JSON_Array;
   end record;

   type Subprogram_Parameter is record
      Parameter_Root : JSON_Value;
   end record;

   No_JSON_Test_Cases : constant JSON_Test_Cases :=
     JSON_Test_Cases'(Root => JSON_Null);

   No_Subprogram_Test_Case : constant Subprogram_Test_Case :=
     Subprogram_Test_Case'(Subp_Root => JSON_Null);

   Empty_Subprogram_Test_Vector : constant Subprogram_Test_Vector :=
     Subprogram_Test_Vector'(Values => Empty_Array);

   function Read_Whole_File (Filename : String) return String;
   --  Return the content of a text file as a string

end TGen.JSON.Test_Cases;
