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

with Ada.Characters.Handling;
with Ada.Text_IO;

with TGen.Environment;

package body TGen.Logging is

   ------------------
   -- Create_Trace --
   ------------------

   function Create_Trace
     (Unit_Name : Ada.Strings.Unbounded.Unbounded_String) return TGen_Trace
   is (TGen_Trace'(Unit_Name => Unit_Name));

   -----------
   -- Trace --
   -----------

   procedure Trace (Self : TGen_Trace; Message : String) is
      use Ada.Strings.Unbounded;
      use Ada.Characters.Handling;
   begin
      --  Skip tracing unless `TGEN_RTS_TRACE` is set to an enabling value. On
      --  runtimes without environment-variable support, TGen.Environment
      --  reports the variable as unset, so tracing is a no-op (which also
      --  keeps the standard output clean for other consumers, e.g. the JSON
      --  generation stream on target).

      if To_Lower (TGen.Environment.Value ("TGEN_RTS_TRACE"))
         not in "1" | "true"
      then
         return;
      end if;

      Ada.Text_IO.Put_Line
        ("["
         & TGen_Trace_Prefix
         & To_String (Self.Unit_Name)
         & "] "
         & Message);
   end Trace;

end TGen.Logging;
