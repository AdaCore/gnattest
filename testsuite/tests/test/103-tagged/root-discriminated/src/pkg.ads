package Pkg is

   type Rec (DDD : Boolean) is tagged record
      A : Integer;
   end record;

    type Extension is new Rec with record
     B : Float;
   end record;

   function Foo (R : Extension) return Integer;
   --function Bar (R : Rec) return Integer;

end Pkg;
