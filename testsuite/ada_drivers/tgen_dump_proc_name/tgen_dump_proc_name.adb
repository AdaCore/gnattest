with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Strings;

with GPR2;
with GPR2.Project.Tree;
with GPR2.Options;

with Libadalang.Analysis;
with Libadalang.Project_Provider;

with Test.Generation;
with Test.Common;

with TGen.Libgen;
with TGen.Strings;

procedure TGen_Dump_Proc_Name is
   package LAL renames Libadalang.Analysis;

   function Load_Project return LAL.Unit_Provider_Reference;

   function Load_Project return LAL.Unit_Provider_Reference is
      package LAL_GPR renames Libadalang.Project_Provider;

      Project_Filename : constant String := Ada.Command_Line.Argument (1);

      Opts     : GPR2.Options.Object;
      Prj_Tree : GPR2.Project.Tree.Object;
   begin
      Opts.Add_Switch (GPR2.Options.P, Project_Filename);
      if not Prj_Tree.Load
               (Options              => Opts,
                Artifacts_Info_Level => GPR2.Sources_Units,
                With_Runtime         => True)
      then
         raise Program_Error
           with "aborted: could not load project " & Project_Filename;
      end if;
      return LAL_GPR.Create_Project_Unit_Provider (Tree => Prj_Tree);
   end Load_Project;

   Context : constant LAL.Analysis_Context :=
     LAL.Create_Context (Unit_Provider => Load_Project);

begin
   for I in 3 .. Ada.Command_Line.Argument_Count loop
      declare
         Filename : constant String := Ada.Command_Line.Argument (I);
         Unit     : constant LAL.Analysis_Unit :=
           Context.Get_From_File (Filename);
      begin
         Test.Generation.Process_Source (Unit);
      end;
   end loop;

   Ada.Text_IO.Put_Line
     (Ada.Strings.Unbounded.To_String
        (TGen.Libgen.Get_Test_Case_Dump_Procedure_Name
           (Test.Common.TGen_Libgen_Ctx,
            TGen.Strings.To_Qualified_Name ("User"),
            Ada.Strings.Unbounded.To_Unbounded_String ("User.Identity"))));
   Ada.Text_IO.Put_Line
     (Ada.Strings.Unbounded.To_String
        (TGen.Libgen.Get_Test_Case_Dump_Procedure_Name
           (Test.Common.TGen_Libgen_Ctx,
            TGen.Strings.To_Qualified_Name ("user_instantiation"),
            Ada.Strings.Unbounded.To_Unbounded_String
              ("user_instantiation.Plus_Two"))));
end TGen_Dump_Proc_Name;
