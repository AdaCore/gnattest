with Pkg; use Pkg;

package Pkh is

   function Access_It return Int_Acc with
   Global => Pkg.Val;

end Pkh;
