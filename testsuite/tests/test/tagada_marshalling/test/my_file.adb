package body My_File is

   procedure Test
     (X       : in out R;
      Y       : T2;
      A       : String;
      M       : Matrix;
      Z       : R2;
      D       : Shape;
      V       : Shape_Array;
      Mod_Val : Non_Static_Mod)
   is null;

   procedure Use_Null_Rec (X : T_Null) is null;

end My_File;
