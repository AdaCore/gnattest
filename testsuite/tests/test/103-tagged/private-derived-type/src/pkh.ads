with Pkg;
package Pkh is
   type Car_T is new Pkg.Vehicle_T with record
      Nb_Occupants : Integer;
   end record;
   procedure Do_Something (Car : Car_T);
end Pkh;
