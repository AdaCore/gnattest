package Pkg is

   type Rec_Ancestor (D : Boolean) is tagged record
      case D is
         when True  => I : Integer;
         when False => B : Boolean;
      end case;
   end record;

   type Rec is new Rec_Ancestor with record
      J : Integer;
   end record;

   function Foo (R : Rec) return Integer;

end Pkg;
