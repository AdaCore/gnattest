package Pkg is

   type T1 is tagged record
      A : Integer;
   end record;

   type T2 is new T1 with record
     B : Boolean;
     C : Integer;
   end record;

   procedure Foo (R : T2);

end Pkg;
