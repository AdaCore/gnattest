------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2014-2021, AdaCore                    --
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

--  This package defines different routines for generating stub files.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Multiway_Trees;

with GNAT.OS_Lib; use GNAT.OS_Lib;

with Libadalang.Analysis; use Libadalang.Analysis;

with Test.Common;  use Test.Common;
with Test.Mapping; use Test.Mapping;

package Test.Stub is

   procedure Process_Unit
     (Pack                : Base_Package_Decl;
      Body_File_Name      : String;
      Stub_Data_File_Spec : String;
      Stub_Data_File_Body : String);
   --  Processes corresponding spec and body,
   --  (re)creates stub body and stub data package.

   Stub_Processing_Error : exception;
   --  Indicates that an unhandled error occured during the processing of given
   --  unit and stub has not being generated partially or completely and thus
   --  is unusable.

   -----------------
   -- LAL parsing --
   -----------------

   type Element_Node is record
      Spec             : Ada_Node;
      Spec_Name        : String_Access;
      --  Not used for incomplete type declarations.
      Inside_Generic   : Boolean := False;
      Inside_Protected : Boolean := False;
   end record;

   package Element_Node_Trees is new
     Ada.Containers.Multiway_Trees (Element_Node);
   use Element_Node_Trees;

   package Element_Node_Lists is new
     Ada.Containers.Doubly_Linked_Lists (Element_Node);
   use Element_Node_Lists;

   Nil_Element_Node : constant Element_Node :=
     (Spec             => No_Ada_Node,
      Spec_Name        => null,
      Inside_Generic   => False,
      Inside_Protected => False);

   type Stubbing_Data is record
      Elem_Tree : Element_Node_Trees.Tree;
      Flat_List : Element_Node_Lists.List;

      Limited_Withed_Units : String_Set.Set;
      --  All limited withed units from the spec should have a corresponding
      --  regular with clause in the body.

      Tasks_Present : Boolean;
      --  Whether tasking subprogram were encountered. If True, we should
      --  import the tasking runtime in the stub files.
   end record;

   -------------------
   -- Markered Data --
   -------------------

   type Markered_Data_Kinds is
     (
     --  with clauses, code 00
     Import_MD,
      --  incomplete type, code 01
      Type_MD,
      --  task type or single task, code 02
      Task_MD,
      --  local declarations in packages, code 03
      Package_MD,
      --  subprogram, code 04
      Subprogram_MD,
      --  entry, code 05
      Entry_MD,
      --  possible elaboration code, code 06
      Elaboration_MD,
      --  used in attempts to partially recover corrupted packages, code 99
      Unknown_MD);

   type Markered_Data_Id is record
      Kind         : Markered_Data_Kinds;
      Self_Hash    : String_Access;
      Nesting_Hash : String_Access;
      Hash_Version : String_Access;
      Name         : String_Access;
   end record;
   --  Markered Datas are identified using hashes.

   function "<" (L, R : Markered_Data_Id) return Boolean;

   package String_Vectors is new
     Ada.Containers.Indefinite_Vectors (Natural, String);
   --  List of strings representing the lines the user wrote which we are
   --  keeping track of.

   type Markered_Data_Type is record
      Commented_Out : Boolean := False;
      Lines         : String_Vectors.Vector := String_Vectors.Empty_Vector;
   end record;
   --  Markered data is essentially lines of code. The Commented_Out
   --  parameter is used if the generated data it is attached to disappears
   --  when regenerating the stubs, to comment out the user code instead of
   --  removing it.

   package Markered_Data_Maps is new
     Ada.Containers.Indefinite_Ordered_Maps
       (Markered_Data_Id,
        Markered_Data_Type,
        "<");
   use Markered_Data_Maps;
   subtype MD_Map is Markered_Data_Maps.Map;

