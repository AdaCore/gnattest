package Pkg is

   type Arr is array (Positive range <>) of Integer;

   --  Ada 2022 syntax: compiling this spec from the harness only works if
   --  the harness inherits Compiler'Local_Configuration_Pragmas (prj.adc,
   --  which contains pragma Ada_2022) from the argument project.

   Values : constant Arr := [1, 2, 3];

   function Inc (X : Integer) return Integer;

end Pkg;
