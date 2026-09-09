with Interfaces.C;

package body Simple is

   function Inc (X : Integer) return Integer is
   begin
      return Integer (Pack.Id (Interfaces.C.unsigned (X))) + 1;
   end Inc;

end Simple;
