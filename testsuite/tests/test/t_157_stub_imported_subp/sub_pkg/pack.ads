pragma Ada_2012;
with Interfaces.C;

package Pack is
   package Bar is

      procedure Increment (X : access Interfaces.C.unsigned)
      with
        Import,
        Convention    => C,
        External_Name => "ignored",
        Link_Name     => "increment";

   end Bar;
end Pack;
