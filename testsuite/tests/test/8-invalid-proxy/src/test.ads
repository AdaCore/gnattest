with Pkg; use Pkg;

package Test is

   function Test_Mismatched_Ret_Typ (X : Mismatched_Ret_Typ) return Boolean is (True);

   function Test_Unsupported_Params (X : Unsupported_Params) return Boolean is (True);

   function Test_Out_Param (X : Out_Param) return Boolean is (True);

   function Test_Missing_Pxy (X : Missing_Pxy) return Boolean is (True);

end Test;
