package Inter is

   type Unsigned_64 is mod 2 ** Long_Long_Integer'Size;
   for Unsigned_64'Size use 64;
   --  See comment on Integer_64 above

   function Shift_Left
     (Value  : Unsigned_64;
      Amount : Natural) return Unsigned_64;

end Inter;
