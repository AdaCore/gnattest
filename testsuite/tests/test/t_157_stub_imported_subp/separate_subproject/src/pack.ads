pragma Ada_2012;
with Interfaces.C;

package Pack is
   function Id (N : Interfaces.C.unsigned) return Interfaces.C.unsigned;
   pragma Import (Convention => C, Entity => Id, External_Name => "identity");
end Pack;
