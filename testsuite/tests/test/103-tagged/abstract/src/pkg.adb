package body Pkg is

  procedure Not_Abstract (Val : Rec) is
  begin
    null;
  end Not_Abstract;

  procedure Test_Root (Val : Root) is
  begin
    null;
  end Test_Root;

  procedure Test_Bar (Val : Bar) is
  begin
    null;
  end Test_Bar;

  procedure Test_Derived (Val : Derived) is
  begin
    null;
  end Test_Derived;
end Pkg;
