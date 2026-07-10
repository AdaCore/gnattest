------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                      Copyright (C) 2021-2022, AdaCore                    --
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

with Ada.Characters.Handling;

with Libadalang.Common; use Libadalang.Common;
with Libadalang.Target_Info;

package body TGen.LAL_Utils is

   -----------------------
   -- To_Qualified_Name --
   -----------------------

   function To_Qualified_Name
     (Name : Libadalang.Analysis.Name) return Ada_Qualified_Name is
   begin
      return Result : Ada_Qualified_Name do
         case Ada_Name (Name.Kind) is
            when Ada_Dotted_Name     =>
               declare
                  DN     : constant Libadalang.Analysis.Dotted_Name :=
                    Name.As_Dotted_Name;
                  Suffix : constant Ada_Qualified_Name :=
                    To_Qualified_Name (DN.F_Suffix.As_Name);
               begin
                  Result := To_Qualified_Name (DN.F_Prefix);
                  Result.Append (Suffix);
               end;

            when Ada_Single_Tok_Node =>
               declare
                  Identifier : constant TGen.Strings.Ada_Identifier :=
                    To_Unbounded_String (Image (Name.Text));
               begin
                  Result.Append (Identifier);
               end;

            when others              =>
               raise Constraint_Error
                 with "no qualified name for " & Name.Kind'Image & " nodes";
         end case;
      end return;
   end To_Qualified_Name;

   ----------------------------
   -- Convert_Qualified_Name --
   ----------------------------

   function Convert_Qualified_Name
     (Text_QN : Libadalang.Analysis.Unbounded_Text_Type_Array)
      return Ada_Qualified_Name
   is
      Res : Ada_Qualified_Name;
   begin
      for Ident of Text_QN loop
         Res.Append (To_Unbounded_String (Image (To_Text (Ident))));
      end loop;
      return Res;
   end Convert_Qualified_Name;

   function Subp_Hash
     (Subp : Libadalang.Analysis.Basic_Decl) return GNAT.SHA1.Message_Digest
   is (GNAT.SHA1.Digest
         (Langkit_Support.Text.Image (Subp.P_Unique_Identifying_Name)));

   ------------------------
   -- JSON_Test_Filename --
   ------------------------

   function JSON_Test_Filename
     (Subp : Libadalang.Analysis.Basic_Decl) return String
   is
      Comp_Unit : constant Libadalang.Analysis.Compilation_Unit :=
        Subp.P_Enclosing_Compilation_Unit;
   begin
      return
        To_JSON_filename
          (Convert_Qualified_Name
             (Comp_Unit.P_Syntactic_Fully_Qualified_Name));
   end JSON_Test_Filename;

   --------------------------------
   -- Default_Blob_Test_Filename --
   --------------------------------

   function Default_Blob_Test_Filename
     (Subp : Libadalang.Analysis.Basic_Decl) return String
   is
      FQN : Ada_Qualified_Name :=
        To_Qualified_Name (Subp.P_Defining_Name.F_Name);
   begin
      --  Having a filename with double quotes inside is a recipe for disaster,
      --  so map the operator name if Subp is one.

      if Is_Operator (+(Unbounded_String (FQN.Last_Element))) then
         FQN.Replace_Element
           (FQN.Last_Index,
            To_Unbounded_String
              (Map_Operator_Name
                 (To_String (Unbounded_String (FQN.Last_Element)))));
      end if;
      FQN.Append (To_Unbounded_String (Subp_Hash (Subp)));
      return To_Filename (FQN);
   end Default_Blob_Test_Filename;

   -----------------------------------------
   -- Ultimate_Enclosing_Compilation_Unit --
   -----------------------------------------

   function Ultimate_Enclosing_Compilation_Unit
     (Subp : LAL.Basic_Decl'Class) return LAL.Basic_Decl
   is
      use Libadalang.Analysis;
      Instantiation_Chain : constant LAL.Generic_Instantiation_Array :=
        Subp.P_Generic_Instantiations;
   begin

      --  For anonymous type return the enclosing compilation unit of the
      --  last element in the instantiation chain (the instantiated type).

      if Instantiation_Chain'Length > 0
        and then Subp.Kind in Ada_Anonymous_Type_Decl_Range
      then
         return
           LAL.P_Enclosing_Compilation_Unit
             (if Instantiation_Chain'Length > 0
              then Instantiation_Chain (Instantiation_Chain'Last)
              else Subp)
             .P_Decl;
      end if;

      --  Walk the instantiation chain (innermost first, outermost last) and
      --  return the first instantiation whose enclosing compilation unit FQN
      --  is a prefix of the subprogram's own FQN. This handles both the
      --  simple case (top-level generic instantiation: the outermost entry
      --  matches) and the child-generic case (the outermost entry's CU may
      --  not be a prefix when the chain spans multiple compilation units).

      declare
         Subp_FQN : constant LAL.Unbounded_Text_Type_Array :=
           Subp.P_Fully_Qualified_Name_Array;
      begin
         for Inst of Instantiation_Chain loop
            declare
               CU_Decl : constant LAL.Basic_Decl :=
                 LAL.P_Enclosing_Compilation_Unit (Inst).P_Decl;
               CU_FQN  : constant LAL.Unbounded_Text_Type_Array :=
                 CU_Decl.P_Fully_Qualified_Name_Array;
            begin
               if CU_FQN'Length <= Subp_FQN'Length
                 and then Subp_FQN
                            (Subp_FQN'First
                             .. Subp_FQN'First + CU_FQN'Length - 1)
                          = CU_FQN
               then
                  return CU_Decl;
               end if;
            end;
         end loop;
      end;
      return Subp.P_Enclosing_Compilation_Unit.P_Decl;
   end Ultimate_Enclosing_Compilation_Unit;

   -------------------------------------------
   -- Get_Top_Level_Instantiation_File_Name --
   -------------------------------------------

   function Top_Level_Instantiation_Test_File_Name
     (Unit_Full_Name : String) return String
   is
      Tmp : Ada_Qualified_Name;
   begin
      Tmp.Append
        (TGen.Strings.Ada_Identifier'(To_Unbounded_String (Unit_Full_Name)));
      return
        Ada.Characters.Handling.To_Lower
          ("tgen_" & To_Symbol (Tmp, Sep => '_') & ".json");
   end Top_Level_Instantiation_Test_File_Name;

   --------------------------
   --  Derive_Opaque_Type  --
   --------------------------

   function Derive_Opaque_Type
     (Ty_Decl : LAL.Base_Type_Decl'Class) return Boolean
   is
      Decl : LAL.Base_Type_Decl'Class := Ty_Decl;
   begin
      while (Decl.Kind = Ada_Concrete_Type_Decl
             and then Decl.As_Concrete_Type_Decl.F_Type_Def.Kind
                      = Ada_Derived_Type_Def)
        or Decl.Kind in Ada_Subtype_Decl_Range
      loop
         if Decl.Kind = Ada_Concrete_Type_Decl then
            Decl :=
              LAL.Base_Type_Decl'Class
                (Decl
                   .As_Concrete_Type_Decl
                   .F_Type_Def
                   .As_Derived_Type_Def
                   .F_Subtype_Indication
                   .P_Designated_Type_Decl);
         else
            Decl :=
              LAL.Base_Type_Decl'Class
                (Decl.As_Subtype_Decl.F_Subtype.P_Designated_Type_Decl);
         end if;
      end loop;

      return not Decl.P_Private_Completion.Is_Null;
   end Derive_Opaque_Type;

   --------------------------
   -- Is_Formal_Expression --
   --------------------------

   function Is_Formal_Expression (E : LAL.Expr'Class) return Boolean is

      use LAL;

      function Formal_Visitor (Node : LAL.Ada_Node'Class) return Visit_Status;
      --  Visitor to look for formals in an expression.

      --------------------
      -- Formal_Visitor --
      --------------------

      function Formal_Visitor (Node : LAL.Ada_Node'Class) return Visit_Status
      is
      begin
         --  We want to forbid usages of generic formal parameters in pre and
         --  post conditions.

         if Node.Kind in Ada_Name
           and then not Node.As_Name.P_Referenced_Decl.Is_Null
           and then Node.As_Name.P_Referenced_Decl.P_Is_Formal
         then
            return Stop;
         end if;

         return Into;
      end Formal_Visitor;
   begin

      --  The node is not generic. No need to check further.

      if E.P_Generic_Instantiations'Length = 0 then
         return False;
      end if;

      return
        Traverse (E.P_Get_Uninstantiated_Node, Formal_Visitor'Access) = Stop;

   end Is_Formal_Expression;

   -------------------------
   -- Is_Ghost_Expression --
   -------------------------

   function Is_Ghost_Expression (E : LAL.Expr'Class) return Boolean is

      use LAL;

      function Is_Ghost_Decl (Decl : LAL.Basic_Decl'Class) return Boolean;
      --  Whether Decl is ghost code. Decl.P_Is_Ghost_Code cannot be called
      --  directly on declarations with several defining names (e.g.
      --  `X, Y : Integer;`), as it raises a precondition failure in this
      --  case: check each defining name individually instead.

      function Ghost_Visitor (Node : LAL.Ada_Node'Class) return Visit_Status;
      --  Visitor to look for references to ghost entities in an expression.

      -------------------
      -- Is_Ghost_Decl --
      -------------------

      function Is_Ghost_Decl (Decl : LAL.Basic_Decl'Class) return Boolean is
      begin
         if Is_Null (Decl.P_Defining_Name) then
            return Decl.P_Is_Ghost_Code;
         else
            return
              (for all Name of Decl.P_Defining_Names => Name.P_Is_Ghost_Code);
         end if;
      exception
         when Property_Error =>

            --  Some declarations (e.g. predefined operators and other
            --  compiler-synthesized entities) do not support aspect-related
            --  queries. They can never be marked Ghost by the user, so treat
            --  them as non-ghost.

            return False;
      end Is_Ghost_Decl;

      -------------------
      -- Ghost_Visitor --
      -------------------

      function Ghost_Visitor (Node : LAL.Ada_Node'Class) return Visit_Status is
      begin
         --  We want to forbid usages of ghost entities in pre and post
         --  conditions, as ghost entities cannot be referenced outside of
         --  ghost code or assertion expressions.

         if Node.Kind in Ada_Name
           and then not Node.As_Name.P_Referenced_Decl.Is_Null
           and then Is_Ghost_Decl (Node.As_Name.P_Referenced_Decl)
         then
            return Stop;
         end if;

         return Into;
      end Ghost_Visitor;
   begin
      return Traverse (E, Ghost_Visitor'Access) = Stop;
   end Is_Ghost_Expression;

   -------------------------
   -- Max_Float_Precision --
   -------------------------

   function Max_Float_Precision
     (N : Libadalang.Analysis.Ada_Node'Class) return Positive
   is
      use Libadalang.Analysis;
      use Libadalang.Target_Info;

      Target_Properties : constant Target_Information :=
        N.Unit.Context.Get_Target_Information;
      D_Properties      : Floating_Point_Type_Information renames
        Target_Properties.Floating_Point_Types (Double_Id);
      LD_Properties     : Floating_Point_Type_Information renames
        Target_Properties.Floating_Point_Types (Long_Double_Id);
   begin

      if not LD_Properties.Present
        or else Target_Properties.Long_Long_Long_Size < LD_Properties.Size
      then
         return Positive (D_Properties.Digs);
      else
         return Positive (LD_Properties.Digs);
      end if;
   end Max_Float_Precision;

end TGen.LAL_Utils;
