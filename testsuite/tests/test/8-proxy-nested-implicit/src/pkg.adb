package body Pkg is

   function Make_Acc (Val : Val_T) return Val_Acc is
   begin
      return new Val_T'(Val);
   end Make_Acc;

   procedure Print_Arr (Arr : Arr_T) is
   begin
      null;
   end Print_Arr;

   procedure Print_Rec (Rec : Rec_T) is
   begin
      null;
   end Print_Rec;

end Pkg;
