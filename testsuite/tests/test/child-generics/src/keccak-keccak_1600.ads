with Inter;
with Keccak.Generic_KeccakF;
with Keccak.Generic_KeccakF.Byte_Lanes;

pragma Elaborate_All (Keccak.Generic_KeccakF);
pragma Elaborate_All (Keccak.Generic_KeccakF.Byte_Lanes);

package Keccak.Keccak_1600 is

   package KeccakF_1600 is new Keccak.Generic_KeccakF
     (Lane_Type => Inter.Unsigned_64);

   package KeccakF_1600_Lanes is new KeccakF_1600.Byte_Lanes
     (Shift_Left => Inter.Shift_Left);

end Keccak.Keccak_1600;
