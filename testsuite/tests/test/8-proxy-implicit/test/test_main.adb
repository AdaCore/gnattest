with Pkg;

with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;

with Pkg.TGen_Support; use Pkg.TGen_Support;

procedure Test_Main is
   F : File_Type;
   S : Stream_Access;
   Val : Pkg.My_Int;
   Acc : Pkg.Int_Acc;
begin
      for I in 0 .. 4 loop
      Open
        (F,
         In_File,
         "bin_tests/print_int_acc-"
         & Ada.Strings.Fixed.Trim(I'Image, Ada.Strings.Left));
      S := Stream (F);
      Acc := TGen_Marshalling_pkg_int_acc_Input (S);
      Pkg.Print_Int_Acc (Acc);
      Close (F);
   end loop;
   for I in 0 .. 4 loop
      Open
        (F,
         In_File,
         "bin_tests/print_my_int-"
         & Ada.Strings.Fixed.Trim(I'Image, Ada.Strings.Left));
      S := Stream (F);
      Val := TGen_Marshalling_pkg_my_int_Input (S);
      Pkg.Print_My_Int (Val);
      Close (F);
   end loop;
end Test_Main;
