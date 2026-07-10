package Foo is

   function Is_Valid (X : Integer) return Boolean with Ghost;

   function Compute (X : Integer) return Integer
   with Pre => Is_Valid (X);

end Foo;
