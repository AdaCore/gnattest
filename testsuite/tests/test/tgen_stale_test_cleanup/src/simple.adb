package body Simple is

   function Add
     (Left : Integer; Right : Integer; Middle : Integer) return Integer
   is
   begin
      return Left + Right + Middle;
   end Add;

end Simple;
