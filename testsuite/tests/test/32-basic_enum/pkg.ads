package Pkg is

   type My_Int is new Integer range -10 .. 10;

   type My_Enum is (A, B, C);

   type My_Mod is mod 10;

   type My_Float is digits 6 range -1.0 .. 1.0;

   type My_Fixed is delta 0.1 range -1.0 .. 1.0;

   procedure Process (A : My_Int; B : My_Enum; C : My_Mod; D : My_Float; E : My_Fixed);

   type Point is record
      X, Y : My_Int;
   end record;

   type Point_F is record
      X, Y : My_Float;
   end Record;

   procedure Eq (A : Point; B : Point_F);

   type Constr_Int_Arr_Type is array (My_Int) of Integer;

   procedure Process (Constr_Int_Arr : Constr_Int_Arr_Type);

   type Singleton_Int_Mod_Type is mod 1;
   type Singleton_Mod_Arr_Type is array (Singleton_Int_Mod_Type range <>) of Integer;

   procedure Process (Singleton_Mod_Arr : Singleton_Mod_Arr_Type);

   type Singleton_Enum_Type is (A);
   type Singleton_Enum_Arr_Type is array (Singleton_Enum_Type range <>) of Integer;

   procedure Process (Singleton_Enum_Arr : Singleton_Enum_Arr_Type);

   type Rec_Type is record
      I : Integer;
   end record;

   procedure Process (Rec : Rec_Type);

   type Disc_Rec_Type (B : My_Enum) is record
      case B is
         when A =>
            I : Integer;
         when others =>
            J : Float;
      end case;
   end record;

   procedure Process (Disc_Rec : Disc_Rec_Type);

end Pkg;
