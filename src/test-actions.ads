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

package Test.Actions is

   --  Each tool should derive from Tool_State, and override the ops.
   --  The driver calls Init, then First_Per_File_Action on each source file,
   --  then First_Pass_Post_Process, then Second_Per_File_Action on each source
   --  file, then Final.

   type Pass_Kind is (First_Pass, Second_Pass);

   type Tool_State is tagged limited record
      Context : Analysis_Context := No_Analysis_Context;
      --  The only tool that needs access to the Context is gnatstub.

      Run_First_Pass : Boolean := False;
      --  Whether the drive should skip the first pass or not. Saves time by
      --  not re-instantiating LAL analysis contexts.
   end record;

   procedure Init (Tool : in out Tool_State; Cmd : in out Command_Line);
   procedure First_Per_File_Action
     (Tool      : in out Tool_State;
      Cmd       : Command_Line;
      File_Name : String;
      Input     : String;
      BOM_Seen  : Boolean;
      Unit      : Analysis_Unit);
   procedure Second_Per_File_Action
     (Tool      : in out Tool_State;
      Cmd       : Command_Line;
      File_Name : String;
      Input     : String;
      BOM_Seen  : Boolean;
      Unit      : Analysis_Unit);
   --  Input is the contents of the file named by File_Name.
   --  BOM_Seen is True if there was a BOM at the start of the file;
   --  the BOM is not included in Input.

   procedure First_Pass_Post_Process
     (Tool : in out Tool_State; Cmd : in out Command_Line);
   --  Called in between First_Per_File_Action and Second_Per_File_Action

   procedure Process_File
     (Tool         : in out Tool_State;
      Cmd          : in out Command_Line;
      File_Name    : String;
      Counter      : Natural;
      Syntax_Error : out Boolean;
      Reparse      : Boolean := False;
      Pass         : Pass_Kind := Second_Pass);
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

   procedure Final (Tool : in out Tool_State; Cmd : Command_Line);
   procedure Tool_Help;

end Test.Actions;
