pragma Ada_2012;
with Interfaces.C;

package Pack is
   procedure Increment (X : access Interfaces.C.unsigned)
   with Import, Convention => C, External_Name => "ignored", Link_Name => "increment";

   procedure Decrement (X : access Interfaces.C.unsigned);
   pragma
     Import
       (Convention => C, Entity => Decrement, External_Name => "decrement");
end Pack;
