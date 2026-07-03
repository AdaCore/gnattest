with Interfaces;
with System.Arith_64;
with System.Image_F;

package System_Under_Test is
   subtype Int64 is Interfaces.Integer_64;
   subtype Uns64 is Interfaces.Unsigned_64;

   package Impl is new System.Image_F (Int64, System.Arith_64.Scaled_Divide64);
end System_Under_Test;
