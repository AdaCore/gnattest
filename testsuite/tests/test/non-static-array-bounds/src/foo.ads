package Foo is
   function Size return Natural
   is (4);
   Count : constant Natural := Size;

   type Bit_Array is array (Integer range <>) of Boolean;
   subtype A is Bit_Array (1 .. Count);
   subtype B is Bit_Array (Count .. Count + 1);
   subtype C is Bit_Array (Count .. 9);
   subtype D is Bit_Array (Count - 1 .. Count + 1);
   subtype E is Bit_Array (2 .. 5);

   type Wide_Index is range 0 .. 2 ** 40;
   Wide_Count : constant Wide_Index := 2 ** 35 + Wide_Index (Size);
   type Wide_Array is array (Wide_Index range <>) of Boolean;
   subtype F is Wide_Array (Wide_Count .. Wide_Count + 1);

   type Matrix is array (Integer range <>, Integer range <>) of Boolean;
   subtype G is Matrix (2 .. 5, 1 .. Count);

   type With_Range is record
      Value : Integer range Count - 1 .. Count + 1;
   end record;

   type Color is (Red, Green, Blue, White);
   Last_Color : constant Color := Color'Val (Size - 2);
   type Color_Array is array (Color range <>) of Boolean;
   subtype Enumeration_Bound is Color_Array (Red .. Last_Color);

   procedure Check_Enumeration (Arr : Enumeration_Bound);
   procedure Check_A (Arr : A);
   procedure Check_B (Arr : B);
   procedure Check_C (Arr : C);
   procedure Check_D (Arr : D);
   procedure Check_E (Arr : E);
   procedure Check_F (Arr : F);
   procedure Check_G (Arr : G);
   procedure Check_Record (Arr : With_Range);
end Foo;
