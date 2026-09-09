package body Pack is

   function Id (X : Interfaces.C.unsigned) return Interfaces.C.unsigned is
   begin
      return X;
   end Id;

end Pack;
