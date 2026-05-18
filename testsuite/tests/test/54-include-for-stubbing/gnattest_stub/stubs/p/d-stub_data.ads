--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

pragma Ada_2012;
--  begin read only
--  end read only

package d.Stub_Data is
   type String_Access is access all String;

--  begin read only
   --  id:2.2/04/ad0ec9ab08c616df/3c363836cf4e1666/0/show_b/
--  end read only
   type Stub_Data_Type_show_b_ad0ec9_3c3638 is record
      show_b_Result : String_Access;

      Stub_Counter : Natural := 0;
   end record;
   Stub_Data_show_b_ad0ec9_3c3638 : Stub_Data_Type_show_b_ad0ec9_3c3638;
   procedure Set_Stub_show_b_ad0ec9_3c3638
     (show_b_Result : String_Access := Stub_Data_show_b_ad0ec9_3c3638.show_b_Result);
--  begin read only
--  end read only

--  begin read only
   --  id:2.2/04/0921f1dff799818f/3c363836cf4e1666/0/show_c/
--  end read only
   type Stub_Data_Type_show_c_0921f1_3c3638 is record
      show_c_Result : String_Access;

      Stub_Counter : Natural := 0;
   end record;
   Stub_Data_show_c_0921f1_3c3638 : Stub_Data_Type_show_c_0921f1_3c3638;
   procedure Set_Stub_show_c_0921f1_3c3638
     (show_c_Result : String_Access := Stub_Data_show_c_0921f1_3c3638.show_c_Result);
--  begin read only
--  end read only

end d.Stub_Data;
