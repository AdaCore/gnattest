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

--  Optional access to process environment variables. TGen only reads a handful
--  of environment variables, all of them optional tuning/debug knobs with a
--  well-defined default behaviour when unset. This package abstracts that
--  access so the generation side stays buildable on runtimes that do not
--  provide Ada.Environment_Variables (embedded/cross runtimes): two bodies are
--  provided and selected in tgen_rts.gpr:
--
--    * the native body reads the actual process environment
--      (Ada.Environment_Variables);
--    * the default body (used on non-native runtimes) always reports variables
--      as unset, so every caller falls back to its default.

package TGen.Environment is

   function Exists (Name : String) return Boolean;
   --  Whether the environment variable Name is set. Always False when the
   --  runtime has no environment-variable support.

   function Value (Name : String; Default : String := "") return String;
   --  Value of the environment variable Name, or Default if it is unset (or if
   --  the runtime has no environment-variable support).

end TGen.Environment;
