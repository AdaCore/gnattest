generic
   type T is private;
package Gen is
   procedure Gen (X : T);

   type Item is tagged null record;
   procedure Touch (X : Item);
end Gen;
