with Ada.Text_IO; use Ada.Text_IO;

package body Pkg is

   procedure Print_Int_Acc (Acc : Int_Acc) is
   begin
      Put_Line (Acc.all'Image);
   end Print_Int_Acc;

end Pkg;
