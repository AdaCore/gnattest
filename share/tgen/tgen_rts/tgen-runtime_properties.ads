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

--  Information about the runtime which we can't reliably query directly from
--  runtime units.
--
--  This version of the package contains defaults appropriate for full native
--  runtimes only.

package TGen.Runtime_Properties is
   pragma Preelaborate;

   Sec_Stack_Dynamic : constant Boolean := True;
   --  Whether the secondary stack is dynamic on this runtime or not. This is
   --  not derived from the runtime sources as the information is not always
   --  present, instead the assumption is that on embedded runtimes the
   --  secondary stack is fixed size (and quite small), whereas full runtimes
   --  have a dynamic secondary stack.

end TGen.Runtime_Properties;
