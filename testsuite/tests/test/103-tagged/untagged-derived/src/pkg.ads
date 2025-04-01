package Pkg is

   type Rec (DDD : Boolean) is record
      A : Integer;
   end record;

    type Extension is new Rec;

   function Foo (R : Extension) return Integer;

end Pkg;
