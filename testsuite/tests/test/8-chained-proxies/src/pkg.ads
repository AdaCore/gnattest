package Pkg is
   type T1 is new Integer with TGen_Proxy => Make_T1;
   type T2 is new Integer with TGen_Proxy => Make_T2_From_T1;
   function Make_T1 (X : Integer) return T1;
   function Make_T2_From_T1 (Val : T1) return T2;
   procedure Consume_T2 (Val : T2);
end Pkg;
