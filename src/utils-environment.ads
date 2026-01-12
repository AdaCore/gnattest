------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                       Copyright (C) 2021, AdaCore                        --
--                                                                          --
-- GNATtest  is  free  software; you  can  redistribute  it  and/or  modify --
-- it  under  terms of the  GNU  General  Public  License  as  published by --
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

--  This package contains routines for creating, maintaining and cleaning up
--  the working environment for the tool

with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with GNAT.OS_Lib;               use GNAT.OS_Lib;

with Utils.String_Utilities; use Utils.String_Utilities;
use Utils.String_Utilities.String_Vectors;

package Utils.Environment is

   procedure Create_Temp_Dir (Obj_Dir : String := "");
   --  Creates the temporary directory for all the compilations performed by
   --  the tool. Raises Fatal_Error if creating of the temporary directory
   --  failed because of any reason. Sets Utils.Environment.Tool_Temp_Dir.
   --  If a non-empty Obj_Dir is specified, temporary directory is created
   --  inside the Obj_Dir.

   procedure Clean_Up;
   --  Performs the general final clean-up actions, including closing and
   --  deleting of all files in the temporary directory and deleting this
   --  temporary directory itself.

   Extra_Inner_Pre_Args, Extra_Inner_Post_Args : String_Vector;
   --  In Incremental_Mode, these may be used by the outer invocation of the
   --  tool to pass information to the inner invocations. The Pre ones go
   --  first; the Post ones go last.

   Initial_Dir : constant String := Normalize_Pathname (Get_Current_Dir);
   --  This is the current directory at the time the current process started.

   Tool_Temp_Dir : String_Access;
   --  Contains the full path name of the temporary directory created by the
   --  ASIS tools for the tree files, etc.

   Tool_Inner_Dir : String_Access;
   --  For an inner invocation, this is the subdirectory of the object
   --  directory in which gprbuild invoked this process; it's the same as
   --  Initial_Dir. If this is not an inner invocation, this is null,
   --  and not used.

end Utils.Environment;
