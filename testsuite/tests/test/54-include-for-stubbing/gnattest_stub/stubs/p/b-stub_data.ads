--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

pragma Ada_2012;
--  begin read only
--  end read only

package b.Stub_Data is
   type String_Access is access all String;

--  begin read only
   --  id:2.2/04/33df42ff6e5288b1/e9d71f5ee7c92d6d/0/func_b/
--  end read only
   type Stub_Data_Type_func_b_33df42_e9d71f is record
      func_b_Result : String_Access;

      Stub_Counter : Natural := 0;
   end record;
   Stub_Data_func_b_33df42_e9d71f : Stub_Data_Type_func_b_33df42_e9d71f;
   procedure Set_Stub_func_b_33df42_e9d71f
     (func_b_Result : String_Access := Stub_Data_func_b_33df42_e9d71f.func_b_Result);
--  begin read only
--  end read only

end b.Stub_Data;
