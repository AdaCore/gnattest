package Pkg is

   type Mismatched_Ret_Typ is access Integer with
     TGen_Proxy => Mismatched_Ret_Typ_Pxy;

   type Unsupported_Params is access Integer with
     TGen_Proxy => Unsupported_Param_Pxy;

   type Out_Param is access Integer with
     TGen_Proxy => Out_Param_Pxy;

   type Missing_Pxy is access Integer with
     TGen_Proxy => Non_Existent_Function;

   function Mismatched_Ret_Typ_Pxy (X : Integer) return Integer is (X);

   function Unsupported_Param_Pxy
     (X : Missing_Pxy) return Unsupported_Params is
     (null);

   function Out_Param_Pxy (X : Integer; Y : out Integer) return Out_Param is
     (null);

end Pkg;
