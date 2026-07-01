generic
   --  Bit-wise left shift for Lane_Type.
   with function Shift_Left (Value  : in Lane_Type;
                             Amount : in Natural) return Lane_Type;
package Keccak.Generic_KeccakF.Byte_Lanes is
   procedure Foo (L : Lane_Type);
end Keccak.Generic_KeccakF.Byte_Lanes;
