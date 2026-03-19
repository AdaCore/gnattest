with Aunit.Test_Fixtures;

package Tests is

   type Custom_Test is new Aunit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Identity (Test : in out Custom_Test);

end Tests;
