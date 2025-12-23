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

with Ada.Containers; use Ada.Containers;

with GNAT.OS_Lib; use GNAT.OS_Lib;

with GNATCOLL.VFS; use GNATCOLL.VFS;

with GPR2; use GPR2;
with GPR2.Build.Compilation_Unit;
with GPR2.Build.Source;
with GPR2.Path_Name;
with GPR2.Path_Name.Set;
with GPR2.Project.Attribute_Index;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Tree;
with GPR2.Project.View;

with Test.Common;
with Utils.Command_Lines; use Utils.Command_Lines;

package Utils.Projects is

   package PAI renames GPR2.Project.Attribute_Index;
   package PRA renames GPR2.Project.Registry.Attribute;

   GPR2_GT_Package : constant Package_Id :=
     +Name_Type (Test.Common.GT_Package);

   type Attribute is
     (Harness_Dir_Attr,
      --  Specify a directory to place the harness packages and the project
      --  file for the test driver.

      Stubs_Dir_Attr,
      --  Specify a directory in which stubbed units are generated

      Subdir_Attr,
      --  Specify a subdirectory corresponding to the source directory where to
      --  generate test packages.

      Tests_Root_Attr,
      --  Specify the directory hosting the hierarchy of test packages

      Tests_Dir_Attr,
      --  Specify a directory containing all test packages

      Switches_Attr,
      --  Specify a list of switches to pass to gnattest invocations for a
      --  specific unit.

      Default_Switches_Attr,
      --  Specify a list of switches to pass to gnattest invocations

      Additional_Tests_Attr,
      --  Specify a list of projects containing additional tests to be added to
      --  the testsuite.

      Skeletons_Default_Attr,
      --  Specify the default behavior of test skeletons (pass or fail)

      Stub_Exclusion_List_Attr,
      --  List of spec:filename that should not be stubbed

      Default_Stub_Exclusion_List_Attr
      --  Response file to specify a stub exclusion list

     );
   --  List of GPR attributes

   function Attr_String (A : Attribute) return String;
   --  Remove the _Attr suffix

   function "+" (A : Attribute) return String;
   function "+" (A : Attribute) return Q_Attribute_Id;

   function Coverage_Switches return Q_Attribute_Id;
   --  Return the Coverage.Switches project attribute

   function Emulator_Board return Q_Attribute_Id;
   --  Return the Emulator.Board project attribute

   function Outermost_Extending
     (View : GPR2.Project.View.Object) return GPR2.Project.View.Object;
   --  If View is extended, return the most extending view of View in the
   --  project tree, otherwise return View.

   function Recursive_Source_Dirs return GPR2.Path_Name.Set.Object;
   --  Return every source directory in the project tree

   function Attr_Id (Pack : String; Attr : String) return Q_Attribute_Id
   is ((Pack => GPR2."+" (GPR2.Name_Type (Pack)),
        Attr => GPR2."+" (GPR2.Name_Type (Attr))));

   function Root_Attribute (Attr : String) return Q_Attribute_Id
   is ((Pack => Project_Level_Scope,
        Attr => GPR2."+" (GPR2.Name_Type (Attr))));
   --  Return the given attribute id for Attr at the project level scope

   function Attr_Value
     (V : GPR2.Project.View.Object; Attr : Q_Attribute_Id) return String
   with
     Pre =>
       V.Has_Attribute (Attr) and then V.Attribute (Attr).Count_Values = 1;

   function Src (Filename : String) return GPR2.Build.Source.Object;
   --  Return the source identified by Filename

   function View_For (P : String) return GPR2.Project.View.Object;
   --  Recursive version of GPR2.Project.View.View_For
   --
   --  TODO??? remove when eng/gpr/gpr-issues#723 is implemented

   function To_File_Array
     (Files : GPR2.Path_Name.Set.Object) return GNATCOLL.VFS.File_Array;
   --  Convert a GPR2.Path_Name.Set.Object to a GNATCOLL.VFS.File_Array

   function Project_Tree return GPR2.Project.Tree.Object;
   --  Return the loaded project tree.

   function Load_Project
     (Cmd : Command_Line; Project_File : String)
      return GPR2.Project.Tree.Object;
   --  Wrapper around GPR2.Project.Tree.Load, passing the right target
   --  and RTS option. If the project could not be loaded, exit with an
   --  error.

   function Unit_Name_To_Unit
     (Unit_Name : String) return GPR2.Build.Compilation_Unit.Object;
   --  Look for a unit in the project tree. TODO??? remove when
   --  eng/gpr/gpr-issues#731 is implemented.

   function Has_Runtime_Source (Source : String) return Boolean
   is (Project_Tree.Has_Runtime_Project
       and then Project_Tree.Runtime_Project.Has_Source
                  (Simple_Name (Source)));
   --  If the project has a defined runtime, check whether the given source is
   --  part of it.

   procedure Unload;
   --  Clear the project tree

   procedure Process_Command_Line
     (Cmd               : in out Command_Line;
      Global_Report_Dir : out String_Ref;
      Print_Help        : not null access procedure);
   --  Processes the command line and (if specified on the command line) the
   --  project file.
   --
   --  Global_Report_Dir is set to the directory name in which to place global
   --  tool results, if this information comes from the project file (see
   --  Set_Global_Result_Dirs). Otherwise it is null.
   --
   --  Compiler_Options are options that should be passed to gcc, based on the
   --  content of the project file.
   --
   --  Project_RTS is the value Runtime of the project.
   --
   --  Individual_Source_Options is a mapping from source file names to
   --  switches specified specifically for that source file.
   --
   --  Result_Dirs is a mapping from source file names to file-specific result
   --  directories. Only used if Needs_Per_File_Output is ON.
   --
   --  ????? Use Compiler_Options for more stuff,
   --  where we currently have actions that call Store_GNAT_Option_With_Path
   --  and friends.
   --
   --  Callback is called for each switch, and can be used when some immediate
   --  action is required as soon as the switch is seen.
   --
   --  Tool_Temp_Dir is the name of the directory to which temp files should be
   --  written.
   --
   --  Print_Help is called if --help appears on the command line.

   procedure Read_File_Names_From_File
     (Par_File_Name : String;
      Action        : not null access procedure (File_Name : String));
   --  Read each file name from the named file, and call Action for each
   --  one. This is used to implement the --files and --ignore switches.

end Utils.Projects;
