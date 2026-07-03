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

with GPR2; use GPR2;
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
with Utils.String_Utilities; use Utils.String_Utilities;
with Utils.Tool_Names;
with Utils_Debug;

package body Test.Setup is

   --  The runtime-profile enum and its --rts-profile switch live in
   --  Test.Command_Lines so the framework can parse the switch directly.

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
   end record;

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

   function Gnattest_Prefix return String;
   --  Return the install prefix of gnattest

   function Compiler_Install_Prefix (Opts : Setup_Options) return String;
   --  Return the install prefix of the Ada compiler that will build the
   --  library according to Opts.

   procedure Run_Build
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List);
   --  Common build helper

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

   ----------------
   -- Print_Help --
   ----------------

   procedure Print_Help is
      use Ada.Text_IO;
   begin
      Put_Line ("Usage: gnattest setup [options]");
      New_Line;
      Put_Line ("Build and install the bundled AUnit library for a given");
      Put_Line ("target / RTS combination. In native mode, also build and");
      Put_Line ("install the TGen runtime.");
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

      --  A minimal Ada project so that loading it autoconfigures the Ada
      --  compiler for the requested target/RTS. We then read the resulting
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
         Put_Line (F, "   for Languages use (""Ada"");");
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
              Index =>
                GPR2.Project.Attribute_Index.Create (GPR2.Ada_Language));
      begin
         if not Attr.Is_Defined then
            Fail ("--compiler-prefix: no Ada compiler driver in config");
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
         Fail ("could not copy sources to " & Target);
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

   ---------------
   -- Run_Build --
   ---------------

   procedure Run_Build
     (Opts         : Setup_Options;
      Project_Path : String;
      Extra_Args   : GNATCOLL.OS.Process.Argument_List)
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
      Test.Subprocess.Run (Cmd, What => "gprbuild");
   end Run_Build;

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

         --  Resolve --compiler-prefix into an explicit install prefix

         if Opts.Compiler_Prefix then
            Opts.Prefix :=
              To_Unbounded_String (Compiler_Install_Prefix (Opts));
         end if;

         Profile :=
           (if Opts.Profile = Auto
            then Infer_Profile (Opts)
            else Opts.Profile);

         --  Stage sources into the temp build directory. We never build in
         --  place: the install tree must stay clean of object and library
         --  artifacts, and concurrent setups for different targets/profiles
         --  must not collide.

         Copy_Sources
           (Src => Source_AUnit_Dir, Dst_Parent => To_String (Build.Path));

         declare
            Build_Dir : constant String := To_String (Build.Path);
            Aunit_GPR : constant String := Build_AUnit_GPR (Build_Dir);
         begin
            if Opts.Verbose then
               Ada.Text_IO.Put_Line
                 ("gnattest setup: AUnit profile = "
                  & Setup_Profile_Image (Profile));
               Ada.Text_IO.Put_Line
                 ("gnattest setup: build dir     = " & Build_Dir);
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
                  else Lib_Gnat_Dir & GNAT.OS_Lib.Path_Separator & Existing);
            begin
               Set ("GPR_PROJECT_PATH", New_Value);
            end;

            Run_Build_AUnit (Opts, Profile, Build_Dir);
            Run_Install_AUnit (Opts, Profile, Build_Dir);

            --  In native mode, also stage and build/install the TGen runtimes

            if Is_Native (Opts) then
               if Opts.Verbose then
                  Ada.Text_IO.Put_Line
                    ("gnattest setup: also building TGen runtime (native)");
               end if;
               Copy_Sources (Src => Source_TGen_Dir, Dst_Parent => Build_Dir);
               Run_Build_TGen (Opts, Build_Dir);
               Run_Install_TGen (Opts, Build_Dir);
            end if;
         end;

         --  Remove Tool_Temp_Dir

         Utils.Environment.Clean_Up;
      end;
   end Run;

end Test.Setup;
