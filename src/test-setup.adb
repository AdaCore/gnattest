------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2026, AdaCore                         --
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

with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with GNATCOLL.OS.Process;
with GNATCOLL.VFS; use GNATCOLL.VFS;

with GPR2;
with GPR2.Options;
with GPR2.Project.Attribute;
with GPR2.Project.Attribute_Index;
with GPR2.Project.Configuration;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Tree;
with GPR2.Project.View;

with Test.Command_Lines; use Test.Command_Lines;
use Test.Command_Lines.Test_String_Switches;
use Test.Command_Lines.Test_Boolean_Switches;
use Test.Command_Lines.Setup_Profile_Switches;

with Test.Common;
with Test.Subprocess;

with Utils.Command_Lines;    use Utils.Command_Lines;
with Utils.Environment;
with Utils.Projects;
with Utils.String_Utilities; use Utils.String_Utilities;
with Utils.Tool_Names;
with Utils_Debug;

package body Test.Setup is

   --  The runtime-profile enum and its --rts-profile switch live in
   --  Test.Command_Lines so the framework can parse the switch directly.

   --  --tgen requests the TGen runtime and --no-tgen skips it. Building
   --  the runtime always requires a successful Ada 2022 compiler probe.
   type Tgen_Mode_Type is (Tgen_Auto, Tgen_Build, Tgen_Skip);

   --  The languages whose test libraries setup builds: AUnit and TGen for
   --  Ada, Unity for C, Google Test for C++.
   type Setup_Language is (Lang_Ada, Lang_C, Lang_Cpp);
   type Language_Set is array (Setup_Language) of Boolean;

   type Setup_Options is record
      Target  : Unbounded_String;
      RTS     : Unbounded_String;
      Config  : Unbounded_String;
      Prefix  : Unbounded_String;
      Profile : Setup_Profile_Type := Auto;
      Gargs   : GNATCOLL.OS.Process.Argument_List;
      Verbose : Boolean := False;
      Quiet   : Boolean := False;

      Compiler_Prefix : Boolean := False;
      --  When set, install at the install prefix of the compiler. Resolved
      --  into Prefix early in Run.

      Tgen_Mode : Tgen_Mode_Type := Tgen_Auto;

      Languages : Language_Set := [others => True];

      Explicit_Languages : Boolean := False;
      --  Whether --lang was passed. Only an explicitly requested language
      --  that cannot be built is an error. By default, setup builds what the
      --  configuration supports, so that a cross or light runtime setup
      --  still succeeds without C or C++ support.
   end record;

   function Parse_Languages (Value : String) return Language_Set;
   --  Parse the comma-separated, case-insensitive list of --lang. Fail on
   --  an empty list or an unknown language.

   function Requested
     (Opts : Setup_Options; Lang : Setup_Language) return Boolean
   is (Opts.Explicit_Languages and then Opts.Languages (Lang));
   --  Whether Lang was named in --lang, so failing to build it is an error

   --  Local helpers

   procedure Fail (Msg : String)
   with No_Return;
   --  Terminate the process with an error code, displaying Msg with the
   --  "gnattest setup:" prefix.

   function Contains (Hay, Needle : String) return Boolean;
   --  Return True if Hay contains Needle

   function Is_Native (Opts : Setup_Options) return Boolean;
   --  True when no --target was passed (or it is "native"). Gates the TGen
   --  runtime build, which has no cross-compilation story.

   function Infer_Profile (Opts : Setup_Options) return Setup_Profile_Type;
   --  Infer the runtime profile according to the command line RTS option. This
   --  influences the AUnit build.

   function TGen_Supports_Profile (Profile : Setup_Profile_Type) return Boolean
   is (Profile in Profile_Full | Profile_Ravenscar);
   --  Determine if TGen can be built against the given runtime profile

   function Gnattest_Prefix return String;
   --  Return the install prefix of gnattest

   function Compiler_Install_Prefix (Opts : Setup_Options) return String;
   --  Return the install prefix of the compiler that will build the
   --  libraries according to Opts: the Ada compiler, or without Ada in
   --  --lang, the compiler of the first selected language.

   function Build_Command
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List)
      return GNATCOLL.OS.Process.Argument_List;
   --  gprbuild command line shared by Run_Build and the Ada 2022 probe

   procedure Run_Build
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List);
   --  Common build helper

   function Compiler_Supports_Ada_2022
     (Opts : Setup_Options; Build_Dir : String) return Boolean;
   --  Whether the selected Ada compiler can build the TGen runtime, which
   --  requires Ada 2022 support. Checked by building, with the same gprbuild
   --  options as the real build, a probe project staged under Build_Dir that
   --  exercises the Ada 2022 features the TGen runtime relies on.

   procedure Run_Install
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List);
   --  Common install helper

   function Source_AUnit_Dir return String;
   --  Read-only AUnit source tree shipped with gnattest, at
   --  <gnattest_prefix>/share/aunit. We never build here directly; sources
   --  are copied into a temp dir first.

   function Source_TGen_Dir return String;
   --  Read-only TGen runtime source tree at
   --  <gnattest_prefix>/share/tgen/tgen_rts. Same staging treatment as
   --  AUnit.

   function Build_AUnit_GPR (Build_Dir : String) return String;
   --  Path of aunit.gpr inside the temp build directory. Build_Dir is the
   --  directory that *contains* the copied "aunit" subtree.

   function Build_TGen_GPR (Build_Dir, Name : String) return String;
   --  Path of <Name>.gpr inside the staged TGen subtree. Name is one of
   --  "tgen_rts" or "tgen_marshalling_rts".

   procedure Copy_Sources (Src, Dst_Parent : String);
   --  Copy the Src directory into Dst_Parent

   function Deref (Ref : String_Ref) return String;
   --  Return the empty string if Ref is null, Ref.all otherwise

   function Aunit_Common_Args
     (Opts : Setup_Options; Profile : Setup_Profile_Type)
      return GNATCOLL.OS.Process.Argument_List;
   --  List of arguments to pass to both gprbuild and gprinstall command line
   --  invocation to build / install aunit.

   procedure Run_Build_AUnit
     (Opts : Setup_Options; Profile : Setup_Profile_Type; Build_Dir : String);
   --  Build the aunit library located in Build_Dir

   procedure Run_Install_AUnit
     (Opts : Setup_Options; Profile : Setup_Profile_Type; Build_Dir : String);
   --  Install the aunit library built at Build_Dir

   procedure Run_Build_TGen (Opts : Setup_Options; Build_Dir : String);
   --  Build the TGen library located in Build_Dir

   procedure Run_Install_TGen (Opts : Setup_Options; Build_Dir : String);
   --  Install the TGen library built at Build_Dir

   function Source_GTest_Dir return String;
   --  Read-only Google Test source tree shipped with gnattest, at
   --  <gnattest_prefix>/share/gtest (populated by "make install-gtest").

   function GTest_Supported
     (Opts : Setup_Options; Profile : Setup_Profile_Type) return Boolean;
   --  True when Google Test can be built for this configuration: native mode,
   --  the full runtime profile (gtest needs a hosted C++ runtime), and the
   --  sources actually shipped with this gnattest.

   function Run_Build_GTest
     (Opts : Setup_Options; Build_Dir : String) return Boolean;
   --  Build libgtest.a from the source drop staged in Build_Dir. Return
   --  whether it succeeded: a C toolchain may lack the C++ compiler.

   procedure Install_GTest (Opts : Setup_Options; Build_Dir : String);
   --  Install the gtest headers, library and its gtest.gpr project under the
   --  chosen prefix, so the generated harness can "with" it.

   function Source_Unity_Dir return String;
   --  Read-only Unity source tree shipped with gnattest, with gnattest's
   --  support for it, at <gnattest_prefix>/share/unity (populated by "make
   --  install-unity").

   function Unity_Supported return Boolean;
   --  True when the Unity sources are shipped with this gnattest. Unity needs
   --  nothing but a C compiler and its library, so any target is supported.

   function Run_Build_Unity
     (Opts : Setup_Options; Build_Dir : String) return Boolean;
   --  Build libgnattest_unity.a from the sources staged in Build_Dir. Return
   --  whether it succeeded: the configuration may have no C compiler.

   procedure Install_Unity (Opts : Setup_Options; Build_Dir : String);
   --  Install the Unity headers, library and its gnattest_unity.gpr project
   --  under the chosen prefix, so the generated C test driver can "with" it.

   --  Controlled wrapper that creates a unique build directory under the
   --  system temp dir and removes it on scope exit (unless Save_Temps was
   --  requested).
   type Build_Dir_Type is new Ada.Finalization.Limited_Controlled with record
      Path       : Unbounded_String;
      Save_Temps : Boolean := False;
   end record;

   overriding
   procedure Initialize (Self : in out Build_Dir_Type);
   overriding
   procedure Finalize (Self : in out Build_Dir_Type);

   ----------
   -- Fail --
   ----------

   procedure Fail (Msg : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "gnattest setup: " & Msg);
      GNAT.OS_Lib.OS_Exit (1);
   end Fail;

   -----------
   -- Deref --
   -----------

   function Deref (Ref : String_Ref) return String is
   begin
      if Present (Ref) then
         return Ref.all;
      else
         return "";
      end if;
   end Deref;

   ---------------------
   -- Parse_Languages --
   ---------------------

   function Parse_Languages (Value : String) return Language_Set is
      Result : Language_Set := [others => False];
      First  : Positive := Value'First;
      Last   : Natural;
   begin
      loop
         Last := Ada.Strings.Fixed.Index (Value (First .. Value'Last), ",");
         Last := (if Last = 0 then Value'Last else Last - 1);

         declare
            Name : constant String :=
              Ada.Characters.Handling.To_Lower
                (Ada.Strings.Fixed.Trim
                   (Value (First .. Last), Ada.Strings.Both));
         begin
            if Name = "" then
               Fail ("--lang: empty language name in """ & Value & """");
            elsif Name = "ada" then
               Result (Lang_Ada) := True;
            elsif Name = "c" then
               Result (Lang_C) := True;
            elsif Name = "c++" then
               Result (Lang_Cpp) := True;
            else
               Fail
                 ("--lang: unknown language """
                  & Name
                  & """, expected ada, c or c++");
            end if;
         end;

         exit when Last >= Value'Last;
         First := Last + 2;
      end loop;
      return Result;
   end Parse_Languages;

   ----------------
   -- Print_Help --
   ----------------

   procedure Print_Help is
      use Ada.Text_IO;
   begin
      Put_Line ("Usage: gnattest setup [options]");
      New_Line;
      Put_Line ("Build and install the bundled test libraries for a given");
      Put_Line ("target / RTS combination: AUnit and the TGen runtime for");
      Put_Line ("Ada, Unity for C and Google Test for C++ (native full");
      Put_Line ("runtime only).");
      New_Line;
      Put_Line ("Options:");
      Put_Line ("  --target=<triplet>  Cross-compilation target");
      Put_Line ("  --RTS=<name>        Runtime to use (e.g. light, embedded)");
      Put_Line ("  --config=<file>     gprbuild configuration project");
      Put_Line ("  --prefix=<dir>      Install prefix (default: gnattest's)");
      Put_Line ("  --compiler-prefix   Install at the compiler's install");
      Put_Line ("                      prefix. Overrides --prefix.");
      Put_Line ("  --rts-profile=<p>   auto | full | zfp | zfp-cross |");
      Put_Line ("                      ravenscar | ravenscar-cert | cert");
      Put_Line ("                      (default: auto, from --RTS/--target)");
      Put_Line ("  --lang=<list>       Languages to set up, comma-separated:");
      Put_Line ("                      ada, c, c++ (case insensitive).");
      Put_Line ("                      Default: all of them.");
      Put_Line ("  --tgen / --no-tgen  Request or skip building the TGen");
      Put_Line
        ("                      runtime. It is skipped if the Ada 2022");
      Put_Line
        ("                      compiler probe fails, even with --tgen.");
      Put_Line ("  -q                  Quiet mode");
      Put_Line ("  -v                  Verbose mode (echo invoked commands)");
      Put_Line ("  -gargs ...          Pass remaining args to gprbuild");
      Put_Line ("  --save-temps        Keep the temporary build directory");
      Put_Line ("  -h, --help          Show this message");
   end Print_Help;

   --------------
   -- Contains --
   --------------

   function Contains (Hay, Needle : String) return Boolean
   is (Ada.Strings.Fixed.Index (Hay, Needle) /= 0);

   ---------------
   -- Is_Native --
   ---------------

   function Is_Native (Opts : Setup_Options) return Boolean is
      Target : constant String := To_String (Opts.Target);
   begin
      return Target = "" or else Target = "native";
   end Is_Native;

   -------------------
   -- Infer_Profile --
   -------------------

   function Infer_Profile (Opts : Setup_Options) return Setup_Profile_Type is
      RTS    : constant String := To_String (Opts.RTS);
      Target : constant String := To_String (Opts.Target);
   begin
      if Contains (RTS, "embedded") or else Contains (RTS, "ravenscar") then
         if Contains (RTS, "cert") then
            return Profile_Ravenscar_Cert;
         else
            return Profile_Ravenscar;
         end if;
      elsif Contains (RTS, "light") or else Contains (RTS, "zfp") then
         if Target /= "" and then Target /= "native" then
            return Profile_ZFP_Cross;
         else
            return Profile_ZFP;
         end if;
      elsif Contains (RTS, "cert") then
         return Profile_Cert;
      else
         return Profile_Full;
      end if;
   end Infer_Profile;

   ---------------------
   -- Gnattest_Prefix --
   ---------------------

   function Gnattest_Prefix return String is
      use Ada.Directories;
      Exe    : constant String := Utils.Tool_Names.Full_Tool_Name;
      Bindir : constant String := Containing_Directory (Exe);
   begin
      return Containing_Directory (Bindir);
   end Gnattest_Prefix;

   -----------------------------
   -- Compiler_Install_Prefix --
   -----------------------------

   function Compiler_Install_Prefix (Opts : Setup_Options) return String is
      use Ada.Directories;

      Target : constant String := To_String (Opts.Target);

      --  A C-only setup must not require an Ada compiler

      Lang      : constant Setup_Language :=
        (if Opts.Languages (Lang_Ada)
         then Lang_Ada
         elsif Opts.Languages (Lang_C)
         then Lang_C
         else Lang_Cpp);
      Lang_Name : constant String :=
        (case Lang is
           when Lang_Ada => "Ada",
           when Lang_C   => "C",
           when Lang_Cpp => "C++");
      Lang_Id   : constant GPR2.Language_Id :=
        (case Lang is
           when Lang_Ada => GPR2.Ada_Language,
           when Lang_C   => GPR2.C_Language,
           when Lang_Cpp => GPR2.CPP_Language);

      --  A minimal project so that loading it autoconfigures the compiler
      --  for the requested target/RTS. We then read the resulting
      --  configuration rather than assuming any particular driver name.

      Prj_Name : constant String :=
        Compose (Utils.Environment.Tool_Temp_Dir.all, "gnattest_setup.gpr");
      Tree     : GPR2.Project.Tree.Object;
      Opt      : GPR2.Options.Object;
   begin
      declare
         use Ada.Text_IO;
         F : File_Type;
      begin
         Create (F, Out_File, Prj_Name);
         Put_Line (F, "project Gnattest_Setup is");
         Put_Line (F, "   for Source_Dirs use ();");
         Put_Line (F, "   for Languages use (""" & Lang_Name & """);");
         Put_Line (F, "end Gnattest_Setup;");
         Close (F);
      end;

      Opt.Add_Switch (GPR2.Options.P, Prj_Name);
      if not Is_Native (Opts) then
         Opt.Add_Switch (GPR2.Options.Target, Target);
      end if;
      if Length (Opts.RTS) > 0 then
         Opt.Add_Switch (GPR2.Options.RTS, To_String (Opts.RTS));
      end if;
      if Length (Opts.Config) > 0 then
         Opt.Add_Switch (GPR2.Options.Config, To_String (Opts.Config));
      end if;

      if not Tree.Load
               (Opt,
                With_Runtime     => True,
                Reporter         =>
                  Utils.Projects.Console_Reporter
                    (Quiet => Opts.Quiet, Verbose => Opts.Verbose),
                Absent_Dir_Error => GPR2.No_Error,
                Check_Drivers    => False)
        or else not Tree.Has_Configuration
      then
         Fail
           ("--compiler-prefix: could not find a compiler for the requested"
            & " target/RTS");
      end if;

      declare
         View : constant GPR2.Project.View.Object :=
           Tree.Configuration.Corresponding_View;
         Attr : constant GPR2.Project.Attribute.Object :=
           View.Attribute
             (Name  => GPR2.Project.Registry.Attribute.Compiler.Driver,
              Index => GPR2.Project.Attribute_Index.Create (Lang_Id));
      begin
         if not Attr.Is_Defined then
            Fail
              ("--compiler-prefix: no "
               & Lang_Name
               & " compiler driver in config");
         end if;

         --  Compilers are installed in <prefix>/bin, so the prefix is the
         --  driver's grandparent directory.

         return
           Containing_Directory
             (Containing_Directory (String (Attr.Value.Text)));
      end;
   end Compiler_Install_Prefix;

   ----------------------
   -- Source_AUnit_Dir --
   ----------------------

   function Source_AUnit_Dir return String is
      use Ada.Directories;
      Share : constant String := Compose (Gnattest_Prefix, "share");
   begin
      return Compose (Share, "aunit");
   end Source_AUnit_Dir;

   ---------------------
   -- Source_TGen_Dir --
   ---------------------

   function Source_TGen_Dir return String is
      use Ada.Directories;
      Share : constant String := Compose (Gnattest_Prefix, "share");
      Tgen  : constant String := Compose (Share, "tgen");
   begin
      return Compose (Tgen, "tgen_rts");
   end Source_TGen_Dir;

   ----------------------
   -- Build_AUnit_GPR  --
   ----------------------

   function Build_AUnit_GPR (Build_Dir : String) return String is
      use Ada.Directories;
      Aunit    : constant String := Compose (Build_Dir, "aunit");
      Lib      : constant String := Compose (Aunit, "lib");
      Lib_Gnat : constant String := Compose (Lib, "gnat");
   begin
      return Compose (Lib_Gnat, "aunit", Extension => "gpr");
   end Build_AUnit_GPR;

   ---------------------
   -- Build_TGen_GPR  --
   ---------------------

   function Build_TGen_GPR (Build_Dir, Name : String) return String is
      use Ada.Directories;
      Staged : constant String := Compose (Build_Dir, "tgen_rts");
   begin
      return Compose (Staged, Name, Extension => "gpr");
   end Build_TGen_GPR;

   -------------------
   -- Copy_Sources  --
   -------------------

   procedure Copy_Sources (Src, Dst_Parent : String) is
      Source  : constant Virtual_File := Create (+Src);
      Target  : constant String :=
        Ada.Directories.Compose
          (Dst_Parent, Ada.Directories.Simple_Name (Src));
      Success : Boolean;
   begin
      Source.Copy (+Target, Success);
      if not Success then
         Fail ("could not copy " & Source.Display_Full_Name & " to " & Target);
      end if;
   end Copy_Sources;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Self : in out Build_Dir_Type) is
      use Ada.Directories;
      Pid_Img : constant String :=
        Ada.Strings.Fixed.Trim
          (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)'Image,
           Ada.Strings.Both);
      Path    : constant String :=
        Compose
          (Utils.Environment.Tool_Temp_Dir.all, "gnattest-setup-" & Pid_Img);
   begin
      if Exists (Path) then
         Delete_Tree (Path);
      end if;
      Create_Path (Path);
      Self.Path := To_Unbounded_String (Path);
   end Initialize;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Self : in out Build_Dir_Type) is
      use Ada.Directories;
   begin
      if Self.Save_Temps or else Length (Self.Path) = 0 then
         return;
      end if;
      if Exists (To_String (Self.Path)) then
         Delete_Tree (To_String (Self.Path));
      end if;
   end Finalize;

   -------------------
   -- Build_Command --
   -------------------

   function Build_Command
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List)
      return GNATCOLL.OS.Process.Argument_List
   is
      Target : constant String := To_String (Opts.Target);
      Cmd    : GNATCOLL.OS.Process.Argument_List;
   begin
      Cmd.Append ("gprbuild");
      Cmd.Append ("-p");
      Cmd.Append ("-P");
      Cmd.Append (Project_Path);
      if Opts.Quiet then
         Cmd.Append ("-q");
      end if;
      if Target /= "" then
         Cmd.Append ("--target=" & Target);
      end if;
      if Length (Opts.RTS) > 0 then
         Cmd.Append ("--RTS=" & To_String (Opts.RTS));
      end if;
      if Length (Opts.Config) > 0 then
         Cmd.Append ("--config=" & To_String (Opts.Config));
      end if;
      Cmd.Append ("-XLIBRARY_TYPE=static");

      --  Compile Aunit and TGen in production mode by default, unless we have
      --  debug mode enabled in gnattest
      if not Utils_Debug.Debug_Flag_1 then
         Cmd.Append ("-XAUNIT_BUILD_MODE=Install");
         Cmd.Append ("-XTGEN_RTS_BUILD_MODE=prod");
      else
         Cmd.Append ("-XAUNIT_BUILD_MODE=Devel");
         Cmd.Append ("-XTGEN_RTS_BUILD_MODE=dev");
      end if;

      for G of Opts.Gargs loop
         Cmd.Append (G);
      end loop;
      for Arg of Extra_Args loop
         Cmd.Append (Arg);
      end loop;
      return Cmd;
   end Build_Command;

   ---------------
   -- Run_Build --
   ---------------

   procedure Run_Build
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List) is
   begin
      Test.Subprocess.Run
        (Build_Command (Opts, Project_Path, Extra_Args), What => "gprbuild");
   end Run_Build;

   --------------------------------
   -- Compiler_Supports_Ada_2022 --
   --------------------------------

   function Compiler_Supports_Ada_2022
     (Opts : Setup_Options; Build_Dir : String) return Boolean
   is
      use Ada.Directories;
      use Ada.Text_IO;

      Probe_Dir : constant String := Compose (Build_Dir, "tgen_probe");
      Probe_GPR : constant String :=
        Compose (Probe_Dir, "tgen_probe", Extension => "gpr");
      Probe_Src : constant String :=
        Compose (Probe_Dir, "tgen_probe", Extension => "adb");
      No_Args   : GNATCOLL.OS.Process.Argument_List;
      F         : File_Type;
   begin
      Create_Path (Probe_Dir);

      Create (F, Out_File, Probe_GPR);
      Put_Line (F, "project Tgen_Probe is");
      Put_Line (F, "   for Source_Dirs use (""."");");
      Put_Line (F, "   for Object_Dir use ""obj"";");
      Put_Line (F, "   package Compiler is");
      Put_Line
        (F, "      for Default_Switches (""Ada"") use (""-gnat2022"");");
      Put_Line (F, "   end Compiler;");
      Put_Line (F, "end Tgen_Probe;");
      Close (F);

      --  Square-bracket aggregates and target names ('@') are the Ada 2022
      --  features the TGen runtime sources use.

      Create (F, Out_File, Probe_Src);
      Put_Line (F, "procedure Tgen_Probe is");
      Put_Line (F, "   S : String (1 .. 4) := [others => ' '];");
      Put_Line (F, "begin");
      Put_Line (F, "   S (1) := 'x';");
      Put_Line (F, "   S := @;");
      Put_Line (F, "end Tgen_Probe;");
      Close (F);

      return
        Test.Subprocess.Run_Status
          (Build_Command (Opts, Probe_GPR, No_Args), Out_To_Null => True)
        = 0;
   end Compiler_Supports_Ada_2022;

   -----------------
   -- Run_Install --
   -----------------

   procedure Run_Install
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List)
   is
      Cmd    : GNATCOLL.OS.Process.Argument_List;
      Prefix : constant String :=
        (if Length (Opts.Prefix) > 0
         then To_String (Opts.Prefix)
         else Gnattest_Prefix);
      Target : constant String := To_String (Opts.Target);

   begin
      Cmd.Append ("gprinstall");
      Cmd.Append ("-p");
      Cmd.Append ("-f");
      Cmd.Append ("--no-build-var");
      Cmd.Append ("-P");
      Cmd.Append (Project_Path);
      Cmd.Append ("--prefix=" & Prefix);
      Cmd.Append ("-XLIBRARY_TYPE=static");
      if Opts.Quiet then
         Cmd.Append ("-q");
      end if;
      if Length (Opts.Config) > 0 then
         Cmd.Append ("--config=" & To_String (Opts.Config));
      end if;
      if Target /= "" then
         Cmd.Append ("--target=" & Target);
      end if;
      if Length (Opts.RTS) > 0 then
         Cmd.Append ("--RTS=" & To_String (Opts.RTS));
      end if;

      --  Install Aunit and TGen in production mode by default, unless we have
      --  debug mode enabled in gnattest
      if not Utils_Debug.Debug_Flag_1 then
         Cmd.Append ("-XAUNIT_BUILD_MODE=Install");
         Cmd.Append ("-XTGEN_RTS_BUILD_MODE=prod");
      else
         Cmd.Append ("-XAUNIT_BUILD_MODE=Devel");
         Cmd.Append ("-XTGEN_RTS_BUILD_MODE=dev");
      end if;

      for Arg of Extra_Args loop
         Cmd.Append (Arg);
      end loop;
      Test.Subprocess.Run (Cmd, What => "gprinstall");
   end Run_Install;

   -----------------------
   -- Aunit_Common_Args --
   -----------------------

   function Aunit_Common_Args
     (Opts : Setup_Options; Profile : Setup_Profile_Type)
      return GNATCOLL.OS.Process.Argument_List
   is
      Result : GNATCOLL.OS.Process.Argument_List;
      Target : constant String := To_String (Opts.Target);
   begin
      if Target /= "" then
         Result.Append ("-XAUNIT_PLATFORM=" & Target);
      end if;
      Result.Append ("-XAUNIT_RUNTIME=" & Setup_Profile_Image (Profile));
      return Result;
   end Aunit_Common_Args;

   ---------------------
   -- Run_Build_AUnit --
   ---------------------

   procedure Run_Build_AUnit
     (Opts : Setup_Options; Profile : Setup_Profile_Type; Build_Dir : String)
   is
   begin
      Run_Build
        (Opts, Build_AUnit_GPR (Build_Dir), Aunit_Common_Args (Opts, Profile));
   end Run_Build_AUnit;

   -----------------------
   -- Run_Install_AUnit --
   -----------------------

   procedure Run_Install_AUnit
     (Opts : Setup_Options; Profile : Setup_Profile_Type; Build_Dir : String)
   is
   begin
      Run_Install
        (Opts, Build_AUnit_GPR (Build_Dir), Aunit_Common_Args (Opts, Profile));
   end Run_Install_AUnit;

   --------------------
   -- Run_Build_TGen --
   --------------------

   --  TGen has no AUNIT_* externals and no cross-compilation knobs; it
   --  only varies on LIBRARY_TYPE. Build the two GPR projects shipped
   --  under share/tgen/tgen_rts/.

   procedure Run_Build_TGen (Opts : Setup_Options; Build_Dir : String) is
      No_Args : GNATCOLL.OS.Process.Argument_List;
   begin
      Run_Build (Opts, Build_TGen_GPR (Build_Dir, "tgen_rts"), No_Args);
      Run_Build
        (Opts, Build_TGen_GPR (Build_Dir, "tgen_marshalling_rts"), No_Args);
   end Run_Build_TGen;

   ----------------------
   -- Run_Install_TGen --
   ----------------------

   procedure Run_Install_TGen (Opts : Setup_Options; Build_Dir : String) is
      No_Args : GNATCOLL.OS.Process.Argument_List;
   begin
      Run_Install (Opts, Build_TGen_GPR (Build_Dir, "tgen_rts"), No_Args);
      Run_Install
        (Opts, Build_TGen_GPR (Build_Dir, "tgen_marshalling_rts"), No_Args);
   end Run_Install_TGen;

   ----------------------
   -- Source_GTest_Dir --
   ----------------------

   function Source_GTest_Dir return String is
      use Ada.Directories;
      Share : constant String := Compose (Gnattest_Prefix, "share");
   begin
      return Compose (Share, "gtest");
   end Source_GTest_Dir;

   --------------------
   -- GTest_Supported --
   --------------------

   function GTest_Supported
     (Opts : Setup_Options; Profile : Setup_Profile_Type) return Boolean
   is (Is_Native (Opts)
       and then Profile = Profile_Full
       and then
         Ada.Directories.Exists
           (Ada.Directories.Compose
              (Ada.Directories.Compose
                 (Ada.Directories.Compose
                    (Ada.Directories.Compose (Source_GTest_Dir, "googletest"),
                     "googletest"),
                  "src"),
               "gtest-all",
               Extension => "cc")));

   ---------------------
   -- Run_Build_GTest --
   ---------------------

   function Run_Build_GTest
     (Opts : Setup_Options; Build_Dir : String) return Boolean
   is
      use Ada.Directories;
      Staged   : constant String := Compose (Build_Dir, "gtest");
      GPR_Path : constant String :=
        Compose
          (Compose (Staged, "gtest_support"), "gtest", Extension => "gpr");
      Cmd      : GNATCOLL.OS.Process.Argument_List;
   begin
      Cmd.Append ("gprbuild");
      Cmd.Append ("-p");
      Cmd.Append ("-P");
      Cmd.Append (GPR_Path);
      if Opts.Quiet then
         Cmd.Append ("-q");
      end if;
      if Length (Opts.Config) > 0 then
         Cmd.Append ("--config=" & To_String (Opts.Config));
      end if;
      for G of Opts.Gargs loop
         Cmd.Append (G);
      end loop;
      return Test.Subprocess.Run_Status (Cmd) = 0;
   end Run_Build_GTest;

   ------------------
   -- Install_GTest --
   ------------------

   procedure Install_GTest (Opts : Setup_Options; Build_Dir : String) is
      C_Opts : Setup_Options := Opts;
      Extra  : GNATCOLL.OS.Process.Argument_List;
   begin
      --  C libraries do not use the Ada runtime selected by --RTS.
      C_Opts.RTS := Null_Unbounded_String;
      Extra.Append ("-m");
      Run_Install
        (C_Opts,
         Ada.Directories.Compose
           (Ada.Directories.Compose
              (Ada.Directories.Compose (Build_Dir, "gtest"), "gtest_support"),
            "gtest",
            Extension => "gpr"),
         Extra);
   end Install_GTest;

   ----------------------
   -- Source_Unity_Dir --
   ----------------------

   function Source_Unity_Dir return String is
      use Ada.Directories;
   begin
      return Compose (Compose (Gnattest_Prefix, "share"), "unity");
   end Source_Unity_Dir;

   ---------------------
   -- Unity_Supported --
   ---------------------

   function Unity_Supported return Boolean
   is (Ada.Directories.Exists
         (Ada.Directories.Compose
            (Ada.Directories.Compose
               (Ada.Directories.Compose (Source_Unity_Dir, "unity"), "src"),
             "unity",
             Extension => "c")));

   ---------------------
   -- Run_Build_Unity --
   ---------------------

   function Run_Build_Unity
     (Opts : Setup_Options; Build_Dir : String) return Boolean
   is
      use Ada.Directories;
      Target   : constant String := To_String (Opts.Target);
      Staged   : constant String := Compose (Build_Dir, "unity");
      GPR_Path : constant String :=
        Compose
          (Compose (Staged, "unity_support"),
           "gnattest_unity",
           Extension => "gpr");
      Cmd      : GNATCOLL.OS.Process.Argument_List;
   begin
      Cmd.Append ("gprbuild");
      Cmd.Append ("-p");
      Cmd.Append ("-P");
      Cmd.Append (GPR_Path);
      Cmd.Append
        ("-XGNATTEST_UNITY_HOSTED="
         & (if Is_Native (Opts) then "true" else "false"));
      if Opts.Quiet then
         Cmd.Append ("-q");
      end if;

      --  Unity is C only: --RTS, which names an Ada runtime, does not apply

      if not Is_Native (Opts) then
         Cmd.Append ("--target=" & Target);
      end if;
      if Length (Opts.Config) > 0 then
         Cmd.Append ("--config=" & To_String (Opts.Config));
      end if;
      for G of Opts.Gargs loop
         Cmd.Append (G);
      end loop;
      return Test.Subprocess.Run_Status (Cmd) = 0;
   end Run_Build_Unity;

   -------------------
   -- Install_Unity --
   -------------------

   procedure Install_Unity (Opts : Setup_Options; Build_Dir : String) is
      C_Opts : Setup_Options := Opts;
      Extra  : GNATCOLL.OS.Process.Argument_List;
   begin
      --  C libraries do not use the Ada runtime selected by --RTS.
      C_Opts.RTS := Null_Unbounded_String;
      Extra.Append ("-m");
      Extra.Append
        ("-XGNATTEST_UNITY_HOSTED="
         & (if Is_Native (Opts) then "true" else "false"));
      Run_Install
        (C_Opts,
         Ada.Directories.Compose
           (Ada.Directories.Compose
              (Ada.Directories.Compose (Build_Dir, "unity"), "unity_support"),
            "gnattest_unity",
            Extension => "gpr"),
         Extra);
   end Install_Unity;

   ---------
   -- Run --
   ---------

   procedure Run is

      --  Build the args we'll feed to the gnattest framework parser, with
      --  the leading "setup" word stripped and any trailing "-gargs ..."
      --  peeled off into a separate vector.

      Setup_Args : String_Vector;
      Gargs      : GNATCOLL.OS.Process.Argument_List;
      In_Gargs   : Boolean := False;

      Cmd :
        Utils.Command_Lines.Command_Line
          (Test.Command_Lines.Descriptor'Access);
   begin
      for I in 2 .. Ada.Command_Line.Argument_Count loop
         declare
            A : constant String := Ada.Command_Line.Argument (I);
         begin
            if In_Gargs then
               Gargs.Append (A);
            elsif A = "-gargs" then
               In_Gargs := True;
            else
               Setup_Args.Append (A);
            end if;
         end;
      end loop;

      Parse
        (Setup_Args, Cmd, Phase => Cmd_Line_1, Collect_File_Names => False);

      for Dbg of Test_String_Seq_Switches.Arg (Cmd, Debug) loop
         Utils_Debug.Set_Debug_Options (Dbg.all);
      end loop;

      if Arg (Cmd, Help) then
         Print_Help;
         GNAT.OS_Lib.OS_Exit (0);
      end if;

      if Arg (Cmd, Verbose) then
         Test.Common.Verbose := True;
      end if;

      --  The setup subcommand bypasses the regular gnattest initialization, so
      --  Tool_Temp_Dir is still null here. Create it explicitly as we use it
      --  as a directory for temporary sources.

      Utils.Environment.Create_Temp_Dir;

      declare
         Opts    : Setup_Options;
         Profile : Setup_Profile_Type;
         Build   : Build_Dir_Type;
      begin
         Opts.Target := To_Unbounded_String (Deref (Arg (Cmd, Target)));
         Opts.RTS := To_Unbounded_String (Deref (Arg (Cmd, Run_Time_System)));
         Opts.Config := To_Unbounded_String (Deref (Arg (Cmd, Config)));
         Opts.Prefix := To_Unbounded_String (Deref (Arg (Cmd, Prefix)));
         Opts.Profile := Arg (Cmd, Rts_Profile);
         Opts.Verbose := Arg (Cmd, Verbose);
         Opts.Quiet := Arg (Cmd, Quiet);
         Opts.Gargs := Gargs;
         Opts.Compiler_Prefix := Arg (Cmd, Compiler_Prefix);
         Opts.Tgen_Mode :=
           (if not Explicit (Cmd, Tgen)
            then Tgen_Auto
            elsif Arg (Cmd, Tgen)
            then Tgen_Build
            else Tgen_Skip);

         if Present (Arg (Cmd, Lang)) then
            Opts.Languages := Parse_Languages (Arg (Cmd, Lang).all);
            Opts.Explicit_Languages := True;
         end if;

         --  Resolve --compiler-prefix into an explicit install prefix

         if Opts.Compiler_Prefix then
            Opts.Prefix :=
              To_Unbounded_String (Compiler_Install_Prefix (Opts));
         end if;
         Build.Save_Temps := Arg (Cmd, Save_Temps);

         Profile :=
           (if Opts.Profile = Auto
            then Infer_Profile (Opts)
            else Opts.Profile);

         if Opts.Tgen_Mode = Tgen_Build then
            if not Opts.Languages (Lang_Ada) then
               Fail ("--tgen: the TGen runtime needs ada in --lang");
            elsif not TGen_Supports_Profile (Profile) then
               Fail
                 ("--tgen: the TGen runtime only supports full and embedded"
                  & " Ada runtime profiles");
            end if;
         end if;

         --  Reject an unsupported language before building anything

         if Requested (Opts, Lang_C) and then not Unity_Supported then
            Fail
              ("--lang: cannot set up c: the Unity sources are not shipped"
               & " with this gnattest");
         end if;
         if Requested (Opts, Lang_Cpp)
           and then not GTest_Supported (Opts, Profile)
         then
            Fail
              ("--lang: cannot set up c++: Google Test is only supported for"
               & " the native full runtime, with the sources shipped with"
               & " gnattest");
         end if;

         --  Stage sources into the temp build directory. We never build in
         --  place: the install tree must stay clean of object and library
         --  artifacts, and concurrent setups for different targets/profiles
         --  must not collide.

         declare
            Build_Dir : constant String := To_String (Build.Path);
         begin
            if Opts.Verbose then
               Ada.Text_IO.Put_Line
                 ("gnattest setup: build dir     = " & Build_Dir);
            end if;

            if Opts.Languages (Lang_Ada) then
               Copy_Sources (Src => Source_AUnit_Dir, Dst_Parent => Build_Dir);

               declare
                  Aunit_GPR : constant String := Build_AUnit_GPR (Build_Dir);
               begin
                  if Opts.Verbose then
                     Ada.Text_IO.Put_Line
                       ("gnattest setup: AUnit profile = "
                        & Setup_Profile_Image (Profile));
                     Ada.Text_IO.Put_Line
                       ("gnattest setup: AUnit project = " & Aunit_GPR);
                  end if;

                  --  Make aunit_shared.gpr discoverable to gprbuild via the
                  --  directory containing the staged aunit.gpr.

                  declare
                     use Ada.Environment_Variables;
                     Lib_Gnat_Dir : constant String :=
                       Ada.Directories.Containing_Directory (Aunit_GPR);
                     Existing     : constant String :=
                       (if Exists ("GPR_PROJECT_PATH")
                        then Value ("GPR_PROJECT_PATH")
                        else "");
                     New_Value    : constant String :=
                       (if Existing = ""
                        then Lib_Gnat_Dir
                        else
                          Lib_Gnat_Dir
                          & GNAT.OS_Lib.Path_Separator
                          & Existing);
                  begin
                     Set ("GPR_PROJECT_PATH", New_Value);
                  end;
               end;

               Run_Build_AUnit (Opts, Profile, Build_Dir);
               Run_Install_AUnit (Opts, Profile, Build_Dir);

               --  The TGen runtime needs Ada 2022 support, including when
               --  explicitly requested with --tgen.

               declare
                  Build_TGen : Boolean :=
                    Opts.Tgen_Mode = Tgen_Build
                    or else
                      (Opts.Tgen_Mode = Tgen_Auto
                       and then TGen_Supports_Profile (Profile));
               begin
                  if Build_TGen
                    and then not Compiler_Supports_Ada_2022 (Opts, Build_Dir)
                  then
                     Build_TGen := False;
                     if not Opts.Quiet then
                        Ada.Text_IO.Put_Line
                          ("gnattest setup: Ada 2022 probe failed; skipping"
                           & " the TGen runtime");
                     end if;
                  end if;

                  if Build_TGen then
                     if Opts.Verbose then
                        Ada.Text_IO.Put_Line
                          ("gnattest setup: also building TGen runtime");
                     end if;
                     Copy_Sources
                       (Src => Source_TGen_Dir, Dst_Parent => Build_Dir);
                     Run_Build_TGen (Opts, Build_Dir);
                     Run_Install_TGen (Opts, Build_Dir);
                  end if;
               end;
            end if;

            --  Google Test, for C++ tests. Native + full runtime only: it
            --  needs a hosted C++ runtime. Unless c++ is in --lang, a
            --  toolchain without a C++ compiler only skips it.

            if not Opts.Languages (Lang_Cpp) then
               null;
            elsif GTest_Supported (Opts, Profile) then
               if Opts.Verbose then
                  Ada.Text_IO.Put_Line
                    ("gnattest setup: also building Google Test");
               end if;
               Copy_Sources (Src => Source_GTest_Dir, Dst_Parent => Build_Dir);
               if Run_Build_GTest (Opts, Build_Dir) then
                  Install_GTest (Opts, Build_Dir);
               elsif Requested (Opts, Lang_Cpp) then
                  Fail
                    ("--lang: cannot set up c++: could not build Google Test,"
                     & " which needs a C++ compiler");
               elsif not Opts.Quiet then
                  Ada.Text_IO.Put_Line
                    ("gnattest setup: could not build Google Test, which"
                     & " needs a C++ compiler; skipping it.");
               end if;
            elsif not Ada.Directories.Exists (Source_GTest_Dir) then
               if Opts.Verbose then
                  Ada.Text_IO.Put_Line
                    ("gnattest setup: Google Test sources not shipped with"
                     & " this gnattest; skipping (C/C++ tests will need a"
                     & " system gtest).");
               end if;
            elsif Opts.Verbose then
               Ada.Text_IO.Put_Line
                 ("gnattest setup: skipping Google Test (only supported for"
                  & " the native full runtime).");
            end if;

            --  Unity, used by the C test driver

            if not Opts.Languages (Lang_C) then
               null;
            elsif Unity_Supported then
               if Opts.Verbose then
                  Ada.Text_IO.Put_Line ("gnattest setup: also building Unity");
               end if;
               Copy_Sources (Src => Source_Unity_Dir, Dst_Parent => Build_Dir);
               if Run_Build_Unity (Opts, Build_Dir) then
                  Install_Unity (Opts, Build_Dir);
               elsif Requested (Opts, Lang_C) then
                  Fail
                    ("--lang: cannot set up c: could not build Unity, which"
                     & " needs a C compiler");
               elsif not Opts.Quiet then
                  Ada.Text_IO.Put_Line
                    ("gnattest setup: could not build Unity, which needs a C"
                     & " compiler; skipping it.");
               end if;
            elsif Opts.Verbose then
               Ada.Text_IO.Put_Line
                 ("gnattest setup: skipping Unity (sources not shipped with"
                  & " this gnattest).");
            end if;
         end;

         --  Remove Tool_Temp_Dir

         if not Build.Save_Temps then
            Utils.Environment.Clean_Up;
         end if;
      end;
   end Run;

end Test.Setup;
