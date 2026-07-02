package Foo is

   type My_LLF is new Long_Long_Float;

   type Custom_Extended_Float is digits 17 range -1.0 .. 1.0;

   function Identity_LLF (X : Long_Long_Float) return Long_Long_Float is (X);

   function Identity_My_LLF (X : My_LLF) return My_LLF is
     (X);

   function Identity_Custom_LLF
     (X : Custom_Extended_Float) return Custom_Extended_Float is
     (X);

end Foo;