private

   ------------------------------
   -- Markered Data processing --
   ------------------------------

   function MD_Kind_To_String (MD : Markered_Data_Kinds) return String;
   --  Returns string with corresponding code
   function MD_Kind_From_String (Str : String) return Markered_Data_Kinds;
   --  And back (Unknown for "99" and any illegal argument)

   function Hash_Suffix (ID : Markered_Data_Id) return String;
   --  Returns hash suffix from given ID

   function Generate_MD_Id_String
     (Element : Ada_Node; Commented_Out : Boolean := False) return String;
   function Generate_MD_Id_String
     (Id : Markered_Data_Id; Commented_Out : Boolean := False) return String;
   function Generate_MD_Id (Element : Ada_Node) return Markered_Data_Id;

   procedure Gather_Markered_Data (File : String; Map : in out MD_Map);

   ------------------------------------------
   --  Arguments & result profile analysis --
   ------------------------------------------

   type Stubbed_Parameter_Kinds is (Access_Kind, Constrained, Not_Constrained);

   type Stubbed_Parameter is record
      Name                 : String_Access;
      Type_Image           : String_Access;
      Type_Full_Name_Image : String_Access;  --  for nested types
      Kind                 : Stubbed_Parameter_Kinds;
      Type_Elem            : Ada_Node;
   end record;

   package Stubbed_Parameter_Lists is new
     Ada.Containers.Doubly_Linked_Lists (Stubbed_Parameter);
   use Stubbed_Parameter_Lists;

   function Get_Args_List
     (Node : Element_Node) return Stubbed_Parameter_Lists.List;
   --  Returns info on access, out and in out parameters of the subprogram and
   --  on result profile in case of functions.

   function Get_Type_Image (Param_Type : Type_Expr) return String;
   --  Returns exact image is the argument type is not declared in nested
   --  package. Otherwise replaces whatever name of the type is given with
   --  corresponding full ada name.

   function Is_Abstract (Param_Type : Type_Expr) return Boolean;
   --  Analyzes type definition and detects is it's private or public
   --  declaration is abstract.

   function Is_Fully_Private (Param_Type : Type_Expr) return Boolean;
   --  Analyzes type definition and detects if corresponding type is declared
   --  only in the private declaration part.

   function Is_Limited (Param_Type : Type_Expr) return Boolean;
   --  Analyzes type definition and detects is it's private or public
   --  declaration is limited.

   function Is_Only_Limited_Withed (Param_Type : Type_Expr) return Boolean;
   --  Analyzes type definition and detects if only the limited view is
   --  available. If so, Is_Limited and Is_Abstract are not to be applied.

   function Is_Anon_Access_To_Subp (Param_Type : Type_Expr) return Boolean;
   --  Returns whether Param_Type represents an anonymous access to subprogram
   --  type.

   -------------
   -- Mapping --
   -------------

   use Entity_Stub_Mapping_List;

   Local_Stub_Unit_Mapping : Stub_Unit_Mapping;

   procedure Add_Entity_To_Local_List
     (Node : Element_Node; New_First_Line, New_First_Column : Natural);
   --  Adds mapping info to Local_Stub_Unit_Mapping

   procedure Update_Local_Entity_With_Setter
     (Node : Element_Node; New_First_Line, New_First_Column : Natural);
   --  Adds mapping info on setter to corresponding item in the list

   -------------------------------
   -- Setter package generation --
   -------------------------------

   procedure Generate_Default_Setter_Spec (Node : Element_Node);
   --  Generate stub data type and object and a setter spec

   procedure Generate_Default_Setter_Body (Node : Element_Node);
   --  Generate setter body

   function Get_Access_Type_Name (Elem : Subtype_Indication) return String;
   --  Returns full ada name for given type definition with "." and "'"
   --  replaced with underscores and an "_Access" suffix.

   type Access_Dictionary_Entry is record
      Entry_Str : String_Access := null;
      Type_Decl : Ada_Node := No_Ada_Node;
   end record;

   function "<" (L, R : Access_Dictionary_Entry) return Boolean
   is (L.Entry_Str.all < R.Entry_Str.all);

   package Access_Dictionaries is new
     Ada.Containers.Indefinite_Ordered_Sets (Access_Dictionary_Entry);
   use Access_Dictionaries;

   Dictionary : Access_Dictionaries.Set;
   --  A set of all unrestricted types that we need to make access types for

   procedure Add_Unconstrained_Type_To_Dictionary (Elem : Subtype_Indication);
   --  Updates the dictionary of unconstrained-to-access types if needed
end Test.Stub;
