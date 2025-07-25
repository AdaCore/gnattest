------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                       Copyright (C) 2022, AdaCore                        --
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

with Ada.Containers;
with Ada.Strings.Equal_Case_Insensitive;

with TGen.Strategies; use TGen.Strategies;
with TGen.Types.Record_Types;

package body TGen.Types is

   --------------------------
   -- Generic_Package_Name --
   --------------------------

   function Generic_Package_Instance_Name
     (Pack_Name : Ada_Qualified_Name) return Ada_Qualified_Name
   is
      Prefix             : constant Ada_Identifier :=
        Ada_Identifier (+"TGen_Generic_Instantiation_");
      First_Element_Name : constant Ada_Identifier :=
        Prefix & Pack_Name.First_Element;
      Result             : Ada_Qualified_Name;

      use Ada_Identifier_Vectors;
   begin
      Result.Append (First_Element_Name);
      Result.Append (Ada_Identifier (+"Instance"));
      for I in
        Extended_Index'Succ (Pack_Name.First_Index) .. Pack_Name.Last_Index
      loop
         Result.Append (Pack_Name.Element (I));
      end loop;

      return Result;
   end Generic_Package_Instance_Name;

   -----------
   -- Image --
   -----------

   function Image (Self : Typ) return String is
   begin
      return
        (if Self.Name = Ada_Identifier_Vectors.Empty_Vector
         then "Anonymous"
         else Self.Type_Name);
   end Image;

   ------------------
   -- Is_Anonymous --
   ------------------

   function Is_Anonymous (Self : Typ) return Boolean is
   begin
      return Self.Name = Ada_Identifier_Vectors.Empty_Vector;
   end Is_Anonymous;

   ----------
   -- Kind --
   ----------

   function Kind (Self : Typ) return Typ_Kind
   is (Invalid_Kind);

   -----------
   -- Image --
   -----------

   function Image (Self : Access_Typ) return String
   is (Typ (Self).Image & ": access type");

   ---------
   -- FQN --
   ---------

   function FQN
     (Self              : Typ;
      No_Std            : Boolean := False;
      Top_Level_Generic : Boolean := False) return String
   is
      Name : constant Ada_Qualified_Name :=
        (if Top_Level_Generic
         then Generic_Package_Instance_Name (Self.Name)
         else Self.Name);

      function Append_Class_Wide_If_Needed (Type_Name : String) return String
      is ((if Self.Is_Class_Wide then Type_Name & "'Class" else Type_Name));
   begin
      if not No_Std
        or else not Ada.Strings.Equal_Case_Insensitive
                      (+Unbounded_String (Name.First_Element), "standard")
      then
         return Append_Class_Wide_If_Needed (To_Ada (Name));
      end if;
      declare
         Stripped : Ada_Qualified_Name := Name;
      begin
         Stripped.Delete_First;
         return Append_Class_Wide_If_Needed (To_Ada (Stripped));
      end;
   end FQN;

   ------------------
   -- Package_Name --
   ------------------

   function Package_Name (Self : Typ) return Ada_Qualified_Name is
      Pack_Name : Ada_Qualified_Name := Self.Name.Copy;
   begin
      Pack_Name.Delete_Last;
      return Pack_Name;
   end Package_Name;

   ---------------------------
   -- Compilation_Unit_Name --
   ---------------------------

   function Compilation_Unit_Name (Self : Typ) return Ada_Qualified_Name is
      use Ada_Identifier_Vectors;
      use Ada.Containers;
      Pack_Name : Ada_Qualified_Name := Self.Name.Copy;
   begin
      Pack_Name.Delete
        (Index => Self.Last_Comp_Unit_Idx + 1,
         Count => Count_Type (Self.Name.Last_Index - Self.Last_Comp_Unit_Idx));
      return Pack_Name;
   end Compilation_Unit_Name;

   function Compilation_Unit_Name (Self : Typ) return String
   is (To_Ada (Self.Compilation_Unit_Name));

   ------------
   -- Encode --
   ------------

   function Encode (Self : Typ; Val : JSON_Value) return JSON_Value
   is (Val);

   ----------------------
   -- Default_Strategy --
   ----------------------

   function Default_Strategy (Self : Typ) return Strategy_Type'Class is
   begin
      return raise Program_Error with "Static strategy not implemented";
   end Default_Strategy;

   ---------------------------
   -- Default_Enum_Strategy --
   ---------------------------

   function Default_Enum_Strategy
     (Self : Typ) return TGen.Strategies.Enum_Strategy_Type'Class is
   begin
      return raise Program_Error with "Enumerative strategy not implemented";
   end Default_Enum_Strategy;

   -------------------------
   -- Try_Generate_Static --
   -------------------------

   function Try_Generate_Static
     (Self : Typ_Access) return TGen.Strategies.Strategy_Type'Class is
   begin
      if Self.all.Supports_Static_Gen then
         return Self.all.Default_Enum_Strategy;
      else
         return
           raise Program_Error
             with
               "Type "
               & To_Ada (Self.all.Name)
               & " does not support static generation";
      end if;
   end Try_Generate_Static;

   ----------
   -- Slug --
   ----------

   function Slug
     (Self : Typ; Top_Level_Generic : Boolean := False) return String
   is
      Name : constant Ada_Qualified_Name :=
        (if Top_Level_Generic
         then Generic_Package_Instance_Name (Self.Name)
         else Self.Name);
   begin
      return To_Symbol (Name, '_');
   end Slug;

   ------------------
   -- Free_Content --
   ------------------

   procedure Free_Content_Wide (Self : in out Typ'Class) is
   begin
      Self.Free_Content;
   end Free_Content_Wide;

   ---------------------
   -- Get_Diagnostics --
   ---------------------

   function Get_Diagnostics
     (Self : Unsupported_Typ; Prefix : String := "") return String_Vector
   is
      Diag : Unbounded_String;
   begin
      if Prefix'Length /= 0 then
         Diag := +Prefix & ": ";
      end if;
      Diag :=
        Diag
        & To_Ada (Self.Name)
        & " is not supported ("
        & (+Self.Reason)
        & ")";
      return String_Vectors.To_Vector (Diag, 1);
   end Get_Diagnostics;

   ----------------------
   -- Default_Strategy --
   ----------------------

   function Default_Strategy
     (Self : Derived_Private_Subtype_Typ)
      return TGen.Strategies.Strategy_Type'Class
   is (Self.Parent_Type.Default_Strategy);

   ---------------------------
   -- Default_Enum_Strategy --
   ---------------------------

   function Default_Enum_Strategy
     (Self : Derived_Private_Subtype_Typ)
      return TGen.Strategies.Enum_Strategy_Type'Class
   is (Self.Parent_Type.Default_Enum_Strategy);

   --------------
   --  Encode  --
   --------------

   function Encode
     (Self : Derived_Private_Subtype_Typ; Val : JSON_Value) return JSON_Value
   is (Self.Parent_Type.Encode (Val));

   ---------------------
   -- Get_Diagnostics --
   ---------------------

   function Get_Diagnostics
     (Self : Proxy_Typ; Prefix : String := "") return String_Vector
   is
      use TGen.Types.Record_Types;
      Proxy : Function_Typ renames Function_Typ (Self.Proxy_Subprogram.all);
      Res   : String_Vector := Proxy.Get_Diagnostics;
   begin
      --  A type with proxy only has diagnostics if there are any attached to
      --  the parameter types of the proxy subprogram, or if any of its
      --  parameters are of "out" mode.

      if (for some Param_Mode of Proxy.Param_Modes => Param_Mode = Out_Mode)
      then
         Res.Append
           (+"proxy subprogram "
            & Proxy.FQN
            & " has at least an out mode parameter");
      end if;
      return Res;
   end Get_Diagnostics;

   --  The generation strategies for proxy types "simply" leverage the
   --  strategies of the proxy subprogram, and alter the representation to add
   --  a header containing the hash of the proxy subprogram, to avoid
   --  catastrophic decoding errors, should the proxy subprogram change between
   --  two TGen invocation. The hash may also be useful in the future to
   --  provision for potential support for more than 1 proxy program supported
   --  at a time.

   type Proxy_Random_Strategy is new Random_Strategy_Type with record
      T           : Typ_Access;
      Proxy_Strat : Strategy_Acc;
   end record;

   overriding
   function Generate
     (S : in out Proxy_Random_Strategy; Disc_Context : Disc_Value_Map)
      return JSON_Value;

   --------------
   -- Generate --
   --------------

   overriding
   function Generate
     (S : in out Proxy_Random_Strategy; Disc_Context : Disc_Value_Map)
      return JSON_Value
   is
      Res       : constant JSON_Value := Create_Object;
      Proxy_Fun : TGen.Types.Record_Types.Function_Typ renames
        TGen.Types.Record_Types.Function_Typ
          (Proxy_Typ (S.T.all).Proxy_Subprogram.all);
   begin
      Res.Set_Field ("proxy_uid", Create (Proxy_Fun.Subp_UID));
      Res.Set_Field ("proxy_values", S.Proxy_Strat.Generate (Disc_Context));
      return Res;
   end Generate;

   ----------------------
   -- Default_Strategy --
   ----------------------

   function Default_Strategy
     (Self : Proxy_Typ) return TGen.Strategies.Strategy_Type'Class
   is
      Proxy_Strat : constant Strategy_Type'Class :=
        Self.Proxy_Subprogram.Default_Strategy;
   begin
      return
        Proxy_Random_Strategy'
          (T           => Self'Unrestricted_Access,
           Proxy_Strat => new Strategy_Type'Class'(Proxy_Strat));
   end Default_Strategy;

   type Proxy_Enum_Strategy is new Enum_Strategy_Type with record
      T           : Typ_Access;
      Proxy_Strat : Enum_Strategy_Type_Acc;
   end record;

   overriding
   procedure Init (S : in out Proxy_Enum_Strategy);
   --  Initializes the enum strategy of the proxy subprogram

   overriding
   function Has_Next (S : Proxy_Enum_Strategy) return Boolean;
   --  Simply returns whether the proxy subprogram's strategy has a next
   --  element to be generated.

   overriding
   function Generate
     (S : in out Proxy_Enum_Strategy; Disc_Context : Disc_Value_Map)
      return JSON_Value;

   ----------
   -- Init --
   ----------

   overriding
   procedure Init (S : in out Proxy_Enum_Strategy) is
   begin
      S.Proxy_Strat.Init;
   end Init;

   --------------
   -- Has_Next --
   --------------

   overriding
   function Has_Next (S : Proxy_Enum_Strategy) return Boolean
   is (S.Proxy_Strat.Has_Next);

   --------------
   -- Generate --
   --------------

   overriding
   function Generate
     (S : in out Proxy_Enum_Strategy; Disc_Context : Disc_Value_Map)
      return JSON_Value
   is
      Res       : constant JSON_Value := Create_Object;
      Proxy_Fun : TGen.Types.Record_Types.Function_Typ renames
        TGen.Types.Record_Types.Function_Typ
          (Proxy_Typ (S.T.all).Proxy_Subprogram.all);
   begin
      Res.Set_Field ("proxy_uid", Create (Proxy_Fun.Subp_UID));
      Res.Set_Field ("proxy_values", S.Proxy_Strat.Generate (Disc_Context));
      return Res;
   end Generate;

   ---------------------------
   -- Default_Enum_Strategy --
   ---------------------------

   function Default_Enum_Strategy
     (Self : Proxy_Typ) return TGen.Strategies.Enum_Strategy_Type'Class
   is
      Proxy_Strat : constant Enum_Strategy_Type'Class :=
        Self.Proxy_Subprogram.Default_Enum_Strategy;
   begin
      return
        Proxy_Enum_Strategy'
          (T           => Self'Unrestricted_Access,
           Proxy_Strat => new Enum_Strategy_Type'Class'(Proxy_Strat));
   end Default_Enum_Strategy;

   ------------
   -- Encode --
   ------------

   function Encode (Self : Proxy_Typ; Val : JSON_Value) return JSON_Value is
      Res : constant JSON_Value := Create_Object;
   begin
      Res.Set_Field ("proxy_uid", JSON_Value'(Val.Get ("proxy_uid")));
      Res.Set_Field
        ("proxy_values",
         Self.Proxy_Subprogram.Encode (Val.Get ("proxy_values")));
      return Res;
   end Encode;

end TGen.Types;
