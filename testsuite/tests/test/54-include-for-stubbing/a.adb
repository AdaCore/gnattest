with b, c, d;

package body a is

   function show_b return String is
   begin
      return b.func_b;
   end show_b;

   function show_c return String is
   begin
      return c.func_c;
   end show_c;

end a;
