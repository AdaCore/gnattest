package Pkg is

   type Root1 is record
      X : Integer;
      Y : Float;
   end record;

   subtype Foo1 is Root1;

   subtype Bar1 is Foo1;

   procedure Test1 (Val : Bar1);

   type Root2 is tagged record
      X : Integer;
      Y : Float;
   end record;

   subtype Foo2 is Root2;

   subtype Bar2 is Foo2;

   procedure Test2 (Val : Bar2);
end Pkg;
