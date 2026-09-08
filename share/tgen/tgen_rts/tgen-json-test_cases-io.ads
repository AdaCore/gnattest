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

--  This unit provides the file-I/O operations for TGen JSON test cases
--  (loading from and writing to a file). It relies on file-I/O facilities
--  (GNAT.OS_Lib, Ada.Text_IO) and is therefore host-only: it is excluded when
--  building TGen_RTS for an embedded runtime.

with GNAT.OS_Lib;

package TGen.JSON.Test_Cases.IO is

   function Load_From_File (File_Path : String) return JSON_Test_Cases
   with Pre => GNAT.OS_Lib.Is_Read_Accessible_File (File_Path);
   --  Load a TGen JSON test case file and return an instance of the loaded
   --  file. This function will raise an exception
   --  (`TGen.JSON.Invalid_JSON_Stream`) if the JSON file is not valid.

   procedure Write_To_File (Self : JSON_Test_Cases; File_Path : String);
   --  Write Self encoded as a JSON to File_Path

end TGen.JSON.Test_Cases.IO;
