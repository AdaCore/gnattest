package Pkg is

   subtype Size is Integer range 1 .. 10;

   type R1 (D1 : Integer) is tagged limited record
      A : Integer := D1;
   end record;

   type R2 (D2 : Size := 1; D3 : Boolean := False) is limited new R1 (D1 => D2) with record
      case D3 is
         when True =>
            B : Boolean;
         when False => null;
      end case;
   end record;

   function Foo (R : R2) return Integer;

end Pkg;
