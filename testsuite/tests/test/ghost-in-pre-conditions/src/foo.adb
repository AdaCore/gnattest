package body Foo is

   function Is_Valid (X : Integer) return Boolean is (X >= 0);

   function Compute (X : Integer) return Integer is (X + 1);

end Foo;
