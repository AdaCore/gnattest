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

with Ada.Text_IO;

with TGen.JSON.Utils; use TGen.JSON.Utils;

package body TGen.JSON.Test_Cases.IO is

   ----------------------
   --  Load_From_File  --
   ----------------------

   function Load_From_File (File_Path : String) return JSON_Test_Cases is
      File_Content : constant String := Read_Whole_File (File_Path);
      Root         : constant JSON_Value :=
        TGen.JSON.Read (File_Content, File_Path);
   begin
      return JSON_Test_Cases'(Root => Root);
   end Load_From_File;

   -------------------
   -- Write_To_File --
   -------------------

   procedure Write_To_File (Self : JSON_Test_Cases; File_Path : String) is
      use Ada.Text_IO;

      FT : File_Type;
   begin
      Open (FT, Mode => Out_File, Name => File_Path);
      Put_Line (FT, Self.Root.Write (Compact => False));
      Close (FT);
   end Write_To_File;

end TGen.JSON.Test_Cases.IO;
