package Pkg is

   type My_Boolean is new Boolean;
   type My_Integer is new Integer;

   type T1 is tagged record
      A : My_Boolean;
   end record;

   type T2 is new T1 with record
     B : Boolean;
   end record;

   type T3 is new T2 with record
     C : My_Integer;
   end record;

   type T4 is new T3 with record
     D : Integer;
   end record;

   procedure Foo (R : T4);

end Pkg;
