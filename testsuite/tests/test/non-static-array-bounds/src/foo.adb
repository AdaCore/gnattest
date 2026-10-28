package body Foo is

   procedure Check_Enumeration (Arr : Enumeration_Bound) is
   begin
      if Arr'First /= Red or else Arr'Last /= Last_Color then
         raise Program_Error with "incorrect enumeration array bounds";
      end if;
   end Check_Enumeration;

   procedure Check_A (Arr : A) is
   begin
      if Arr'First /= 1 or else Arr'Last /= Count then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_A;

   procedure Check_B (Arr : B) is
   begin
      if Arr'First /= Count or else Arr'Last /= Count + 1 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_B;

   procedure Check_C (Arr : C) is
   begin
      if Arr'First /= Count or else Arr'Last /= 9 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_C;

   procedure Check_D (Arr : D) is
   begin
      if Arr'First /= Count - 1 or else Arr'Last /= Count + 1 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_D;

   procedure Check_E (Arr : E) is
   begin
      if Arr'First /= 2 or else Arr'Last /= 5 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_E;

   procedure Check_F (Arr : F) is
   begin
      if Arr'First /= Wide_Count or else Arr'Last /= Wide_Count + 1 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_F;

   procedure Check_G (Arr : G) is
   begin
      if Arr'First /= 2
        or else Arr'Last /= 5
        or else Arr'First (2) /= 1
        or else Arr'Last (2) /= Count
      then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_G;

   procedure Check_Record (Arr : With_Range) is
   begin
      if Arr.Value not in Count - 1 .. Count + 1 then
         raise Program_Error with "incorrect array bounds";
      end if;
   end Check_Record;
end Foo;
