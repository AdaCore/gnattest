with Pkg;

package Pkh is

   type Nested is record
      Comp : Pkg.Opaque;
   end record;

   function Qux (X : Nested) return Pkg.Opaque is (X.Comp);

end Pkh;
