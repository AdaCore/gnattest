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

with Libadalang.Analysis; use Libadalang.Analysis;

with Utils.Command_Lines; use Utils.Command_Lines;
with Test.Command_Lines;

package Test.Actions is

   type Pass_Kind is (First_Pass, Second_Pass);

   Max_Files_Per_Context : constant Natural := 100;
   subtype Ctx_Count is Natural range 0 .. Max_Files_Per_Context;

   type Tool_State is tagged limited record
      Context : Analysis_Context := No_Analysis_Context;
      --  The only tool that needs access to the Context is gnatstub.

      Ctx_Counter : Ctx_Count := 0;
      --  Number of files processed with the current Context.

      Run_First_Pass : Boolean := False;
      --  Whether the drive should skip the first pass or not. Saves time by
      --  not re-instantiating LAL analysis contexts.
   end record;

   procedure Maybe_Recreate_Context
     (Tool : in out Tool_State; Char_Encoding : String);
   --  If Tool.Ctx_Counter reached Max_Files_Per_Context, recreate the context.
   --  Otherwise, increment Ctx_Counter.

   Global_Cmd : Command_Line (Test.Command_Lines.Descriptor'Access);

   procedure Init (Tool : in out Tool_State; Cmd : in out Command_Line);

   procedure Process_File
     (Tool         : Tool_State;
      Cmd          : Command_Line;
      File_Name    : String;
      Counter      : Natural;
      Syntax_Error : out Boolean;
      Reparse      : Boolean := False;
      Pass         : Pass_Kind := Second_Pass)
   with Pre => Tool.Context /= No_Analysis_Context;
   --  This class-wide procedure takes care of some bookkeeping, and then
   --  dispatches to First_Per_File_Action or Second_Per_File_Action depending
   --  on the .
   --
   --  If Tool.Context is nil, Process_File creates it. This is necessary
   --  because we have to defer the Create_Context call until after we've read
   --  the first file, because it might set the Wide_Character_Encoding via the
   --  BOM. This makes the somewhat questionable assumption that all files have
   --  the same encoding (which is necessary anyway if it's controlled by the
   --  command line).
   --
   --  Counter is a count of the number of files left to process. This is used
   --  to call Create_Context every N files, for some arbitrary N. Without
   --  that, we use up huge amounts of memory when processing a lot of files,
   --  due to caching in libadalang. But we don't want to call Create_Context
   --  on every file, because that slows down processing a lot.
   --
   --  Reparse has the same meaning as the parameter of Get_From_File. The
   --  reason this is needed is documented in Stub.Actions (search for the call
   --  to Process_File).

   procedure Generate_Tests (Cmd : Command_Line);
   --  Run GNATtest in generation mode.

   procedure Run_Tests;
   --  Run GNATtest in aggregate mode.

   procedure Tool_Help;

end Test.Actions;
