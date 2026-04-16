with Bar;
with Baz;

package Foo is
   function Check_Fn (X : Integer) return Boolean is (X < 10);

   package Inner is
      package Inst is new Bar (A => 2);
      package Other_Inst is new Baz (Allowed => Check_Fn);
   end Inner;
end Foo;
