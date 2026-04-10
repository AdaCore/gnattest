package body Pkg is

   function Make_Int (X : Integer) return My_Int is (My_Int (X));

   procedure Print_My_Int (X : My_Int) is
   begin
      null;
   end Print_My_Int;

   function Access_It return Int_Acc is
   begin
      return Val'Access;
   end Access_It;

   procedure Print_Int_Acc (Acc : Int_Acc) is
   begin
      null;
   end Print_Int_Acc;

end Pkg;
