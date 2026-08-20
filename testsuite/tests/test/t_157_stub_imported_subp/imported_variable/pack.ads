pragma Ada_2012;
with Interfaces.C;

package Pack is
   Foo : Interfaces.C.unsigned
   with Import, Convention => C, External_Name => "ANSWER_TO_LIFE";

   Bar : Interfaces.C.unsigned;
   pragma Import (Convention => C, Entity => Bar, External_Name => "OTHER");

   function Id (N : Interfaces.C.unsigned) return Interfaces.C.unsigned;
   pragma Import (Convention => C, Entity => Id, External_Name => "identity");
end Pack;
