------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                       Copyright (C) 2022, AdaCore                        --
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

with Ada.Command_Line;
with Ada.Containers; use Ada.Containers;
with Ada.Text_IO;

with GPR2.Path_Name;

with Test.Command_Lines; use Test.Command_Lines;

with Utils.String_Utilities; use Utils.String_Utilities;
with Utils.Tool_Names;

package body Utils.Projects.Aggregate is

   use Test_Boolean_Switches;

   use String_Access_Sets;
   Aggregated_Projects : String_Access_Set;
   --  The set of aggregated projects that are part of the current aggregate
   --  project. Set by Collect_Aggregated_Projects

   ---------------------------------
   -- Collect_Aggregated_Projects --
   ---------------------------------

   procedure Collect_Aggregated_Projects (P : GPR2.Project.Tree.Object) is
   begin
      if Debug_Flag_A then
         Ada.Text_IO.Put_Line (String (P.Root_Project.Path_Name.Name));
      end if;

      for Prj of P.Root_Project.Aggregated loop
         declare
            Prj_Path : constant GPR2.Path_Name.Object := Prj.Path_Name;
            pragma Assert (Prj_Path.Is_Defined);
         begin
            Include
              (Aggregated_Projects, new String'(String (Prj.Path_Name.Name)));
         end;
      end loop;

      if Aggregated_Projects.Length = 0 then
         Cmd_Error ("aggregate project does not contain anything to process");
      end if;
   end Collect_Aggregated_Projects;

   ---------------------------------
   -- Process_Aggregated_Projects --
   ---------------------------------

   procedure Process_Aggregated_Projects (Cmd : Command_Line) is
      Args_Vec : String_Vector renames Utils.Command_Lines.Args;
      Args     : GNAT.OS_Lib.Argument_List (1 .. Args_Vec.Last_Index + 2);
   begin
      for I in 1 .. Args_Vec.Last_Index loop
         Args (I) := new String'(Args_Vec.Element (I));
      end loop;

      for Prj_Name of Aggregated_Projects loop
         if Arg (Cmd, Verbose) then
            Ada.Text_IO.Put_Line
              ("Processing aggregated project " & Prj_Name.all);
         end if;
         Args (Args'Last - 1) := +"--aggregated-project-file";
         Args (Args'Last) := Prj_Name;

         if Debug_Flag_C then
            Print_Command_Line (Ada.Command_Line.Command_Name, Args);
         end if;

         declare
            Exit_Code : constant Integer :=
              Spawn (Tool_Names.Full_Tool_Name, Args);
         begin
            --  If the subprocess failed, then we fail. We could instead keep
            --  going, and collect the exit codes of all subprocesses, and
            --  print something at the end if some failed.

            if Exit_Code /= 0 then
               OS_Exit (Exit_Code);
            end if;
         end;
      end loop;
   end Process_Aggregated_Projects;

end Utils.Projects.Aggregate;
