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
--
--  Provides translation utilities for types represented by Libadalang nodes
--  to TGen's internal type representation.

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Doubly_Linked_Lists;

with Libadalang.Analysis;

with TGen.Libgen;

package TGen.Types.Translation is
   subtype Proxy_Policy is TGen.Libgen.Proxy_Autodetect_Policy;
   use type Proxy_Policy;

   package LAL renames Libadalang.Analysis;

   type Translation_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Res : Typ_Access;

         when False =>
            Diagnostics : Unbounded_String :=
              To_Unbounded_String ("Error during translation");
      end case;
   end record;

   type Translation_Ctx is private;

   function Make_Translation_Context
     (Verbose         : Boolean := False;
      Proxy_Detection : Proxy_Policy := TGen.Libgen.Unit;
      Relevant_Units  : TGen.Libgen.Get_Relevant_Units_CB := null)
      return Translation_Ctx;
   --  Create a Translation_Context object with adequate default values

   function Translate
     (N : LAL.Type_Expr; Ctx : in out Translation_Ctx)
      return Translation_Result;
   --  Translate N to TGen's internal type representation

   function Translate
     (N : LAL.Base_Type_Decl; Ctx : in out Translation_Ctx)
      return Translation_Result;
   --  Translate N to TGen's internal type representation

   function Translate
     (N : LAL.Basic_Decl; Ctx : in out Translation_Ctx)
      return Translation_Result;

   package Translation_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Ada_Qualified_Name,
        Element_Type    => TGen.Types.Typ_Access,
        Hash            => TGen.Strings.Hash2,
        Equivalent_Keys => TGen.Strings.Ada_Identifier_Vectors."=",
        "="             => TGen.Types."=");

   Translation_Cache : Translation_Maps.Map;
   --  Cache used for the memoization of Translate.

   package Type_Decl_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Ada_Qualified_Name,
        Element_Type    => LAL.Base_Type_Decl,
        Hash            => TGen.Strings.Hash2,
        Equivalent_Keys => TGen.Strings.Ada_Identifier_Vectors."=",
        "="             => Libadalang.Analysis."=");

   Type_Decl_Cache : Type_Decl_Maps.Map;
   --  Cache to be able to find the LAL base type decl node from the fully
   --  qualified name.

   procedure Print_Cache_Stats;
   --  Print translation cache statistics on the standard output

   procedure PP_Cache;
   --  Print the content of the translation cache on the standard output

   procedure Clear_Cache;
   --  Clear the translation cache

private

   package Ada_Qualified_Name_Stacks is new
     Ada.Containers.Doubly_Linked_Lists
       (Element_Type => Ada_Qualified_Name,
        "="          => Ada_Identifier_Vectors."=");

   type Translation_Ctx is record
      Verbose : Boolean := False;

      Translation_Stack : Ada_Qualified_Name_Stacks.List;
      --  Name of types which are currently being translated. This is used to
      --  prevent using a subprogram as a proxy which would introduce a
      --  recursive loop for unmarshalling.
      --
      --  For instance, if we have the following:
      --
      --    type Node;
      --    type Node_Acc is access Node;
      --    type Node is record
      --       Parent : Node_Acc;
      --    end record;
      --
      --    function Get_Parent (N : Node) return Node_Acc;
      --
      --  Trying to use Get_Parent as a proxy for Node_Acc would cause a
      --  infinite recursive calls when unmarshalling a Node_Acc element, as to
      --  call Get_Parent, TGen would need to read a value of type Node, which
      --  would need to call Get_Parent to create the `Parent` field, etc..
      --
      --  The list structure is useful to be able to re-create the circularity
      --  chain for diagnostics (not implemented yet).

      Skip_Proxy_Set : Ada_Qualified_Name_Set;
      --  Names of types for which we should ignore the proxy aspect, and avoid
      --  searching a proxy if unsupported.

      Proxy_Detection : Proxy_Policy;
      --  To which extend proxy subprograms should be searched for, for
      --  unsupported types.

      Unit_List_CB : TGen.Libgen.Get_Relevant_Units_CB := null;
   end record;
   --  Context for translating type declarations from LAL to TGen's internal
   --  representation. It should be passed down at least to all subprograms
   --  which may call a `Translate*` variant.

   function Make_Translation_Context
     (Verbose         : Boolean := False;
      Proxy_Detection : Proxy_Policy := TGen.Libgen.Unit;
      Relevant_Units  : TGen.Libgen.Get_Relevant_Units_CB := null)
      return Translation_Ctx
   is ((Verbose           => Verbose,
        Translation_Stack => Ada_Qualified_Name_Stacks.Empty_List,
        Skip_Proxy_Set    => Ada_Qualified_Name_Sets.Empty_Set,
        Proxy_Detection   => Proxy_Detection,
        Unit_List_CB      => Relevant_Units));

   Anonymous_Typ_Index : Positive := 1;
   --  Index incremented each time we create an anonymous type, to uniquely
   --  identify every anonymous type created.

end TGen.Types.Translation;
