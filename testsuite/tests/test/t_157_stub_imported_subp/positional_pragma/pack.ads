pragma Ada_2012;
with Interfaces.C;

package Pack is
   Bar : Interfaces.C.unsigned;
   pragma Import (C, Bar, "OTHER");

   function Id (N : Interfaces.C.unsigned) return Interfaces.C.unsigned;
   pragma Import (C, Id, "identity");
end Pack;
