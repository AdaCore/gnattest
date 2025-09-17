package Pkg is

   type Rec (D : Boolean) is tagged record
      I : Integer;
   end record;

   function Foo (R : Rec) return Integer;

end Pkg;
