pragma Ada_2012;
with Interfaces.C;

package Expr_Func is

   function Identity (X : Integer) return Integer is (X);
   --  Body is not expected; shouldn't be stubbed.

end Expr_Func;
