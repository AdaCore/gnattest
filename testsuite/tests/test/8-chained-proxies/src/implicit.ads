package Implicit is
   type T3 is new Integer;
   type T4 is new Integer;
   function Make_T3 (X : Integer) return T3;
   function Make_T4_From_T3 (Val : T3) return T4;
   procedure Consume_T4(Val : T4);
end Implicit;
