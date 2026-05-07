generic
   A : Integer;
package Bar is
   type Ctx is private;

   procedure Id (X : out Ctx; Y : Integer);

   function Other (Y : Integer) return Ctx with Pre => A < 100;

private

   type Ctx is record
      Dummy : Integer;
   end record;

end Bar;
