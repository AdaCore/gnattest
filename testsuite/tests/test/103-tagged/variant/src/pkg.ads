package Pkg is

   type Rec (D : Boolean) is tagged record
      case D is
         when True  => I : Integer;
         when False => B : Boolean;
      end case;
   end record;

   function Foo (R : Rec) return Integer;

end Pkg;
