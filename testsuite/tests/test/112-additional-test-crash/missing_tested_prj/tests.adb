with Pkg; use Pkg;

package Tests is

   procedure Test_Identity (Test : in out Custom_Test) is
   begin
      Aunit.Assertions.Assert (Identity (3) = 3, "Identity test failed");
   end Test_Identity;

end Tests;
