with Stubbed;
with Stubbed.Child;

package body Pkg is

   procedure Foo (X, Y : Integer) is
      B : Boolean := Stubbed.Child.Qux (Y = X);
      I : Integer :=
        Stubbed.
          Bar (X);
   begin
      null;
   end Foo;

end Pkg;
