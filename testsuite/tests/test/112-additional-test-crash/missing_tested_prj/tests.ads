with Aunit.Test_Fixtures;
with Pkg;

package Tests is

   type Unrelated is new Pkg.Type_That_Does_Not_Exist with null record;

   type Custom_Test is new Aunit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Identity (Test : in out Custom_Test);

end Tests;
