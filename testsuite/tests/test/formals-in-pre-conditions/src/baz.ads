generic
   with function Allowed (X : Integer) return Boolean;
package Baz is
   function Compute (X : Integer) return Integer
   with Pre => Allowed (X);
end Baz;
