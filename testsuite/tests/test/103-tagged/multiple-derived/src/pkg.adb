with Ada.Text_IO; use Ada.Text_IO;

package body Pkg is

  procedure Foo (R : T4)
  is
    Dummy1 : My_Boolean := R.A;
    Dummy2 :    Boolean := R.B;
    Dummy3 : My_Integer := R.C;
    Dummy4 :    Integer := R.D;
  begin
    null;
  end Foo;

end Pkg;
