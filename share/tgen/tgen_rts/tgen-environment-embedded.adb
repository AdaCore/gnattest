------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                       Copyright (C) 2026, AdaCore                        --
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

--  Default implementation for runtimes without Ada.Environment_Variables
--  (embedded/cross runtimes): every variable is reported as unset, so callers
--  fall back to their defaults. This file is the body of TGen.Environment; it
--  is mapped to that unit through a Naming clause in tgen_rts.gpr (its file
--  name does not follow the default GNAT convention on purpose, so the native
--  body tgen-environment.adb remains the default one).

package body TGen.Environment is

   ------------
   -- Exists --
   ------------

   function Exists (Name : String) return Boolean is
      pragma Unreferenced (Name);
   begin
      return False;
   end Exists;

   -----------
   -- Value --
   -----------

   function Value (Name : String; Default : String := "") return String is
      pragma Unreferenced (Name);
   begin
      return Default;
   end Value;

end TGen.Environment;
