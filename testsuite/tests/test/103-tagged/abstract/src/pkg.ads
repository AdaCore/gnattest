package Pkg is

   type Rec is tagged record
      X : Integer;
      Y : Float;
   end record;

   procedure Not_Abstract (Val : Rec);

   type Root is abstract tagged record
      X : Integer;
      Y : Float;
   end record;

   procedure Test_Root (Val : Root);

   subtype Foo is Root;

   subtype Bar is Foo;

  procedure Test_Bar (Val : Bar);

   type Derived is new Root with record
      Z : Boolean;
   end record;

   procedure Test_Derived (Val : Derived);
end Pkg;
