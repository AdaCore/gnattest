package Pkg is

   type Index_T is new Integer range 1 .. 10;

   type Val_T is new Integer range 1 .. 100;

   type Val_Acc is access all Val_T;

   type Arr_T is array (Index_T range <>) of Val_Acc;

   type Rec_T (Disc : Index_T) is record
      Index : Index_T;
      First_Acc : Val_Acc;
      case Disc is
         when 1 .. 9 =>
            Comp : Val_Acc;
         when 10 =>
            Other_Stuff : Val_T;
      end case;
   end record;

   function Make_Acc (Val : Val_T) return Val_Acc;

   procedure Print_Arr (Arr : Arr_T);

   procedure Print_Rec (Rec : Rec_T);
end Pkg;
