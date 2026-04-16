package body Bar is
   procedure Id (X : out Ctx; Y : Integer) is
   begin
      X := Ctx'(Dummy => Y + A);
   end Id;

   function Other (Y : Integer) return Ctx is (Ctx'(Dummy => y));

end Bar;
