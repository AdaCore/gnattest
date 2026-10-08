pragma Ada_2012;
with Interfaces.C;

package Null_Proc is

   procedure Decrement (X : access Interfaces.C.unsigned) is null;
   --  Body is not expected; shouldn't be stubbed.

end Null_Proc;
