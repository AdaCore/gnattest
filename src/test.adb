with GPR2; use GPR2;
with GPR2.Project.Registry.Attribute;
with GPR2.Project.Registry.Attribute.Description;
with GPR2.Project.Registry.Pack;
with GPR2.Project.Registry.Pack.Description;

with Utils.Projects; use Utils.Projects;

package body Test is

   ----------------------------------
   -- Register_Specific_Attributes --
   ----------------------------------

   procedure Register_Specific_Attributes is
      package GPR2_RA renames GPR2.Project.Registry.Attribute;
      package GPR2_RP renames GPR2.Project.Registry.Pack;
   begin
      GPR2_RP.Add (GPR2_GT_Package, GPR2_RP.Everywhere);
      GPR2_RP.Description.Set_Package_Description
        (GPR2_GT_Package,
         "Specifies options used when calling the 'gnattest' program.");

      GPR2_RA.Add
        (Name                 => +Default_Switches_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.List,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Default_Switches_Attr, "Switches passed to gnattest invocations.");

      GPR2_RA.Add
        (Name                 => +Switches_Attr,
         Index_Type           => GPR2_RA.String_Index,
         Value                => GPR2_RA.List,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Switches_Attr,
         "Switches passed to gnattest invocations for a specific file.");

      GPR2_RA.Add
        (Name                 => +Harness_Dir_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Harness_Dir_Attr, "Directory containing the gnattest harness.");

      GPR2_RA.Add
        (Name                 => +Subdir_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Subdir_Attr,
         "Subdirectory corresponding to the source directory where to generate"
         & " test packages.");

      GPR2_RA.Add
        (Name                 => +Tests_Root_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Tests_Root_Attr,
         "Directory hosting the hierarchy of test packages.");

      GPR2_RA.Add
        (Name                 => +Tests_Dir_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Tests_Dir_Attr, "Directory containing all test packages.");

      GPR2_RA.Add
        (Name                 => +Additional_Tests_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Additional_Tests_Attr,
         "List of projects containing additional tests to be added to the"
         & " testsuite.");

      GPR2_RA.Add
        (Name                 => +Stubs_Dir_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Stubs_Dir_Attr, "Directory in which stubbed units are generated.");

      GPR2_RA.Add
        (Name                 => +Skeletons_Default_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Skeletons_Default_Attr,
         "Default behavior of test skeletons (pass or fail).");

      GPR2_RA.Add
        (Name                 => +Stub_Inclusion_List_Attr,
         Index_Type           => GPR2_RA.String_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Stub_Exclusion_List_Attr,
         "List of spec:filename that should be stubbed.");

      GPR2_RA.Add
        (Name                 => +Stub_Exclusion_List_Attr,
         Index_Type           => GPR2_RA.String_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Stub_Exclusion_List_Attr,
         "List of spec:filename that should not be stubbed.");

      GPR2_RA.Add
        (Name                 => +Default_Stub_Inclusion_List_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Default_Stub_Inclusion_List_Attr,
         "Response file to specify a stub inclusion list.");

      GPR2_RA.Add
        (Name                 => +Default_Stub_Exclusion_List_Attr,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
      GPR2_RA.Description.Set_Attribute_Description
        (+Default_Stub_Exclusion_List_Attr,
         "Response file to specify a stub exclusion list.");

      --  Not really a gnattest specific attribute, but we still need to
      --  inherit makefile attribute in test driver.

      declare
         GPR2_Make_Package : constant GPR2.Package_Id := +Name_Type'("make");
      begin
         GPR2_RP.Add (GPR2_Make_Package, GPR2_RP.Everywhere);
         GPR2_RA.Add
           (Name                 =>
              (Pack => GPR2_Make_Package,
               Attr => GPR2."+" (GPR2.Name_Type'("makefile"))),
            Index_Type           => GPR2_RA.No_Index,
            Value                => GPR2_RA.Single,
            Value_Case_Sensitive => True,
            Is_Allowed_In        => GPR2_RA.Everywhere);
      end;

      --  Needed for gnatcov integration

      GPR2_RP.Add (+Name_Type'("coverage"), GPR2_RP.Everywhere);
      GPR2_RA.Add
        (Name                 => Coverage_Switches,
         Index_Type           => GPR2_RA.File_Index,
         Value                => GPR2_RA.List,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);

      GPR2_RP.Add (+Name_Type'("emulator"), GPR2_RP.Everywhere);
      GPR2_RA.Add
        (Name                 => Emulator_Board,
         Index_Type           => GPR2_RA.No_Index,
         Value                => GPR2_RA.Single,
         Value_Case_Sensitive => True,
         Is_Allowed_In        => GPR2_RA.Everywhere);
   end Register_Specific_Attributes;
end Test;
