package Pkg is

   Val : aliased Integer := 0;

   type Int_Acc is access all Integer;

   procedure Print_Int_Acc (Acc : Int_Acc);

end Pkg;
