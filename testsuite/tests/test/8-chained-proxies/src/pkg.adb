package body Pkg is

   function Make_T1 (X : Integer) return T1 is (T1 (X));
   function Make_T2_From_T1 (Val : T1) return T2 is (T2 (Val));
   procedure Consume_T2 (Val : T2) is null;

end Pkg;
