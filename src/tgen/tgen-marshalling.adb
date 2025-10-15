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

with Ada.Characters.Latin_1;
with Ada.Environment_Variables;
with Ada.Numerics.Big_Numbers.Big_Integers;
use Ada.Numerics.Big_Numbers.Big_Integers;
with Ada.Strings;                           use Ada.Strings;
with Ada.Strings.Fixed;                     use Ada.Strings.Fixed;
with Ada.Text_IO;                           use Ada.Text_IO;

with TGen.Libgen; use TGen.Libgen;

with TGen.Types.Array_Types;    use TGen.Types.Array_Types;
with TGen.Types.Discrete_Types; use TGen.Types.Discrete_Types;
with TGen.Types.Enum_Types;     use TGen.Types.Enum_Types;
with TGen.Types.Int_Types;      use TGen.Types.Int_Types;
with TGen.Types.Real_Types;     use TGen.Types.Real_Types;
with TGen.Types.Record_Types;   use TGen.Types.Record_Types;

package body TGen.Marshalling is

   ----------------------
   --  Local Variables --
   ----------------------

   Array_Length_Limit_Env_Var : constant String := "TGEN_ARRAY_LIMIT";
   --  Name of the environment variable to be used during generation of the
   --  marshallers to override the default array length limit.

   Array_Length_Limit : Positive := 1000;
   --  Limit in the number of elements beyond which the marshallers will not
   --  even try to create an object, and instead raise an Invalid_Error.

   -----------------------
   -- Local Subprograms --
   -----------------------

   function Needs_Wrappers (Typ : TGen.Types.Typ'Class) return Boolean;
   --  Return True for types with headers when they can occur nested in the
   --  data-structure (not at the top level).
   --  For now, this is only true for types with mutable discriminants as we
   --  do not support access types.

   function Create_Tag_For_Constraints
     (Comp_Ty : TGen.Types.Typ'Class) return Tag;
   --  Create a tag for the constraints of anonymous types.
   --   * For scalars and uni-dimensional arrays:
   --       <Global_Prefix>_First => <Low_Bound>,
   --       <Global_Prefix>_Last  => <High_Bound>
   --   * For mulit-dimensional arrays:
   --       <Global_Prefix>_First_1 => <Low_Bound for first index>,
   --       <Global_Prefix>_Last_1  => <High_Bound for first index>,
   --       <Global_Prefix>_First_2 => <Low_Bound for second index>,
   --       ...
   --   * For records:
   --       <Global_Prefix>_<Discr_Name>_Min => <Low_Bound for Discr_Name>,
   --       <Global_Prefix>_<Discr_Name>_Max => <High_Bound for Discr_Name>,
   --       ...
   --     Min and Max values for discriminants come from types constrained
   --     using a discriminant from the upper level. They are the bounds of
   --     the upper level discriminant type.
   --
   --  ??? For now, we do not support numeric constraints which are not static.
   --  We use the bounds of the type instead. We could possibly do better when
   --  dynamic values are better handled inside tgen. However, we might want to
   --  try to detect cases where a dynamic numeric constraint depends on
   --  variables which might have been modified after the type elaboration.

   function Create_Tag_For_Intervals
     (Intervals : Alternatives_Set; Typ : TGen.Types.Typ'Class) return Tag;
   --  Return as a tag the choices represented by a set of intervals

   procedure Create_Tags_For_Array_Bounds
     (U_Typ        : Unconstrained_Array_Typ'Class;
      Fst_Name_Tag : in out Tag;
      Lst_Name_Tag : in out Tag;
      Typ_Tag      : in out Tag;
      Pref_Tag     : in out Tag;
      Is_Enum_Tag  : in out Tag);
   --  Compute the tags for the bounds of an unconstrained array type:
   --    * Fst_Name_Tag contains the names of the objects corresponding to
   --      the lower bounds: First_1, ...,
   --    * Lst_Name_Tag contains the names of the objects corresponding to
   --      the higher bounds: Last_1, ...,
   --    * Typ_Tag contains the index types: First_Index ..., and
   --    * Pref_Tag contains the prefix associated to the index base types:
   --      Global_Prefix_First_Index_Base...
   --    * Is_Enum_Tag contains wether each index type is a enumerated type

   function Create_Tags_For_Array_Dims (A_Typ : Array_Typ'Class) return Tag;
   --  Compute the string to be associated to array attributes for each
   --  dimension. Return "" for unidimensional arrays and (1) (2)... for
   --  multidimensional ones.

   procedure Create_Tags_For_Discriminants
     (D_Typ          : Record_Typ'Class;
      Name_Tag       : in out Tag;
      Typ_Tag        : in out Tag;
      Pref_Tag       : in out Tag;
      Discr_Ancestor : in out Tag;
      Complete       : Boolean := False)
   with Pre => Is_Discriminated (D_Typ);
   --  Compute the tags for the discriminant of a record type:
   --    * Name_Tag contains the names of the  discriminants: Discr, ...,
   --    * Typ_Tag contains their types: Discr_Ty ..., and
   --    * Pref_Tag contains the prefix associated to the type:
   --      Global_Prefix_Descr_Ty...,
   --    * Complete True when we want all discriminants of the ancestor types
   --      excluding those of the current type.

   function String_Value
     (V : TGen.Types.Big_Integer; Typ : TGen.Types.Typ'Class) return String;
   --  Get a string for the value at position V in Typ

   --------------------------------
   -- Create_Tag_For_Constraints --
   --------------------------------

   function Create_Tag_For_Constraints
     (Comp_Ty : TGen.Types.Typ'Class) return Tag
   is

      function Bound_To_String
        (C      : Discrete_Constraint_Value;
         Typ    : TGen.Types.Typ'Class;
         Is_Min : Boolean := True) return String
      is (case C.Kind is
            when Static       => String_Value (C.Int_Val, Typ),
            when Discriminant =>
              Global_Prefix
              & "_"
              & String'(+C.Disc_Name)
              & (if Is_Min then "_D_Min" else "_D_Max"),
            when Non_Static   => "");
      --  Compute the constraint from a discrete value C. If C has a
      --  static value, we use it. If it is a discriminant, we use the min or
      --  max value for this discriminant. We do not supply values for
      --  dynamic bounds for now. The default values (the First and Last
      --  attribute of the expected type) will be used instead.

      procedure Append_Association
        (Name : String; Value : String; Associations : in out Tag);
      --  Append the association Name => Value to Associations

      ------------------------
      -- Append_Association --
      ------------------------

      procedure Append_Association
        (Name : String; Value : String; Associations : in out Tag) is
      begin
         if Value'Length = 0 then
            return;
         end if;

         Associations := Associations & (Name & " => " & Value);
      end Append_Association;

   begin
      --  Nothing to do for named types

      if Comp_Ty not in Anonymous_Typ'Class then
         return +"";
      end if;

      declare
         Associations : Tag;
         Ancestor     : constant TGen.Types.Typ'Class :=
           Anonymous_Typ'Class (Comp_Ty).Named_Ancestor.all;
         Constraint   : constant Constraint_Acc :=
           Anonymous_Typ'Class (Comp_Ty).Subtype_Constraints;

      begin
         if Constraint = null then
            return +"";

         --  For a discrete range constraint:
         --    range Low .. High
         --  We generate:
         --    First => Low, Last => High

         elsif Constraint.all in Discrete_Range_Constraint'Class then
            declare
               D_Constr : constant Discrete_Range_Constraint'Class :=
                 Discrete_Range_Constraint'Class (Constraint.all);
            begin
               Append_Association
                 (Name         => Global_Prefix & "_First",
                  Value        =>
                    Bound_To_String (D_Constr.Low_Bound, Typ => Ancestor),
                  Associations => Associations);
               Append_Association
                 (Name         => Global_Prefix & "_Last",
                  Value        =>
                    Bound_To_String (D_Constr.High_Bound, Typ => Ancestor),
                  Associations => Associations);
            end;

         --  For an array constraint:
         --    (F1 .. L1, ...)
         --  We generate:
         --    First_1 => F1, Last_1  => L1, ...
         --  If F1 or L1 are discriminants, we generate instead:
         --    First_1 => F1_Min, Last_1  => L1_Max, ...

         elsif Constraint.all in Index_Constraints'Class then
            declare
               A_Typ       : constant Array_Typ'Class :=
                 Array_Typ'Class (Ancestor);
               Idx_Constrs : constant Index_Constraints'Class :=
                 Index_Constraints'Class (Constraint.all);
            begin
               for Index in Idx_Constrs.Constraint_Array'Range loop
                  declare
                     Idx_Constr : constant Index_Constraint :=
                       Idx_Constrs.Constraint_Array (Index).all;
                     Idx_Typ    : constant TGen.Types.Typ'Class :=
                       A_Typ.Index_Types (Index).all;
                     Dim        : constant String := Trim (Index'Image, Left);
                  begin
                     if Idx_Constr.Present then
                        Append_Association
                          (Name         => Global_Prefix & "_First_" & Dim,
                           Value        =>
                             Bound_To_String
                               (Idx_Constr.Discrete_Range.Low_Bound,
                                Idx_Typ,
                                Is_Min => True),
                           Associations => Associations);
                        Append_Association
                          (Name         => Global_Prefix & "_Last_" & Dim,
                           Value        =>
                             Bound_To_String
                               (Idx_Constr.Discrete_Range.High_Bound,
                                Idx_Typ,
                                Is_Min => False),
                           Associations => Associations);
                     end if;
                  end;
               end loop;
            end;

         --  For a discriminant constraint:
         --    (D1 => V1, ...)
         --  We generate:
         --    D1_Min => V1, D1_Max => V1, ...
         --  If V1 is a discriminant, we generate instead:
         --    D1_Min => V1_Min, D1_Max => V1_Max, ...

         elsif Constraint.all in Discriminant_Constraints'Class then
            declare
               D_Typ             : constant Record_Typ'Class :=
                 Record_Typ'Class (Ancestor);
               Discr_Constraints : constant Discriminant_Constraint_Map :=
                 Discriminant_Constraints (Constraint.all).Constraint_Map;
            begin

               for Cu in Discr_Constraints.Iterate loop
                  declare
                     Discr_Text   : constant Unbounded_String :=
                       Discriminant_Constraint_Maps.Key (Cu);
                     Discr_Name   : constant String := +Discr_Text;
                     Discr_Constr : constant Discrete_Constraint_Value :=
                       Discriminant_Constraint_Maps.Element (Cu);
                     Discr_Typ    : constant TGen.Types.Typ'Class :=
                       D_Typ.Discriminant_Types.Element (Discr_Text).all;
                  begin
                     Append_Association
                       (Name         =>
                          Global_Prefix & "_" & Discr_Name & "_D_Min",
                        Value        =>
                          Bound_To_String
                            (Discr_Constr, Discr_Typ, Is_Min => True),
                        Associations => Associations);
                     Append_Association
                       (Name         =>
                          Global_Prefix & "_" & Discr_Name & "_D_Max",
                        Value        =>
                          Bound_To_String
                            (Discr_Constr, Discr_Typ, Is_Min => False),
                        Associations => Associations);
                  end;
               end loop;
            end;
         else
            raise Program_Error;
         end if;
         Set_Separator (Associations, ", ");
         return Associations;
      end;
   end Create_Tag_For_Constraints;

   ------------------------------
   -- Create_Tag_For_Intervals --
   ------------------------------

   function Create_Tag_For_Intervals
     (Intervals : Alternatives_Set; Typ : TGen.Types.Typ'Class) return Tag
   is
      Choices_Tag : Tag;
   begin
      for Int of Intervals loop
         if Int.Min = Int.Max then
            Choices_Tag := Choices_Tag & String_Value (Int.Min, Typ);
         else
            Choices_Tag :=
              Choices_Tag
              & (String_Value (Int.Min, Typ)
                 & " .. "
                 & String_Value (Int.Max, Typ));
         end if;
      end loop;

      Set_Separator (Choices_Tag, " | ");
      return Choices_Tag;
   end Create_Tag_For_Intervals;

   ----------------------------------
   -- Create_Tags_For_Array_Bounds --
   ----------------------------------

   procedure Create_Tags_For_Array_Bounds
     (U_Typ        : Unconstrained_Array_Typ'Class;
      Fst_Name_Tag : in out Tag;
      Lst_Name_Tag : in out Tag;
      Typ_Tag      : in out Tag;
      Pref_Tag     : in out Tag;
      Is_Enum_Tag  : in out Tag)
   is
      First_Name_Tmplt : constant String := "First_@_DIM_@";
      Last_Name_Tmplt  : constant String := "Last_@_DIM_@";

   begin
      for I in U_Typ.Index_Types'Range loop
         declare
            Index_Type : constant String :=
              U_Typ.Index_Types (I).all.FQN (No_Std => True);
            Index_Pref : constant String :=
              Prefix_For_Typ (U_Typ.Index_Types (I).all.Slug);
            Assocs     : constant Translate_Table := [1 => Assoc ("DIM", I)];
         begin
            Fst_Name_Tag :=
              Fst_Name_Tag & Translate (First_Name_Tmplt, Assocs);
            Lst_Name_Tag := Lst_Name_Tag & Translate (Last_Name_Tmplt, Assocs);

            Typ_Tag := Typ_Tag & Index_Type;
            Pref_Tag := Pref_Tag & Index_Pref;
            Is_Enum_Tag :=
              Is_Enum_Tag
              & (U_Typ.Index_Types (I).all.Kind
                 in Bool_Kind | Char_Kind | Enum_Kind);
         end;
      end loop;
   end Create_Tags_For_Array_Bounds;

   --------------------------------
   -- Create_Tags_For_Array_Dims --
   --------------------------------

   function Create_Tags_For_Array_Dims (A_Typ : Array_Typ'Class) return Tag is
      Ada_Dim_Tmplt : constant String := "(@_DIM_@)";

   begin
      return Ada_Dim_Tag : Tag do
         for I in A_Typ.Index_Types'Range loop
            declare
               Assocs : constant Translate_Table := [1 => Assoc ("DIM", I)];
            begin
               if A_Typ.Num_Dims = 1 then
                  Ada_Dim_Tag := Ada_Dim_Tag & "";
               else
                  Ada_Dim_Tag :=
                    Ada_Dim_Tag & Translate (Ada_Dim_Tmplt, Assocs);
               end if;
            end;
         end loop;
      end return;
   end Create_Tags_For_Array_Dims;

   -----------------------------------
   -- Create_Tags_For_Discriminants --
   -----------------------------------

   procedure Create_Tags_For_Discriminants
     (D_Typ          : Record_Typ'Class;
      Name_Tag       : in out Tag;
      Typ_Tag        : in out Tag;
      Pref_Tag       : in out Tag;
      Discr_Ancestor : in out Tag;
      Complete       : Boolean := False)
   is
      procedure Create_Tags_For_Discriminants_Aux (Cur_Typ : Record_Typ'Class);

      procedure Create_Tags_For_Discriminants_Aux (Cur_Typ : Record_Typ'Class)
      is
      begin
         for Cu in Cur_Typ.Discriminant_Types.Iterate loop
            declare
               Discr_Name : constant String := (+Component_Maps.Key (Cu));
               Discr_Typ  : constant String :=
                 (Component_Maps.Element (Cu).all.FQN (No_Std => True));
               Discr_Pref : constant String :=
                 Prefix_For_Typ (Component_Maps.Element (Cu).all.Slug);
            begin
               Name_Tag := Name_Tag & Discr_Name;
               Typ_Tag := Typ_Tag & Discr_Typ;
               Pref_Tag := Pref_Tag & Discr_Pref;
            end;
         end loop;
      end Create_Tags_For_Discriminants_Aux;

      Cur_Ancestor_Typ : Record_Typ_Access := D_Typ.Ancestor;
   begin
      if not Complete then
         Create_Tags_For_Discriminants_Aux (D_Typ);
      else
         while Cur_Ancestor_Typ /= null loop
            if not Cur_Ancestor_Typ.Discriminant_Types.Is_Empty then
               Create_Tags_For_Discriminants_Aux (Cur_Ancestor_Typ.all);
               Discr_Ancestor :=
                 Discr_Ancestor & Cur_Ancestor_Typ.FQN (No_Std => True);
               Cur_Ancestor_Typ := Cur_Ancestor_Typ.Ancestor;
            end if;
         end loop;
      end if;
   end Create_Tags_For_Discriminants;

   -------------------------------------
   -- Generate_Base_Functions_For_Typ --
   -------------------------------------

   procedure Generate_Base_Functions_For_Typ
     (Typ            : TGen.Types.Typ'Class;
      Output_Support : Boolean;
      For_Base       : Boolean := False)
   is
      B_Name    : constant String := Typ.FQN (No_Std => True);
      Ty_Prefix : constant String := Prefix_For_Typ (Typ.Slug);
      Ty_Name   : constant String :=
        (if For_Base then B_Name & "'Base" else B_Name);

      Common_Assocs : constant Translate_Table :=
        [1 => Assoc ("GLOBAL_PREFIX", Global_Prefix),
         2 => Assoc ("TY_PREFIX", Ty_Prefix),
         3 => Assoc ("TY_NAME", Ty_Name),
         4 => Assoc ("HAS_STATIC_PREDICATE", Typ.Has_Static_Predicate),
         5 => Assoc ("NEEDS_HEADER", Needs_Header (Typ)),
         6 => Assoc ("OUTPUT_SUPPORTED", Output_Support)];

      type Component_Kind is (Array_Component, Record_Component);

      --  Function computing the indentation for component handling

      --  Initial spacing for records
      RW_Init_Spacing  : constant Natural := 6;
      --  Incremental spacing for record variants
      Var_Incr_Spacing : constant Natural := 6;
      --  Spacing for arrays
      RW_Arr_Spacing   : constant Natural := 9;

      function RW_Spacing (Spacing : Natural) return String
      is (if Typ in Array_Typ'Class
          then [1 .. RW_Arr_Spacing => ' ']
          else [1 .. RW_Init_Spacing + Spacing * Var_Incr_Spacing => ' ']);
      --  Tags for the components of the header if any, their types, their
      --  prefix and the corresponding Ada Value.

      procedure Collect_Info_For_Component
        (Comp_Kind        : Component_Kind;
         Comp_Name        : String;
         Comp             : String;
         Comp_Ty          : TGen.Types.Typ'Class;
         Read_Tag         : out Unbounded_String;
         Read_Indexed_Tag : out Unbounded_String;
         Write_Tag        : out Unbounded_String;
         Ancestor_WT      : out Unbounded_String;
         Comp_B2J_Tag     : out Unbounded_String;
         Comp_J2B_Tag     : out Unbounded_String;
         Spacing          : Natural);
      --  Generate the parts of the subprograms Read and Write
      --  for a component Comp_Name of type Comp_Ty. Also generate base
      --  functions for Comp_Ty.
      --  Spacing is used to tabulate the generated code, see ..._Spacing
      --  above.

      procedure Collect_Info_For_Components
        (Components  : Component_Maps.Map;
         Read_Tag    : in out Vector_Tag;
         Write_Tag   : in out Vector_Tag;
         Ancestor_WT : in out Vector_Tag;
         B2J_Tag     : in out Vector_Tag;
         J2B_Tag     : in out Vector_Tag;
         Spacing     : Natural;
         Object_Name : String);
      --  Go over the components in Components and generate the parts of the
      --  subprograms Read and Write for the components.
      --  Along the way, generate base functions for the component types.
      --  Spacing is used to tabulate the generated code Object_Name is the
      --  name of the object we are traversing.

      procedure Collect_Info_For_Variants
        (V             : TGen.Types.Record_Types.Variant_Part;
         Discriminants : Component_Maps.Map;
         Read_Tag      : out Tag;
         Write_Tag     : out Tag;
         Ancestor_WT   : out Tag;
         B2J_Tag       : out Tag;
         J2B_Tag       : out Tag;
         Spacing       : Natural;
         Object_Name   : String);
      --  Instanciate the variant part templates to create strings for the
      --  operations Read and Write on a variant part V.
      --  Spacing is used to tabulate the generated code Object_Name is the
      --  name of the object we are traversing.

      --------------------------------
      -- Collect_Info_For_Component --
      --------------------------------

      procedure Collect_Info_For_Component
        (Comp_Kind        : Component_Kind;
         Comp_Name        : String;
         Comp             : String;
         Comp_Ty          : TGen.Types.Typ'Class;
         Read_Tag         : out Unbounded_String;
         Read_Indexed_Tag : out Unbounded_String;
         Write_Tag        : out Unbounded_String;
         Ancestor_WT      : out Unbounded_String;
         Comp_B2J_Tag     : out Unbounded_String;
         Comp_J2B_Tag     : out Unbounded_String;
         Spacing          : Natural)
      is
         Named_Comp_Ty    : constant TGen.Types.Typ'Class :=
           (if Comp_Ty in Anonymous_Typ'Class
            then Anonymous_Typ'Class (Comp_Ty).Named_Ancestor.all
            else Comp_Ty);
         Comp_Scalar      : constant Boolean :=
           Named_Comp_Ty in Scalar_Typ'Class;
         Comp_Prefix      : constant String :=
           Prefix_For_Typ (Named_Comp_Ty.Slug);
         Comp_Constraints : constant Tag :=
           Create_Tag_For_Constraints (Comp_Ty);
         Assocs           : constant Translate_Table :=
           Common_Assocs
           & [1 => Assoc ("COMP_PREFIX", Comp_Prefix),
              2 => Assoc ("COMPONENT", Comp),
              3 => Assoc ("CONSTRAINTS", Comp_Constraints),
              4 => Assoc ("COMP_SCALAR", Comp_Scalar),
              5 => Assoc ("COMP_NEEDS_HEADER", Needs_Header (Named_Comp_Ty)),
              6 => Assoc ("COMPONENT_KIND", Component_Kind'Image (Comp_Kind)),
              7 => Assoc ("COMPONENT_NAME", Comp_Name),
              8 => Assoc ("SPACING", RW_Spacing (Spacing))];
         Comp_Kind_Str    : constant String :=
           Component_Kind'Image (Comp_Kind);
         pragma Unreferenced (Comp_Kind_Str);
      begin
         Read_Tag := Component_Read (Assocs);
         Read_Indexed_Tag := Component_Read_Indexed (Assocs);
         Write_Tag := Component_Write (Assocs);
         Ancestor_WT :=
           Component_Write (Assocs & Assoc ("FOR_ANCESTOR", "True"));
         Comp_B2J_Tag := Component_B2J (Assocs);
         Comp_J2B_Tag := Component_J2B (Assocs);
      end Collect_Info_For_Component;

      ---------------------------------
      -- Collect_Info_For_Components --
      ---------------------------------

      procedure Collect_Info_For_Components
        (Components  : Component_Maps.Map;
         Read_Tag    : in out Vector_Tag;
         Write_Tag   : in out Vector_Tag;
         Ancestor_WT : in out Vector_Tag;
         B2J_Tag     : in out Vector_Tag;
         J2B_Tag     : in out Vector_Tag;
         Spacing     : Natural;
         Object_Name : String) is
      begin
         --  Go over the record components to fill the associations

         for Cu in Components.Iterate loop
            declare
               Comp_Ty      : constant TGen.Types.Typ'Class :=
                 Component_Maps.Element (Cu).all;
               Comp_Name    : constant String := +Component_Maps.Key (Cu);
               Read         : Unbounded_String;
               Read_Indexed : Unbounded_String;
               Write        : Unbounded_String;
               Ancestor_W   : Unbounded_String;
               Comp_B2J     : Unbounded_String;
               Comp_J2B     : Unbounded_String;
            begin
               Collect_Info_For_Component
                 (Record_Component,
                  Comp_Name,
                  Object_Name & "." & Comp_Name,
                  Comp_Ty,
                  Read,
                  Read_Indexed,
                  Write,
                  Ancestor_W,
                  Comp_B2J,
                  Comp_J2B,
                  Spacing);
               Read_Tag := Read_Tag & Read;
               Write_Tag := Write_Tag & Write;
               Ancestor_WT := Ancestor_WT & Ancestor_W;
               B2J_Tag := B2J_Tag & Comp_B2J;
               J2B_Tag := J2B_Tag & Comp_J2B;
            end;
         end loop;
      end Collect_Info_For_Components;

      ----------------------------------
      -- Collect_Info_For_Variants --
      ----------------------------------

      procedure Collect_Info_For_Variants
        (V             : TGen.Types.Record_Types.Variant_Part;
         Discriminants : Component_Maps.Map;
         Read_Tag      : out Tag;
         Write_Tag     : out Tag;
         Ancestor_WT   : out Tag;
         B2J_Tag       : out Tag;
         J2B_Tag       : out Tag;
         Spacing       : Natural;
         Object_Name   : String)
      is
         Discr_Name    : constant String := +V.Discr_Name;
         Discr_Typ     : constant TGen.Types.Typ_Access :=
           Discriminants (V.Discr_Name);
         Discr_Typ_FQN : constant String := Discr_Typ.all.FQN (No_Std => True);

         Choices_Tag       : Matrix_Tag;
         Comp_Read_Tag     : Matrix_Tag;
         Comp_Write_Tag    : Matrix_Tag;
         Ancestor_CWT      : Matrix_Tag;
         Comp_B2J_Tag      : Matrix_Tag;
         Comp_J2B_Tag      : Matrix_Tag;
         Variant_Read_Tag  : Vector_Tag;
         Variant_Write_Tag : Vector_Tag;
         Ancestor_VWT      : Vector_Tag;
         Variant_J2B_Tag   : Vector_Tag;
         Variant_B2J_Tag   : Vector_Tag;

      begin
         for V_Choice of V.Variant_Choices loop

            --  Get tags for the variant choices

            Choices_Tag :=
              Choices_Tag
              & Create_Tag_For_Intervals (V_Choice.Alt_Set, Discr_Typ.all);

            --  Handle the components

            declare
               Comp_Read   : Tag;
               Comp_Write  : Tag;
               Ancestor_CW : Tag;
               Comp_B2J    : Tag;
               Comp_J2B    : Tag;
            begin
               Collect_Info_For_Components
                 (V_Choice.Components,
                  Comp_Read,
                  Comp_Write,
                  Ancestor_CW,
                  Comp_B2J,
                  Comp_J2B,
                  Spacing     => Spacing + 1,
                  Object_Name => Object_Name);
               Comp_Read_Tag := Comp_Read_Tag & Comp_Read;
               Comp_Write_Tag := Comp_Write_Tag & Comp_Write;
               Ancestor_CWT := Ancestor_CWT & Ancestor_CW;
               Comp_B2J_Tag := Comp_B2J_Tag & Comp_B2J;
               Comp_J2B_Tag := Comp_J2B_Tag & Comp_J2B;
            end;

            --  Handle the nested variant if any

            if V_Choice.Variant = null then
               Variant_Read_Tag := Variant_Read_Tag & "";
               Variant_Write_Tag := Variant_Write_Tag & "";
               Ancestor_VWT := Ancestor_VWT & "";
            else
               declare
                  Variant_Read  : Tag;
                  Variant_Write : Tag;
                  Ancestor_VW   : Tag;
                  Variant_B2J   : Tag;
                  Variant_J2B   : Tag;
               begin
                  Collect_Info_For_Variants
                    (V_Choice.Variant.all,
                     Discriminants,
                     Variant_Read,
                     Variant_Write,
                     Ancestor_VW,
                     Variant_B2J,
                     Variant_J2B,
                     Spacing + 1,
                     Object_Name);
                  Variant_Read_Tag := Variant_Read_Tag & Variant_Read;
                  Variant_Write_Tag := Variant_Write_Tag & Variant_Write;
                  Ancestor_VWT := Ancestor_VWT & Ancestor_VW;
                  Variant_B2J_Tag := Variant_B2J_Tag & Variant_B2J;
                  Variant_J2B_Tag := Variant_J2B_Tag & Variant_J2B;
               end;
            end if;
         end loop;

         --  Instantiate the appropriate template to glue the pieces together

         declare
            Assocs : constant Translate_Table :=
              Common_Assocs
              & [1 => Assoc ("OBJECT_NAME", Object_Name),
                 2 => Assoc ("DISCR_NAME", Discr_Name),
                 3 => Assoc ("DISCR_TYP", Discr_Typ_FQN),
                 4 => Assoc ("CHOICES", Choices_Tag),
                 5 => Assoc ("SPACING", RW_Spacing (Spacing))];

         begin
            Read_Tag :=
              +Variant_Read_Write
                 (Assocs
                  & [1 => Assoc ("COMPONENT_ACTION", Comp_Read_Tag),
                     2 => Assoc ("VARIANT_PART", Variant_Read_Tag)]);
            Write_Tag :=
              +Variant_Read_Write
                 (Assocs
                  & [1 => Assoc ("COMPONENT_ACTION", Comp_Write_Tag),
                     2 => Assoc ("VARIANT_PART", Variant_Write_Tag)]);
            Ancestor_WT :=
              +Variant_Read_Write
                 (Assocs
                  & [1 => Assoc ("COMPONENT_ACTION", Ancestor_CWT),
                     2 => Assoc ("ANCESTOR_COMPONENT_ACTION", Ancestor_CWT),
                     3 => Assoc ("VARIANT_PART", Ancestor_VWT)]);
            B2J_Tag :=
              +Variant_Read_Write
                 (Assocs
                  & [1 => Assoc ("COMPONENT_ACTION", Comp_B2J_Tag),
                     2 => Assoc ("VARIANT_PART", Variant_B2J_Tag)]);
            J2B_Tag :=
              +Variant_Read_Write
                 (Assocs
                  & [1 => Assoc ("COMPONENT_ACTION", Comp_J2B_Tag),
                     2 => Assoc ("VARIANT_PART", Variant_J2B_Tag)]);
         end;
      end Collect_Info_For_Variants;

      Discr_Name_Tag           : Tag;
      First_Name_Tag           : Tag;
      Last_Name_Tag            : Tag;
      Comp_Typ_Tag             : Tag;
      Comp_Pref_Tag            : Tag;
      Is_Enum_Tag              : Tag;
      Ada_Dim_Tag              : constant Tag :=
        (if Typ in Array_Typ'Class
         then Create_Tags_For_Array_Dims (Array_Typ'Class (Typ))
         else +"");
      Ancestor_Ty_Prefix       : Tag;
      Ancestor_Ty_Name         : Tag;
      Has_Discr_Tag            : Tag;
      Ancestors_Discr_Name_Tag : Tag;
      Ancestors_Comp_Typ_Tag   : Tag;
      Ancestors_Comp_Pref_Tag  : Tag;
      Discr_Ancestor_Name_Tag  : Tag;
   begin
      --  1. Generate operations for the header if needed

      if Needs_Header (Typ) then

         --  Fill the tags for the components of the header and generate
         --  additional base functions if needed.

         if Typ in Unconstrained_Array_Typ'Class then
            declare
               U_Typ : Unconstrained_Array_Typ'Class renames
                 Unconstrained_Array_Typ'Class (Typ);

            begin
               --  Fill the association maps

               Create_Tags_For_Array_Bounds
                 (U_Typ,
                  First_Name_Tag,
                  Last_Name_Tag,
                  Comp_Typ_Tag,
                  Comp_Pref_Tag,
                  Is_Enum_Tag);
            end;

         else
            declare
               D_Typ : Record_Typ'Class renames Record_Typ'Class (Typ);
            begin
               --  Generate base functions for the discriminant types.
               --  TODO???: why is this commented out?

               --  for Cu in D_Typ.Discriminant_Types.Iterate loop
               --     Generate_Base_Functions_For_Typ
               --       (F_Spec, F_Body, Component_Maps.Element (Cu).Get);
               --  end loop;
               --  Fill the association maps

               Create_Tags_For_Discriminants
                 (D_Typ,
                  Discr_Name_Tag,
                  Comp_Typ_Tag,
                  Comp_Pref_Tag,
                  Discr_Ancestor_Name_Tag);

               --  Get all discriminants of the derivation chain separatly,
               --  except those of the current type.
               Create_Tags_For_Discriminants
                 (D_Typ,
                  Ancestors_Discr_Name_Tag,
                  Ancestors_Comp_Typ_Tag,
                  Ancestors_Comp_Pref_Tag,
                  Discr_Ancestor_Name_Tag,
                  True);

               Has_Discr_Tag :=
                 Has_Discr_Tag & not D_Typ.Discriminant_Types.Is_Empty;

               if D_Typ.Ancestor /= null then
                  Ancestor_Ty_Prefix :=
                    Ancestor_Ty_Prefix & Prefix_For_Typ (D_Typ.Ancestor.Slug);
                  Ancestor_Ty_Name :=
                    Ancestor_Ty_Name & D_Typ.Ancestor.FQN (No_Std => True);
               end if;
            end;
         end if;

         --  Generate the header

         declare
            Assocs : constant Translate_Table :=
              Common_Assocs
              & [1  => Assoc ("DISCR_NAME", Discr_Name_Tag),
                 2  => Assoc ("FIRST_NAME", First_Name_Tag),
                 3  => Assoc ("LAST_NAME", Last_Name_Tag),
                 4  => Assoc ("COMP_TYP", Comp_Typ_Tag),
                 5  => Assoc ("COMP_PREFIX", Comp_Pref_Tag),
                 6  => Assoc ("ADA_DIM", Ada_Dim_Tag),
                 7  => Assoc ("IS_ENUM", Is_Enum_Tag),
                 8  => Assoc ("ARR_LIMIT", Get_Array_Size_Limit),
                 9  => Assoc ("ANCESTOR_TY_PREFIX", Ancestor_Ty_Prefix),
                 10 => Assoc ("HAS_DISCR", Has_Discr_Tag),
                 11 =>
                   Assoc ("ANCESTORS_DISCR_NAME", Ancestors_Discr_Name_Tag),
                 12 => Assoc ("ANCESTORS_COMP_TYP", Ancestors_Comp_Typ_Tag),
                 13 =>
                   Assoc ("ANCESTORS_COMP_PREFIX", Ancestors_Comp_Pref_Tag),
                 14 => Assoc ("ANCESTOR_TY_NAME", Ancestor_Ty_Name)];
         begin
            Print_Header (Assocs);
         end;

      --  If the type does not need a header, still generate definitions for
      --  the size of the header.

      elsif not For_Base then
         Print_Default_Header (Common_Assocs);
      end if;

      --  3. Generate the body and spec of the base operations
      --  3.1. For scalar types, we generate clones. We need to provide the
      --       name of the appropriate generic unit depending on the scalar
      --       kind (Discrete, Fixed, or Float).

      if Typ in Scalar_Typ'Class then
         declare
            Generic_Name : constant String :=
              (if Typ in Discrete_Typ'Class and then not Differentiate_Discrete
               then "Read_Write_Discrete"
               elsif Typ in Signed_Int_Typ'Class
               then "Read_Write_Signed"
               elsif Typ in Mod_Int_Typ'Class
               then "Read_Write_Unsigned"
               elsif Typ in Enum_Typ'Class
               then "Read_Write_Enum"
               elsif Typ in Float_Typ'Class
               then "Read_Write_Float"
               elsif Typ in Ordinary_Fixed_Typ'Class
               then "Read_Write_Ordinary_Fixed"
               else "Read_Write_Decimal_Fixed");
            Assocs       : constant Translate_Table :=
              Common_Assocs
              & [1 => Assoc ("MARSHALLING_LIB", Marshalling_Lib),
                 2 => Assoc ("GENERIC_NAME", Generic_Name),
                 3 => Assoc ("IS_DISCRETE", Typ in Discrete_Typ'Class),
                 4 => Assoc ("FOR_BASE", For_Base)];

         begin
            Print_Scalar (Assocs, For_Base);
         end;

      --  3.2 For array types, we generate the calls for the components and
      --      we instantiate the appropriate patterns.

      elsif Typ in Array_Typ'Class then
         declare
            Comp_Ty                : constant TGen.Types.Typ'Class :=
              Array_Typ'Class (Typ).Component_Type.all;
            Named_Comp_Ty          : constant TGen.Types.Typ'Class :=
              (if Comp_Ty in Anonymous_Typ'Class
               then Anonymous_Typ'Class (Comp_Ty).Named_Ancestor.all
               else Comp_Ty);
            Component_Read         : Unbounded_String;
            Component_Read_Indexed : Unbounded_String;
            Component_Write        : Unbounded_String;
            Ancestor_CW            : Unbounded_String;
            Comp_B2J               : Unbounded_String;
            Comp_J2B               : Unbounded_String;
         begin
            --  Contruct the calls for the components
            --  Ancestor_CW is only useful for tagged records, but needs to
            --  exist here to be able to perform the following call.

            Collect_Info_For_Component
              (Array_Component,
               Global_Prefix & "_E",
               Global_Prefix & "_E",
               Comp_Ty,
               Component_Read,
               Component_Read_Indexed,
               Component_Write,
               Ancestor_CW,
               Comp_B2J,
               Comp_J2B,
               1);

            --  Generate the basic operations

            declare
               Assocs : constant Translate_Table :=
                 Common_Assocs
                 & [1  => Assoc ("COMPONENT_READ", Component_Read),
                    2  => Assoc ("COMPONENT_WRITE", Component_Write),
                    3  =>
                      Assoc ("COMP_TYP", Named_Comp_Ty.FQN (No_Std => True)),
                    4  => Assoc ("ADA_DIM", Ada_Dim_Tag),
                    5  => Assoc ("FIRST_NAME", First_Name_Tag),
                    6  => Assoc ("LAST_NAME", Last_Name_Tag),
                    7  => Assoc ("BOUND_TYP", Comp_Typ_Tag),
                    8  =>
                      Assoc ("COMPONENT_READ_INDEXED", Component_Read_Indexed),
                    9  => Assoc ("AS_ANCESTOR", Ancestor_CW),
                    10 => Assoc ("COMPONENT_B2J", Comp_B2J),
                    11 => Assoc ("COMPONENT_J2B", Comp_J2B)];

            begin
               Print_Array (Assocs);
            end;
         end;

      elsif Typ in Derived_Private_Subtype_Typ'Class then

         declare
            Derived_Typ : constant Derived_Private_Subtype_Typ :=
              Derived_Private_Subtype_Typ (Typ);
            Assocs      : constant Translate_Table :=
              Common_Assocs
              & [1 =>
                   Assoc
                     ("PARENT_TY_NAME",
                      Derived_Typ.Parent_Type.FQN (No_Std => True)),
                 2 =>
                   Assoc ("PARENT_TY_NAME_SLUG", Derived_Typ.Parent_Type.Slug),
                 3 => Assoc ("TY_SLUG", Derived_Typ.Slug),
                 4 =>
                   Assoc
                     ("PARENT_TY_PACKAGE",
                      TGen.Strings.To_Ada
                        (Derived_Typ.Parent_Type.Package_Name))];
         begin
            Print_Derived_Private_Subtype (Assocs);
         end;

      elsif Typ in Proxy_Typ'Class then
         declare
            Proxy_FN : Function_Typ renames
              Function_Typ (Proxy_Typ (Typ).Proxy_Subprogram.all);
            Assocs   : Translate_Set := To_Set (Common_Assocs);

            Param_Names  : Vector_Tag;
            --  Name of the parameters of the proxy subprogram
            Param_Types  : Vector_Tag;
            --  fully qualified names of the parameters of the proxy subprogram
            Param_Inputs : Vector_Tag;
            --  Name of the input function for each of the parameters of the
            --  proxy subprogram.
            Param_J2B    : Vector_Tag;
            Param_B2J    : Vector_Tag;
            --  Conversion function names for the parameters of the proxy
            --  subprogram.

            Global_Names  : Vector_Tag;
            --  Name of the global variables
            Global_Inputs : Vector_Tag;
            --  Name of the input function for each of the global variables
            Global_J2B    : Vector_Tag;
            Global_B2J    : Vector_Tag;
            --  Conversion function names for the parameters of the proxy
            --  subprogram.
         begin
            Insert (Assocs, Assoc ("PROXY_FN_FQN", Proxy_FN.FQN));
            Insert (Assocs, Assoc ("PROXY_UID", String'(+Proxy_FN.Subp_UID)));
            for Param_Name of Proxy_FN.Param_Order loop
               declare
                  use Component_Maps;
                  Param_Ty : constant Constant_Reference_Type :=
                    Proxy_FN.Component_Types.Constant_Reference (Param_Name);
               begin
                  Append (Param_Names, String'(+Param_Name));
                  Append
                    (Param_Types, Param_Ty.Element.all.FQN (No_Std => True));
                  Append (Param_Inputs, Input_Fname_For_Typ (Param_Ty.Name));
                  Append
                    (Param_B2J, Bin_to_JSON_Fname_For_Typ (Param_Ty.Name));
                  Append
                    (Param_J2B, JSON_to_Bin_Fname_For_Typ (Param_Ty.Name));
               end;
            end loop;
            Insert (Assocs, Assoc ("PARAM_TY", Param_Types));
            Insert (Assocs, Assoc ("PARAM_NAME", Param_Names));
            Insert (Assocs, Assoc ("PARAM_INPUT_FN", Param_Inputs));
            Insert (Assocs, Assoc ("PARAM_BIN_TO_JSON_FN", Param_B2J));
            Insert (Assocs, Assoc ("PARAM_JSON_TO_BIN_FN", Param_J2B));
            for Global_Cur in Proxy_FN.Globals.Iterate loop
               declare
                  use Component_Maps;
                  Global_Name : constant String :=
                    +Component_Maps.Key (Global_Cur);
                  Global_Ty   : constant Constant_Reference_Type :=
                    Proxy_FN.Globals.Constant_Reference (Global_Cur);
               begin
                  Append (Global_Names, Global_Name);
                  Append (Global_Inputs, Input_Fname_For_Typ (Global_Ty.Name));
                  Append
                    (Global_B2J, Bin_to_JSON_Fname_For_Typ (Global_Ty.Name));
                  Append
                    (Global_J2B, JSON_to_Bin_Fname_For_Typ (Global_Ty.Name));
               end;
            end loop;
            Insert (Assocs, Assoc ("GLOBAL_NAME", Global_Names));
            Insert (Assocs, Assoc ("GLOBAL_INPUT_FN", Global_Inputs));
            Insert (Assocs, Assoc ("GLOBAL_BIN_TO_JSON_FN", Global_B2J));
            Insert (Assocs, Assoc ("GLOBAL_JSON_TO_BIN_FN", Global_J2B));
            Print_Proxy_Read (Assocs);
         end;

      --  3.3 For record types, we generate the calls for the components and
      --      the variant part and instanciate the appropriate patterns.

      --  Record types: generate a call per component

      else
         pragma Assert (Typ in Record_Typ'Class);

         declare
            Object_Name            : constant String := Global_Prefix & "_V";
            Ancestor_Ty_Prefix     : Unbounded_String := +"";
            Ancestor_Ty_Name       : Unbounded_String := +"";
            Component_Read         : Tag;
            Component_Read_Indexed : Tag;
            Component_Write        : Tag;
            Ancestor_CW            : Tag;
            Variant_Read           : Tag;
            Variant_Write          : Tag;
            Ancestor_VW            : Tag;
            As_Ancestor            : Tag;
            Comp_B2J               : Tag;
            Comp_J2B               : Tag;
            Variant_J2B            : Tag;
            Variant_B2J            : Tag;
         begin

            if Kind (Typ) = Record_Kind
              and then Record_Typ (Typ).Ancestor /= null
            then
               declare
                  Ancestor        : constant Record_Typ_Access :=
                    Record_Typ (Typ).Ancestor;
                  Ancestor_B_Name : constant String :=
                    Ancestor.FQN (No_Std => True);
               begin
                  Ancestor_Ty_Prefix := +Prefix_For_Typ (Ancestor.Slug);
                  Ancestor_Ty_Name :=
                    +(if For_Base
                      then Ancestor_B_Name & "'Base"
                      else Ancestor_B_Name);
               end;
            end if;

            --  Construct the calls for the components

            Collect_Info_For_Components
              (Record_Typ'Class (Typ).Component_Types,
               Component_Read,
               Component_Write,
               Ancestor_CW,
               Comp_B2J,
               Comp_J2B,
               Object_Name => Object_Name,
               Spacing     => 0);

            --  Construct the calls for the variant part if any

            if Typ in Record_Typ'Class then
               declare
                  D_Typ : Record_Typ'Class renames Record_Typ'Class (Typ);
               begin
                  if D_Typ.Variant /= null then
                     Collect_Info_For_Variants
                       (D_Typ.Variant.all,
                        D_Typ.Discriminant_Types,
                        Variant_Read,
                        Variant_Write,
                        Ancestor_VW,
                        Variant_B2J,
                        Variant_J2B,
                        Object_Name => Object_Name,
                        Spacing     => 0);
                  end if;
               end;
            end if;

            As_Ancestor := As_Ancestor & True;

            --  Generate the basic operations

            declare
               Assocs : constant Translate_Table :=
                 Common_Assocs
                 & [1  => Assoc ("COMPONENT_READ", Component_Read),
                    2  => Assoc ("COMPONENT_WRITE", Component_Write),
                    3  => Assoc ("VARIANT_READ", Variant_Read),
                    4  => Assoc ("VARIANT_WRITE", Variant_Write),
                    5  => Assoc ("ANCESTOR_VARIANT_WRITE", Ancestor_VW),
                    6  => Assoc ("DISCR_NAME", Discr_Name_Tag),
                    7  => Assoc ("DISCR_TYP", Comp_Typ_Tag),
                    8  =>
                      Assoc ("COMPONENT_READ_INDEXED", Component_Read_Indexed),
                    9  => Assoc ("ANCESTOR_TY_PREFIX", Ancestor_Ty_Prefix),
                    10 => Assoc ("ANCESTOR_TY_NAME", Ancestor_Ty_Name),
                    11 => Assoc ("ANCESTOR_COMPONENT_WRITE", Ancestor_CW),
                    12 => Assoc ("AS_ANCESTOR", As_Ancestor),
                    13 => Assoc ("COMPONENT_B2J", Comp_B2J),
                    14 => Assoc ("COMPONENT_J2B", Comp_J2B),
                    15 => Assoc ("VARIANT_B2J", Variant_B2J),
                    16 => Assoc ("VARIANT_J2B", Variant_J2B)];
            begin
               Print_Record (Assocs);
            end;
         end;
      end if;

      --  4. Generate the wrappers for writing both the header and the
      --     components if necessary.

      if Needs_Wrappers (Typ) then
         declare
            Assocs : constant Translate_Table :=
              Common_Assocs
              & [1 => Assoc ("DISCR_NAME", Discr_Name_Tag),
                 2 => Assoc ("DISCR_TYP", Comp_Typ_Tag),
                 3 => Assoc ("DISCR_PREFIX", Comp_Pref_Tag)];

         begin
            Print_Header_Wrappers (Assocs);
         end;
      end if;
   end Generate_Base_Functions_For_Typ;

   --------------------
   -- Get_IO_Support --
   --------------------

   function Get_IO_Support (Typ : TGen.Types.Typ'Class) return IO_Support is
      use Component_Maps;

      function Variant_IO_Support
        (Variant_Part : Variant_Part_Acc) return IO_Support;
      --  Recursive function used to check the variant part of a discriminated
      --  record.

      ------------------------
      -- Variant_IO_Support --
      ------------------------

      function Variant_IO_Support
        (Variant_Part : Variant_Part_Acc) return IO_Support
      is
         Res : IO_Support := IO_Full;
      begin
         if Variant_Part /= null then

            --  Check each variant choice

            for V_Choice of Variant_Part.Variant_Choices loop

               --  Check components

               for Cu in V_Choice.Components.Iterate loop
                  Res := Res and Get_IO_Support (Element (Cu).all);
               end loop;

               --  Check the variant part if any

               Res := Res and Variant_IO_Support (V_Choice.Variant);
            end loop;
         end if;

         return Res;
      end Variant_IO_Support;

      Res : IO_Support := IO_Full;
      --  Used as accumulator for some type kinds

   begin
      if Typ in Scalar_Typ'Class then
         return IO_Full;
      elsif Typ in Derived_Private_Subtype_Typ then
         return
           Get_IO_Support
             (Derived_Private_Subtype_Typ'Class (Typ).Parent_Type.all);
      elsif Typ in Constrained_Array_Typ'Class then
         return
           Get_IO_Support
             (Constrained_Array_Typ'Class (Typ).Component_Type.all);
      elsif Typ in Unconstrained_Array_Typ'Class then
         return
           Get_IO_Support
             (Unconstrained_Array_Typ'Class (Typ).Component_Type.all);
      elsif Typ in Function_Typ'Class then
         declare
            FN_Typ : Function_Typ renames Function_Typ (Typ);
         begin
            Res := IO_Full;

            --  Check out and in out parameters

            for Param_Name of FN_Typ.Param_Order loop
               if FN_Typ.Param_Modes.Element (Param_Name)
                  in In_Mode | In_Out_Mode
               then
                  Res :=
                    Res
                    and Get_IO_Support
                          (FN_Typ.Component_Types.Element (Param_Name).all);
               end if;
            end loop;

            --  Check all globals

            for Global_T of FN_Typ.Globals loop
               Res := Res and Get_IO_Support (Global_T.all);
            end loop;
            return Res;
         end;
      elsif Typ in Base_Record_Typ'Class then

         --  Check specific components of discriminated records
         Res := IO_Full;

         if Typ in Record_Typ'Class then
            declare
               D_Typ : Record_Typ'Class renames Record_Typ'Class (Typ);
            begin
               --  Check that the discriminant types are supported

               for Cu in D_Typ.Discriminant_Types.Iterate loop
                  Res := Res and Get_IO_Support (Element (Cu).all);
               end loop;

               --  Check the variant parts if any

               Res := Res and Variant_IO_Support (D_Typ.Variant);
            end;
         end if;

         --  Check regular component types

         for Cu in Base_Record_Typ'Class (Typ).Component_Types.Iterate loop
            Res := Res and Get_IO_Support (Element (Cu).all);
         end loop;

         return Res;

      elsif Typ in Anonymous_Typ'Class then

         --  We don't support real constraints yet, as they are (incorrectly)
         --  handled using Long_Float by libadalang.

         if Anonymous_Typ'Class (Typ).Named_Ancestor.all in Real_Typ'Class then
            Ada.Text_IO.Put_Line ("real constraints");
            return IO_None;
         else
            return
              Get_IO_Support (Anonymous_Typ'Class (Typ).Named_Ancestor.all);
         end if;
      elsif Typ in Proxy_Typ'Class then
         --  Proxy types only support input at most (depending on the
         --  capabilities of the parameters of the proxy subprogram).
         return
           IO_Input and Get_IO_Support (Proxy_Typ (Typ).Proxy_Subprogram.all);
      else
         return IO_None;
      end if;
   end Get_IO_Support;

   -----------------------
   -- Is_Supported_Type --
   -----------------------

   function Is_Supported_Type (Typ : TGen.Types.Typ'Class) return Boolean
   is (Get_IO_Support (Typ) = IO_Full);
   --  Return True for types which are currently fully supported by TGen

   -------------------------
   -- Type_Supports_Input --
   -------------------------

   function Type_Supports_Input (Typ : TGen.Types.Typ'Class) return Boolean
   is (Get_IO_Support (Typ) in IO_Input | IO_Full);
   --  Whether TGen can generate input function for Typ

   --------------------------
   -- Type_Supports_Output --
   --------------------------

   function Type_Supports_Output (Typ : TGen.Types.Typ'Class) return Boolean
   is (Get_IO_Support (Typ) in IO_Output | IO_Full);
   --  Whether TGen can generate output functions for Typ

   ------------------
   -- Needs_Header --
   ------------------

   function Needs_Header (Typ : TGen.Types.Typ'Class) return Boolean is
      function Rec_Needs_Header (R : Record_Typ'Class) return Boolean
      is ((Is_Discriminated (R) and then not R.Constrained)
          or else (R.Ancestor /= null
                   and then Rec_Needs_Header (R.Ancestor.all)));
      --  Records can be tagged and have ancestors. If at least one of the
      --  ancestors has constraints, then Typ has constraints and return True.

   begin
      return
        Typ in Unconstrained_Array_Typ'Class
        or else (Typ in Record_Typ'Class
                 and then Rec_Needs_Header (Record_Typ'Class (Typ)));
   end Needs_Header;

   --------------------
   -- Needs_Wrappers --
   --------------------

   function Needs_Wrappers (Typ : TGen.Types.Typ'Class) return Boolean
   is (Typ in Record_Typ'Class
       and then Is_Discriminated (Record_Typ'Class (Typ))
       and then not Record_Typ'Class (Typ).Constrained
       and then Record_Typ'Class (Typ).Mutable);

   ------------------
   -- String_Value --
   ------------------

   function String_Value
     (V : TGen.Types.Big_Integer; Typ : TGen.Types.Typ'Class) return String is
   begin
      if Typ in Enum_Typ'Class then
         return
           To_Ada (Typ.Package_Name)
           & "."
           & Lit_Image (Enum_Typ'Class (Typ), V);
      else
         return Trim (To_String (V), Left);
      end if;
   end String_Value;

   --------------------------
   -- Output_Fname_For_Typ --
   --------------------------

   function Output_Fname_For_Typ (Typ_FQN : Ada_Qualified_Name) return String
   is
   begin
      return Prefix_For_Typ (To_Symbol (Typ_FQN, '_')) & "_Output";
   end Output_Fname_For_Typ;

   -------------------------
   -- Input_Fname_For_Typ --
   -------------------------

   function Input_Fname_For_Typ (Typ_FQN : Ada_Qualified_Name) return String is
   begin
      return Prefix_For_Typ (To_Symbol (Typ_FQN, '_')) & "_Input";
   end Input_Fname_For_Typ;

   -------------------------------
   -- Bin_to_JSON_Fname_For_Typ --
   -------------------------------

   function Bin_to_JSON_Fname_For_Typ
     (Typ_FQN : Ada_Qualified_Name) return String
   is (Prefix_For_Typ (To_Symbol (Typ_FQN, '_')) & "_To_JSON");

   -------------------------------
   -- Bin_to_JSON_Fname_For_Typ --
   -------------------------------

   function JSON_to_Bin_Fname_For_Typ
     (Typ_FQN : Ada_Qualified_Name) return String
   is (Prefix_For_Typ (To_Symbol (Typ_FQN, '_')) & "_To_Binary");

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Str : US_Access; Added : String) is
   begin
      Append (Str.all, Added & Ada.Characters.Latin_1.LF);
   end Put_Line;

   --------------
   -- New_Line --
   --------------

   procedure New_Line (Str : US_Access) is
   begin
      Append (Str.all, Ada.Characters.Latin_1.LF);
   end New_Line;

   --------------------------
   -- Get_Array_Size_Limit --
   --------------------------

   function Get_Array_Size_Limit return Positive
   is (Array_Length_Limit);

   --------------------------
   -- Set_Array_Size_Limit --
   --------------------------

   procedure Set_Array_Size_Limit (Limit : Positive) is
   begin
      Array_Length_Limit := Limit;
   end Set_Array_Size_Limit;

begin

   if Ada.Environment_Variables.Exists (Array_Length_Limit_Env_Var) then
      declare
         Env_Val : Positive;
      begin
         Env_Val :=
           Positive'Value
             (Ada.Environment_Variables.Value (Array_Length_Limit_Env_Var));
         Array_Length_Limit := Env_Val;
      exception
         when Constraint_Error =>
            Put_Line
              (File => Standard_Error,
               Item =>
                 "Warning: Could not interpret value of the "
                 & Array_Length_Limit_Env_Var
                 & "environment variable as"
                 & " a positive, defaulting to"
                 & Array_Length_Limit'Image);
      end;
   end if;

end TGen.Marshalling;
