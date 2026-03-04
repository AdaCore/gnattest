--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

pragma Ada_2012;
--  begin read only
--  end read only

package c.Stub_Data is
   type String_Access is access all String;

--  begin read only
   --  id:2.2/04/15c5a03d0768af47/84a516841ba77a5b/0/func_c/
--  end read only
   type Stub_Data_Type_func_c_15c5a0_84a516 is record
      func_c_Result : String_Access;

      Stub_Counter : Natural := 0;
   end record;
   Stub_Data_func_c_15c5a0_84a516 : Stub_Data_Type_func_c_15c5a0_84a516;
   procedure Set_Stub_func_c_15c5a0_84a516
     (func_c_Result : String_Access := Stub_Data_func_c_15c5a0_84a516.func_c_Result);
--  begin read only
--  end read only

end c.Stub_Data;
