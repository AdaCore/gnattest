with Ada.Text_IO; use Ada.Text_IO;

package body Pkg is

  procedure Foo (R : T2) is
    Dummy1 : Integer := R.A;
    Dummy2 : Boolean := R.B;
    Dummy3 : Integer := R.C;
  begin
    null;
  end Foo;

end Pkg;
