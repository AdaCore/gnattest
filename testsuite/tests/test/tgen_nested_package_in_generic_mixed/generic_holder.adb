package body Generic_Holder is
   function Identity (Value : Integer) return Integer is (Value);

   package body Inner is
      procedure Put (Value : Integer) is null;

      package body Deeper is
         procedure Put (Value : Integer) is null;
      end Deeper;
   end Inner;
end Generic_Holder;
