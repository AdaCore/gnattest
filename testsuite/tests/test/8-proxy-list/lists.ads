package Lists is

   type DLL;

   type DLL_Access is access all DLL
     with TGen_Proxy => To_DLL;

   type DLL is record
      Next, Prev : DLL_Access;
      Value : Integer;
   end record;

   type Int_Array is array (Positive range <>) of Integer;

   function To_DLL (Arr : Int_Array) return DLL_Access;

   procedure Check_And_Print_DLL (List : DLL_Access);

end Lists;
