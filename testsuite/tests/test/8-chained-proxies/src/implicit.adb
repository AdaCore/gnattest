package body Implicit is

   function Make_T3 (X : Integer) return T3 is (T3 (X));
   function Make_T4_From_T3 (Val : T3) return T4 is (T4 (Val));
   procedure Consume_T4 (Val : T4) is null;

end Implicit;
