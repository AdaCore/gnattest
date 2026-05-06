package body Foo is

   function Specializing_Moves ( n : integer32 ) return VecVec is
      pragma Unreferenced (n);
   begin
      return (raise Program_Error);
   end Specializing_Moves;

   function Generalizing_Moves ( n : integer32 ) return VecVec is
      pragma Unreferenced (n);
   begin
      return (raise Program_Error);
   end Generalizing_Moves;

   function Create ( r,c : Vector ) return Node is
      pragma Unreferenced (r, c);
   begin
      return (raise Program_Error);
   end Create;

   function Create ( n,k : integer32; root : Node ) return Poset is
      pragma Unreferenced (n, k, root);
   begin
      return (raise Program_Error);
   end Create;

   function Create ( n : integer32; r,c : Vector ) return Poset is
      pragma Unreferenced (n, r, c);
   begin
      return (raise Program_Error);
   end Create;

   function Create ( n : integer32; cff : Natural_Number;
                     r,c : Vector ) return Poset is
      pragma Unreferenced (n, cff, r, c);
   begin
      return (raise Program_Error);
   end Create;

   procedure Add_Multiplicity ( ps : in out Poset; m : in Natural_Number ) is
      pragma Unreferenced (m);
   begin
      null;
   end Add_Multiplicity;

   procedure Set_Coefficients_to_Zero ( ps : in out Poset ) is
   begin
      null;
   end Set_Coefficients_to_Zero;

   procedure Add_from_Leaves_to_Root ( ps : in out Poset ) is
   begin
      null;
   end Add_from_Leaves_to_Root;

   function Root_Rows ( ps : in Poset ) return Vector is
      pragma Unreferenced (ps);
   begin
      return (raise Program_Error);
   end Root_Rows;

   function Root_Columns ( ps : in Poset ) return Vector is
      pragma Unreferenced (ps);
   begin
      return (raise Program_Error);
   end Root_Columns;

   function Equal ( nd1,nd2 : Node ) return boolean is
      pragma Unreferenced (nd1, nd2);
   begin
      return False;
   end Equal;

   function Position ( first_nd : Node; nd : Node ) return integer32 is
      pragma Unreferenced (first_nd, nd);
   begin
      return 0;
   end Position;

   function Retrieve ( ps : Poset; i,j : integer32 ) return Link_to_Node is
      pragma Unreferenced (ps, i, j);
   begin
      return null;
   end Retrieve;

   procedure Retrieve_Leaf ( ps : in Poset; cols : in Vector;
                             ind : out integer32; lnd : out Link_to_Node ) is
      pragma Unreferenced (ps, cols);
   begin
      ind := 0;
      lnd := null;
   end Retrieve_Leaf;

   function Is_Stay_Child ( parent,child : Node ) return boolean is
      pragma Unreferenced (parent, child);
   begin
      return False;
   end Is_Stay_Child;

   function Is_Swap_Child ( parent,child : Node ) return boolean is
      pragma Unreferenced (parent, child);
   begin
      return False;
   end Is_Swap_Child;

   function Number_of_Parents ( nd : Node ) return natural32 is
      pragma Unreferenced (nd);
   begin
      return 0.0;
   end Number_of_Parents;

   function Multiplicity_of_Parents ( nd : Node ) return Natural_Number is
      pragma Unreferenced (nd);
   begin
      return 0.0;
   end Multiplicity_of_Parents;

   function Retrieve_Parent ( nd : Node; k : integer32 ) return Link_to_Node is
      pragma Unreferenced (nd, k);
   begin
      return null;
   end Retrieve_Parent;

   function Degree_of_Freedom ( ps : Poset ) return natural32 is
      pragma Unreferenced (ps);
   begin
      return 0.0;
   end Degree_of_Freedom;

end Foo;
