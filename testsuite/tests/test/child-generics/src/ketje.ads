with Keccak.Generic_KeccakF.Byte_Lanes.Twisted;
with Keccak.Keccak_1600;
with Inter;

pragma Elaborate_All (Keccak.Generic_KeccakF.Byte_Lanes.Twisted);

package Ketje is
   use Keccak;

   package Twisted_Lanes_1600 is new Keccak_1600.KeccakF_1600_Lanes.Twisted
     (Shift_Left  => Inter.Shift_Left);

end Ketje;
