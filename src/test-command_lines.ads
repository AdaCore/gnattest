------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2019-2023, AdaCore                    --
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

with Utils.Command_Lines; use Utils.Command_Lines;

package Test.Command_Lines is

   Descriptor : aliased Command_Line_Descriptor;

   --  ??? -j is ignored.
   type Test_Nats is (Jobs);
   package Test_Nat_Switches is new
     Other_Switches
       (Descriptor,
        Test_Nats,
        Natural,
        Natural'Image,
        Natural'Value);
   package Test_Nat_Syntax is new Test_Nat_Switches.Set_Syntax ([Jobs => '!']);
   package Test_Nat_Defaults is new
     Test_Nat_Switches.Set_Defaults ([Jobs => 1]);
   package Test_Nat_Shorthands is new
     Test_Nat_Switches.Set_Shorthands ([Jobs => +"-j"]);
   package Test_Nat_Shorthands_2 is new
     Test_Nat_Switches.Set_Shorthands ([Jobs => +"--queues"]);

   type Test_Booleans is
     (Strict,
      Recursive,
      Harness_Only,
      Stub,
      Recursive_Stub,
      Validate_Type_Extensions,
      Inheritance_Check,
      Test_Case_Only,
      Omit_Sloc,
      Command_Line_Support,
      Test_Duration,
      Relocatable_Harness,
      Gen_Test_Vectors,
      Test_Filtering,
      Test_Filtering_File_IO,
      Serialized_Test_Dir,
      Dump_Test_Inputs,
      Unparse,
      Enum_Strat,
      Minimize,
      Include_Subp_Name,

      --  Moved from the late Utils.Command_Lines.Common

      Version,
      Help,
      Verbose,
      Quiet,
      Follow_Symbolic_Links);

   package Test_Boolean_Switches is new
     Boolean_Switches (Descriptor, Test_Booleans);

   package Test_Boolean_Shorthands is new
     Test_Boolean_Switches.Set_Shorthands
       ([Recursive             => +"-r",
         Command_Line_Support  => +"--command-line",
         Verbose               => +"-v",
         Quiet                 => +"-q",
         Follow_Symbolic_Links => +"-eL",
         others                => null]);

   --  Re: the --command-line/--no-command-line switch. We don't want an
   --  enumeration literal Command_Line here, because it causes conflicts
   --  with the type of the same name. So we call it Command_Line_Support,
   --  and add --command-line as a shorthand.

   package Test_Boolean_Defaults is new
     Test_Boolean_Switches.Set_Defaults
       ([Inheritance_Check      => True,
         Command_Line_Support   => True,
         Harness_Only           => False,
         Test_Filtering         => True,
         Test_Filtering_File_IO => True,
         others                 => False]);

   type Test_Strings is
     (Separate_Drivers,
      Harness_Dir,
      Tests_Dir,
      Tests_Root,
      Stubs_Dir,
      Additional_Tests,
      Skeleton_Default,
      Passed_Tests,
      Exit_Status,
      Copy_Environment,
      Reporter,
      Gen_Test_Num,
      Gen_Test_Subprograms,
      Serialized_Test_Dir,
      Cov_Level,
      Minimization_Filter,
      Dump_Subp_Hash,

      --  Moved from the late Utils.Command_Lines.Common

      Project_File,
      Aggregated_Project_File,
      --  Aggregated_Project_File is an undocumented switch used in the
      --  implementation of aggregate projects. When gnattest is invoked with
      --  an aggregate project where the aggregated projects are a, b, and c,
      --  it spawns 3 subprocesses passing --aggregated-project-file=a,
      --  --aggregated-project-file=b, and  --aggregated-project-file=c.
      Run_Time_System,
      Output_Directory,
      Target,
      Subdirs,
      Wide_Character_Encoding -- Use Enum_Switches????
     );

   package Test_String_Switches is new
     String_Switches (Descriptor, Test_Strings);

   package Test_String_Syntax is new
     Test_String_Switches.Set_Syntax
       ([Separate_Drivers        => '?',
         Project_File            => ':',
         Wide_Character_Encoding => '!',
         others                  => '=']);

   package Test_String_Defaults is new
     Test_String_Switches.Set_Defaults
       ([Run_Time_System => +"", others => null]);

   package Test_String_Shorthands is new
     Test_String_Switches.Set_Shorthands
       ([Project_File            => +"-P",
         Run_Time_System         => +"--RTS",
         Output_Directory        => +"--output-dir",
         Wide_Character_Encoding => +"-W",
         others                  => null]);

   package Test_String_Shorthands_2 is new
     Test_String_Switches.Set_Shorthands
       ([Output_Directory => +"--dir", others => null]);

   type Test_String_Seqs is
     (Exclude_From_Stubbing,

      --  Moved from the late Utils.Command_Lines.Common

      Debug,
      Files,
      Ignore,
      External_Variable);

   package Test_String_Seq_Switches is new
     String_Seq_Switches (Descriptor, Test_String_Seqs);

   package Test_String_Seq_Syntax is new
     Test_String_Seq_Switches.Set_Syntax
       ([Exclude_From_Stubbing => '!',
         Debug                 => '!',
         Files                 => '=',
         Ignore                => '=',
         External_Variable     => '!']);

   package Test_String_Seq_Shorthands is new
     Test_String_Seq_Switches.Set_Shorthands
       ([Debug             => +"-d",
         Files             => +"-files",
         External_Variable => +"-X",
         others            => null]);

   type Ada_Version_Type is (Ada_83, Ada_95, Ada_2005, Ada_2012, Ada_2022);

   package Ada_Version_Switches is new
     Enum_Switches (Descriptor, Ada_Version_Type, Default => Ada_2012);
   --  These switches are ignored. The tools are tolerant of using newer
   --  reserved words, such as "interface", as identifiers, so we don't need to
   --  know the version.

   package Ada_Version_Shorthands is new
     Ada_Version_Switches.Set_Shorthands
       ([Ada_83   => +"-gnat83",
         Ada_95   => +"-gnat95",
         Ada_2005 => +"-gnat2005",
         Ada_2012 => +"-gnat2012",
         Ada_2022 => +"-gnat2022"]);

   package Ada_Version_Shorthands_2 is new
     Ada_Version_Switches.Set_Shorthands
       ([Ada_2005 => +"-gnat05", others => null]);

   type Source_Selection_Type is
     (Update_All, No_Subprojects, No_Source_Selection);
   package Source_Selection_Switches is new
     Enum_Switches
       (Descriptor,
        Source_Selection_Type,
        Default => Source_Selection_Type'Last);
   package Source_Selection_Shorthands is new
     Source_Selection_Switches.Set_Shorthands
       ([Update_All => +"-U", others => null]);

   package Freeze is new Freeze_Descriptor (Descriptor);

   ----------------

   function Wide_Character_Encoding (Cmd : Command_Line) return String;
   --  Libadalang wants the encoding as a String

   function WCEM (Cmd : Command_Line) return Character;
   --  Return the single-character encoding letter

   procedure Set_WCEM (Cmd : in out Command_Line; Encoding : String);
   --  Set the wide character encoding method as if the switch had appeared on
   --  the command line. This is used when a BOM selects UTF-8.
   --
   --  The encoding specified on the command line is saved internally and can
   --  be restored with Restore_WCEM.

   procedure Restore_WCEM (Cmd : in out Command_Line);
   --  Restore the wide character encoding method saved in the internal state
   --  of this package. This must not be called if Set_WCEM has not previously
   --  been called, otherwise Program_Error is raised.

end Test.Command_Lines;
