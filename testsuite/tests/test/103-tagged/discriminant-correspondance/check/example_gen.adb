--  Use the Initialize_Scalars config pragma to make sure that if part of the
--  data was not initialized by the marshaller then this is caught.

pragma Initialize_Scalars (Unsigned_8 => 16#FF#, Signed_32 => 16#FFFFFFFF#);


with Pkg; use Pkg;
with Pkg.TGen_Support; use Pkg.TGen_Support;
with TGen.TGen_Support; use TGen.TGen_Support;

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;

procedure Example_Gen is

   F         : Ada.Streams.Stream_IO.File_Type;
   S         : Stream_Access;
   File_Name : constant String := "scratch_pad.bin";

   V_Out : constant R2 :=
     (D2 => 1, D3 => True, Buff => (1 => 'A'), B => True);
begin
   Create (F, Out_File, File_Name);
   S := Stream (F);

   TGen_Marshalling_Pkg_R2_Output (S, V_Out);
   Close (F);

   Open (F, In_File, File_Name);
   S := Stream (F);

   declare
      V_In : constant R2 := TGen_Marshalling_Pkg_R2_Input (S);
   begin
      if V_In /= V_Out then
         Put_Line ("R2 marshaling KO!!");
      end if;
   end;
end Example_Gen;
