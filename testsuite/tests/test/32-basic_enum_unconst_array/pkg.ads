package Pkg is

   type Int_Arr_Type is array (Integer range <>) of Integer;

   procedure Process (Int_Arr : Int_Arr_Type);

   type Disc_Rec_With_Constr_Type (I : Integer) is record
      Arr : Int_Arr_Type (1 .. I);
   end record;

   procedure Process (Disc_Rec_With_Constr : Disc_Rec_With_Constr_Type);

   type Rec_With_Constr_Rec_Type is record
      Disc_Rec_With_Constr : Disc_Rec_With_Constr_Type (1);
   end record;

   procedure Process (Rec_With_Constr_Rec : Rec_With_Constr_Rec_Type);

end Pkg;
