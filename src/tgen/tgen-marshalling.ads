------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                      Copyright (C) 2021-2023, AdaCore                    --
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
--
--  This unit provides a procedure to generate a marshalling/un-marshalling
--  function for a given Ada type.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Templates_Parser; use Templates_Parser;

with TGen.Types.Constraints; use TGen.Types.Constraints;
with TGen.Types;             use TGen.Types;
with TGen.Strings;           use TGen.Strings;

limited with TGen.Libgen;

package TGen.Marshalling is

   function Get_IO_Support
     (Typ : TGen.Types.Typ'Class) return TGen.Libgen.IO_Support;
   --  Return the IO capabilities TGen can generate for Typ

   function Is_Supported_Type (Typ : TGen.Types.Typ'Class) return Boolean;
   --  Return True for types which are currently fully supported by TGen

   function Type_Supports_Input (Typ : TGen.Types.Typ'Class) return Boolean;
   --  Whether TGen can generate input function for Typ

   function Type_Supports_Output (Typ : TGen.Types.Typ'Class) return Boolean;
   --  Whether TGen can generate output functions for Typ

   function Needs_Header (Typ : TGen.Types.Typ'Class) return Boolean;
   --  Return True for types which have constraints (bounds of unconstrained
   --  array types, and discriminants of unconstrained record types).

   function Output_Fname_For_Typ (Typ_FQN : Ada_Qualified_Name) return String;
   --  Name of the output marshalling function for the given type

   function Input_Fname_For_Typ (Typ_FQN : Ada_Qualified_Name) return String;
   --  Name of the input marshalling function for the given type

   function Get_Array_Size_Limit return Positive;
   --  Return the size beyond which the marshallers will give up trying to load
   --  arrays, to avoid allocating overly-large arrays on the stack.
   --
   --  The default value is 1000, but this can be overridden either through the
   --  TGEN_ARRAY_LIMIT environment variable, or the Set_Array_Size_Limit
   --  procedure. The latter takes precedence over the former.

   procedure Set_Array_Size_Limit (Limit : Positive);
   --  Set the array size limit beyond which marshallers will give up reading
   --  array values, to avoid allocating overly large arrays on the stack.
   --
   --  If used, this will override any value set through the TGEN_ARRAY_LIMIT
   --  environment variable.

   Global_Prefix : constant String := "TGen_Marshalling";

   type Spec_Part is (Pub, Priv);

private
   Marshalling_Lib : constant String := "TGen.Marshalling_Lib";

   function Prefix_For_Typ (Ty_Name : String) return String
   is (Global_Prefix & "_" & Ty_Name);
   --  Construct a prefix that will be shared by all entities generated for a
   --  given type.

   generic
      Differentiate_Discrete : Boolean;
      --  Whether we should use differentiated marshalling function for the
      --  various discrete type kinds, or a single one.

      with
        function Component_Read
          (Assocs : Translate_Table) return Unbounded_String;
      --  Generate a call to read a record / array component

      with
        function Component_Read_Indexed
          (Assocs : Translate_Table) return Unbounded_String;
      --  Generate a call to read a record / array component

      with
        function Component_Write
          (Assocs : Translate_Table) return Unbounded_String;
      --  Generate a call to write a record / array component

      with
        function Variant_Read_Write
          (Assocs : Translate_Table) return Unbounded_String;
      --  Generate a variant part as part of a read / write action procedure

      with procedure Print_Header (Assocs : Translate_Table);
      --  Output a header (un)marshallers (for an unconstrained type)

      with procedure Print_Default_Header (Assocs : Translate_Table);
      --  Output a default header type for constrained types that do not
      --  normally require a header.

      with
        procedure Print_Scalar (Assocs : Translate_Table; For_Base : Boolean);
      --  Output a scalar (un)marshallers

      with procedure Print_Array (Assocs : Translate_Table);
      --  Output an array (un)marshallers

      with procedure Print_Record (Assocs : Translate_Table);
      --  Output a record (un)marshallers

      with procedure Print_Header_Wrappers (Assocs : Translate_Table);
      --  Output an unconstrained type (un)marshallers, (un)marshalling both
      --  the type's header and the type's component(s).

      with procedure Print_Derived_Private_Subtype (Assocs : Translate_Table);
      --  Output (un)marshallers for a type that is a derivation of a
      --  private type.

      with procedure Print_Proxy_Read (Assocs : Translate_Set);
      --  Output the body of the function to read a value using a proxy

     procedure Generate_Base_Functions_For_Typ
     (Typ : TGen.Types.Typ'Class; For_Base : Boolean := False)
   with
     Pre =>
       (if For_Base then Typ in Scalar_Typ'Class)
       and then Typ not in Anonymous_Typ'Class
       and then Typ not in Instance_Typ'Class;
   --  Generate base marshalling and unmarshalling functions for Typ. Note that
   --  this function will not operate recursively. It will thus have to be
   --  called for each of the component type of a record for instance.
   --
   --  If For_Base is True, generate the functions for Typ'Base.
   --
   --  For scalars, we generate:
   --
   --  procedure TAGAda_Marshalling_Typ_Write
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : Typ;
   --     TAGAda_Marshalling_First  : Typ := Typ'First;
   --     TAGAda_Marshalling_Last   : Typ := Typ'Last);
   --
   --  procedure TAGAda_Marshalling_Typ_Read
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : out Typ;
   --     TAGAda_Marshalling_First  : Typ := Typ'First;
   --     TAGAda_Marshalling_Last   : Typ := Typ'Last);
   --
   --  The additional First and Last parameters are used to handle anonymous
   --  subtypes in record or array components.
   --
   --  For composite types with no headers, we generate:
   --
   --  procedure TAGAda_Marshalling_Typ_Write
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : Typ);
   --
   --  procedure TAGAda_Marshalling_Typ_Read
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : out Typ);
   --
   --  For composite types with headers, we generate:
   --
   --  type TAGAda_Marshalling_Typ_Header_Type is record
   --     < Typ's array bound or record discriminants >
   --  end record;
   --
   --  function TAGAda_Marshalling_Typ_Input_Header
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class)
   --    return TAGAda_Marshalling_Typ_Header_Type;
   --
   --  procedure TAGAda_Marshalling_Typ_Output_Header
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_V      : Typ);
   --
   --  procedure TAGAda_Marshalling_Typ_Write
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : Typ);
   --
   --  procedure TAGAda_Marshalling_Typ_Read
   --    (TAGAda_Marshalling_Stream : not null access Root_Stream_Type'Class;
   --     TAGAda_Marshalling_Buffer : in out Unsigned_8;
   --     TAGAda_Marshalling_Offset : in out Offset_Type;
   --     TAGAda_Marshalling_V      : out Typ);

   procedure Put_Line (Str : US_Access; Added : String);

   procedure New_Line (Str : US_Access);

end TGen.Marshalling;
