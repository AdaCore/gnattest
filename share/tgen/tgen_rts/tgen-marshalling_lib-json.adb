------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                    Copyright (C) 2022-2025, AdaCore                      --
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

with TGen.Big_Reals;     use TGen.Big_Reals;
with TGen.Big_Reals_Aux; use TGen.Big_Reals_Aux;
with TGen.Runtime_Properties;

with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

package body TGen.Marshalling_Lib.JSON is

   function Trim_Leading_Space (S : String) return String
   is (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   --  This is not in TGen.Strings in order not to pull the unit into the
   --  closure for marshalling only scenarios.

   ------------------------------
   -- Read_Write_Discrete_JSON --
   ------------------------------

   package body Read_Write_Discrete_JSON is
      use Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
      --  We need to encode characters as UTF8 strings, as JSON only supports
      --  UTF-8 encoded strings.

      -----------
      -- Write --
      -----------

      procedure Write (JSON : in out TGen.JSON.JSON_Value; V : T) is
      begin
         JSON := Create (Encode (T'Wide_Wide_Image (V)));
      end Write;

      ----------
      -- Read --
      ----------

      procedure Read (JSON : TGen.JSON.JSON_Value; V : out T) is
      begin
         V := T'Wide_Wide_Value (Decode (Get (JSON)));
      end Read;

   end Read_Write_Discrete_JSON;

   -----------------------------------
   -- Read_Write_Decimal_Fixed_JSON --
   -----------------------------------

   package body Read_Write_Decimal_Fixed_JSON is

      package T_Conversions is new Decimal_Fixed_Conversions (Num => T);
      --  To avoid the loss of precision, we encode the fixed point as a
      --  Big_Real and then represent it as a fraction, except on runtimes not
      --  supporting dynamic secondary stack (quotient strings are usually too
      --  long).

      -----------
      -- Write --
      -----------

      pragma Warnings (Off, "formal parameter * is read but never assigned");
      procedure Write (JSON : in out TGen.JSON.JSON_Value; V : T) is
      begin
         if TGen.Runtime_Properties.Sec_Stack_Dynamic then
            Set_Field (JSON, "quotient", True);
            Set_Field
              (JSON,
               "value",
               To_Quotient_String (T_Conversions.To_Big_Real (V)));
         else
            Set_Field (JSON, "quotient", False);
            Set_Field (JSON, "value", Trim_Leading_Space (V'Image));
         end if;
      end Write;
      pragma Warnings (On, "formal parameter * is read but never assigned");

      ----------
      -- Read --
      ----------

      procedure Read (JSON : TGen.JSON.JSON_Value; V : out T) is
         Has_Quotient : constant Boolean := Get (JSON, "quotient");
         Value        : constant JSON_Value := Get (JSON, "value");
      begin
         if Has_Quotient then

            --  Decode the big real from the string encoded as a quotient
            --  string.

            V :=
              T_Conversions.From_Big_Real
                (Big_Reals.From_Quotient_String (Get (Value)));
         else
            V := T'Value (Get (Value));
         end if;
      end Read;

   end Read_Write_Decimal_Fixed_JSON;

   ------------------------------------
   -- Read_Write_Ordinary_Fixed_JSON --
   ------------------------------------

   package body Read_Write_Ordinary_Fixed_JSON is

      package T_Conversions is new TGen.Big_Reals.Fixed_Conversions (Num => T);
      --  To avoid the loss of precision, we encode the fixed point as a
      --  Big_Real and then represent it as a fraction, unless the runtime does
      --  not support dynamic secondary stack (quotient string can be very
      --  long).

      -----------
      -- Write --
      -----------

      pragma Warnings (Off, "formal parameter * is read but never assigned");
      procedure Write (JSON : in out TGen.JSON.JSON_Value; V : T) is
      begin
         if TGen.Runtime_Properties.Sec_Stack_Dynamic then
            Set_Field (JSON, "quotient", True);
            Set_Field
              (JSON,
               "value",
               To_Quotient_String (T_Conversions.To_Big_Real (V)));
         else
            Set_Field (JSON, "quotient", False);
            Set_Field (JSON, "value", Trim_Leading_Space (V'Image));
         end if;
      end Write;
      pragma Warnings (On, "formal parameter * is read but never assigned");

      ----------
      -- Read --
      ----------

      procedure Read (JSON : TGen.JSON.JSON_Value; V : out T) is
         Has_Quotient : constant Boolean := Get (JSON, "quotient");
      begin
         if Has_Quotient then

            --  Decode the big real from the string encoded as a quotient
            --  string.

            V :=
              T_Conversions.From_Big_Real
                (Big_Reals.From_Quotient_String (Get (JSON, "value")));
         else
            V := T'Value (Get (JSON, "value"));
         end if;
      end Read;

   end Read_Write_Ordinary_Fixed_JSON;

   ---------------------------
   -- Read_Write_Float_JSON --
   ---------------------------

   package body Read_Write_Float_JSON is

      package T_Conversions is new TGen.Big_Reals.Float_Conversions (Num => T);
      --  To avoid the loss of precision, we need to encode the float as a
      --  Big_Real and then represent it as a fraction, unless the runtime does
      --  not support dynamic secondary stack (quotient strings get very large)

      -----------
      -- Write --
      -----------

      pragma Warnings (Off, "formal parameter * is read but never assigned");
      procedure Write (JSON : in out TGen.JSON.JSON_Value; V : T) is
      begin
         if TGen.Runtime_Properties.Sec_Stack_Dynamic then
            Set_Field (JSON, "quotient", True);
            Set_Field
              (JSON,
               "value",
               To_Quotient_String (T_Conversions.To_Big_Real (V)));
         else
            Set_Field (JSON, "quotient", False);
            Set_Field (JSON, "value", Trim_Leading_Space (V'Image));
         end if;
      end Write;
      pragma Warnings (On, "formal parameter * is read but never assigned");

      ----------
      -- Read --
      ----------

      procedure Read (JSON : TGen.JSON.JSON_Value; V : out T) is
         Is_Quotient : constant Boolean := Get (JSON, "quotient");
      begin
         if Is_Quotient then
            --  Decode the big real from the string encoded as a quotient
            --  string
            V :=
              T_Conversions.From_Big_Real
                (Big_Reals.From_Quotient_String (Get (JSON, "value")));
         else
            V :=
              T_Conversions.From_Big_Real
                (Big_Reals.From_String (Get (JSON, "value")));
         end if;
      end Read;

   end Read_Write_Float_JSON;

   -----------------
   -- In_Out_JSON --
   -----------------

   package body In_Out_JSON is

      -----------
      -- Input --
      -----------

      function Input (JSON : TGen.JSON.JSON_Value) return T is
      begin
         return V : T do
            Read (JSON, V);
         end return;
      end Input;

      ------------
      -- Output --
      ------------

      function Output (V : T) return TGen.JSON.JSON_Value is
         JSON : TGen.JSON.JSON_Value := Create_Object;
      begin
         Write (JSON, V);
         return JSON;
      end Output;

   end In_Out_JSON;

   -------------------------------
   -- In_Out_Unconstrained_JSON --
   -------------------------------

   package body In_Out_Unconstrained_JSON is

      -----------
      -- Input --
      -----------

      function Input (JSON : TGen.JSON.JSON_Value) return T is
         H : constant Header := Input_Header (JSON);
      begin
         return V : T := Init (H) do
            Read (JSON, V);
         end return;
      end Input;

      ------------
      -- Output --
      ------------

      function Output (V : T) return TGen.JSON.JSON_Value is
         JSON : TGen.JSON.JSON_Value := Create_Object;
      begin
         pragma Warnings (Off);
         Output_Header (JSON, V);
         pragma Warnings (On);
         Write (JSON, V);
         return JSON;
      end Output;

   end In_Out_Unconstrained_JSON;

end TGen.Marshalling_Lib.JSON;
