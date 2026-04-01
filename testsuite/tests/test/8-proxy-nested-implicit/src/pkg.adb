with Ada.Text_IO; use Ada.Text_IO;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Pkg is

   function Make_Acc (Val : Val_T) return Val_Acc is
   begin
      return new Val_T'(Val);
   end Make_Acc;

   procedure Print_Arr (Arr : Arr_T) is
   begin
      Put ("[");
      for I in Arr'Range loop
         if Arr (I) /= null then
            Put (Val_T'(Arr(I).all)'Image);
         else
            Put (" null");
         end if;
         if I < Arr'Last then
            Put(",");
         end if;
      end loop;
      Put_Line ("]");
   end Print_Arr;

   procedure Print_Rec (Rec : Rec_T) is
      Res : Unbounded_String;
   begin
      Res := To_Unbounded_String
        ("{Disc:" & Rec.Disc'Image & "; Index:" & Rec.Index'Image
         & "; First_Acc :" & Rec.First_Acc.all'Image);
      case Rec.Disc is
         when 1 .. 9 =>
            Res := Res & "; Comp:" & Rec.Comp.all'Image;
         when 10 =>
            Res := Res & "; Other_Stuff" & Rec.Other_Stuff'Image;
      end case;
      Put_Line (To_String (Res) & "}");
   end Print_Rec;

end Pkg;
