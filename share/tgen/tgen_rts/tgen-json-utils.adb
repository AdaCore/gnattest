------------------------------------------------------------------------------
--                                                                          --
--                                  TGen                                    --
--                                                                          --
--                       Copyright (C) 2025, AdaCore                        --
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

with Ada.Directories;
with Ada.Text_IO;
with Ada.Text_IO.Unbounded_IO;

package body TGen.JSON.Utils is

   ---------------------
   -- Read_Whole_File --
   ---------------------

   function Read_Whole_File (Filename : String) return String is
      use Ada.Text_IO;

      FT     : File_Type;
      Result : Unbounded_String;
      Line   : Unbounded_String;
   begin
      Ada.Text_IO.Open (FT, Mode => In_File, Name => Filename);

      loop
         Unbounded_IO.Get_Line (FT, Line);
         Append (Result, Line);

         exit when Ada.Text_IO.End_Of_File (FT);
      end loop;

      Ada.Text_IO.Close (FT);
      return To_String (Result);
   end Read_Whole_File;

   ------------
   -- Create --
   ------------

   function Create (Filename : String) return JSON_Auto_IO is
      Content : JSON_Value;
   begin

      --  Use Ada.Directories here as it checks whether Filename can
      --  designate a file or not, and raises an exception if it is not the
      --  case.
      Content :=
        (if Ada.Directories.Exists (Filename)
         then Read (Read_Whole_File (Filename), Filename)
         else Create_Object);
      return Res : JSON_Auto_IO do
         Res.Filename := new String'(Filename);
         Res.JSON_Content := Content;
      end return;
   end Create;

   ------------------
   -- Get_JSON_Ref --
   ------------------

   function Get_JSON_Ref (Self : JSON_Auto_IO) return JSON_Value
   is (Self.JSON_Content);

   ----------------
   --  Finalize  --
   ----------------

   overriding
   procedure Finalize (Self : in out JSON_Auto_IO) is
      use Ada.Directories;
      use GNAT.Strings;
      File : Ada.Text_IO.File_Type;
   begin
      if Self.Filename = null then
         return;
      end if;

      --  Assume Self.Filename is a valid path, as otherwise Create would
      --  have already complained about this.

      if not Self.JSON_Content.Is_Empty then
         if Ada.Directories.Exists (Self.Filename.all) then
            Ada.Text_IO.Open (File, Ada.Text_IO.Out_File, Self.Filename.all);
         else
            Create_Path (Containing_Directory (Self.Filename.all));
            Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Self.Filename.all);
         end if;
         Ada.Text_IO.Put (File, Self.JSON_Content.Write (Compact => True));
         Ada.Text_IO.Close (File);
      end if;
      Free (Self.Filename);
   end Finalize;

end TGen.JSON.Utils;
