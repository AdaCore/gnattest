------------------------------------------------------------------------------
--                                                                          --
--                             Libadalang Tools                             --
--                                                                          --
--                       Copyright (C) 2021, AdaCore                        --
--                                                                          --
-- Libadalang Tools  is free software; you can redistribute it and/or modi- --
-- fy  it  under  terms of the  GNU General Public License  as published by --
-- the Free Software Foundation;  either version 3, or (at your option) any --
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

--  This package contains high-level interfaces to project files needed to
--  process aggregate projects.
--
--  There are two different cases here:
--
--  When processing aggregate projects, the tool is spawned from itself
--  to process the next aggregated project, passing the latter through the
--  '--aggregated-project-file prj' command line switch. 'prj' is the name of
--  an aggregated project to be processed by this run.

package Utils.Projects.Aggregate is

   procedure Collect_Aggregated_Projects (P : GPR2.Project.Tree.Object);
   --  Stores (in internal data structures) the full paths to the
   --  (non-aggregate!) projects that have been aggregated by P

   procedure Process_Aggregated_Projects (Cmd : Command_Line);
   --  Iterates through the projects being aggregated and spawns the tool
   --  for each of them.

end Utils.Projects.Aggregate;
