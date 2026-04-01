package Pkg is

   Val : aliased Integer := 0;

   type My_Int is new Integer;

   type Int_Acc is access all Integer;

   function Make_Int (X : Integer) return My_Int;

   function Access_It return Int_Acc with
   Global => Pkg.Val;

   procedure Print_My_Int (X : My_Int);

   procedure Print_Int_Acc (Acc : Int_Acc);

end Pkg;
