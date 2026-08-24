package Test.Stub.Write is

   --  Child package of Test.Stub which specifically is used to generate
   --  the stubbing files.

   procedure Generate_Body_Stub
     (Body_File_Name : String;
      Data           : Stubbing_Data;
      Markered_Data  : in out MD_Map);
   --  Generates stub body

   procedure Generate_Stub_Data
     (Stub_Data_File_Spec : String;
      Stub_Data_File_Body : String;
      Data                : Stubbing_Data);
   --  Generates Stub_Data package which contains setters

end Test.Stub.Write;
