package Pkg is

   type R1 (D1 : Integer) is tagged record
      Buff : String (1 .. D1);
   end record;

   type R2 (D2 : Positive; D3 : Boolean) is new R1 (D1 => D2) with record
      case D3 is
         when True =>
            B : Boolean;
         when False => null;
      end case;
   end record;

   function Foo (R : R2) return Integer;

end Pkg;
