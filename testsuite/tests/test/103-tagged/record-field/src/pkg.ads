package Pkg is

   type Rec is record
      I : Integer;
      J : Float;
   end record;

   --  Field of non-tagged recor type
   type T1 is tagged record
      A : Integer;
      B : Rec;
   end record;

   function Foo (R : T1) return Integer;

   --  Tagged record with a field of tagged record type.
   type T2 is new T1 with record
      C : Integer;
      D : Rec; 
   end record;

   function Bar (R : T2) return Integer;

   --  Derived type with fields of the two previously described kinds
   type T3 is new T2 with record
     E : T1;
     F : T2;
   end record;

   function Baz (R : T3) return Integer;

end Pkg;
