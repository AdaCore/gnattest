pragma Ada_2012;
with Interfaces.C;

package Pack is
   procedure Increment (X : access Interfaces.C.unsigned)
   with Import, Convention => C, Unreferenced, External_Name => "increment";
end Pack;
