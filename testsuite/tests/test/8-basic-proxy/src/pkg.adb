with Ada.Text_IO; use Ada.Text_IO;

package body Pkg is

   function Make_Int (X : Integer) return My_Int is (My_Int (X));

   procedure Print_My_Int (X : My_Int) is
   begin
      Put_Line (X'Image);
   end Print_My_Int;

   function Access_It return Int_Acc is
   begin
      return Val'Access;
   end Access_It;

   procedure Print_Int_Acc (Acc : Int_Acc) is
   begin
      Put_Line (Acc.all'Image);
   end Print_Int_Acc;

end Pkg;
