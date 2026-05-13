package Pkg is

   subtype Size is Integer range 1 .. 10;

   type R1 (D1 : Integer) is tagged record
      A : Integer := D1;
   end record;

   type R2 (D2 : Size; D3 : Boolean) is new R1 (D1 => D2) with record
      case D3 is
         when True =>
            B : Boolean;
         when False => null;
      end case;
   end record;

   type R3 (D4 : Size; D5 : Boolean) is new R2 (D2 => D4, D3 => D5) with record
      case D5 is
         when True =>
            C : Boolean;
         when False => null;
      end case;
   end record;

   function Foo (R : R3) return Integer;

end Pkg;
