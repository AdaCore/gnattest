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

--  This unit provides the JSON_Auto_IO helper, used to automatically load and
--  store JSON values from/to a file. It relies on file-I/O facilities
--  (Ada.Directories, Ada.Text_IO.Unbounded_IO) and is therefore host-only:
--  it is excluded when building TGen_RTS for an embedded runtime.

with Ada.Finalization;
with GNAT.Strings;

package TGen.JSON.Utils is

   type JSON_Auto_IO is new Ada.Finalization.Limited_Controlled with private;
   --  Type to handle automatic reading and writing JSON values from a
   --  specific file. When created, if the specified filename exists, the
   --  internal ref will hold the contents of that file loaded as a
   --  JSON_Value. It will then be written to disk once this object is
   --  finalized.

   function Create (Filename : String) return JSON_Auto_IO;
   --  Create a JSON_Auto_IO by loading the contents of Filename in its
   --  internal ref if the file exists. If not, the internal ref is an empty
   --  JSON object. The JSON_Value held by the JSON_Auto_IO will be
   --  serialized to filename when finalized.
   --
   --  This function propagates Ada.Directories.Filename_Error if the passed
   --  Filename does not contain a valid path.

   function Get_JSON_Ref (Self : JSON_Auto_IO) return JSON_Value;
   --  Get a reference to the JSON_Value held by Self

   function Read_Whole_File (Filename : String) return String;
   --  Read the text content of `Filename`

private
   type JSON_Auto_IO is new Ada.Finalization.Limited_Controlled with record
      Filename     : GNAT.Strings.String_Access;
      JSON_Content : JSON_Value := Create_Object;
   end record;

   overriding
   procedure Finalize (Self : in out JSON_Auto_IO);

end TGen.JSON.Utils;
