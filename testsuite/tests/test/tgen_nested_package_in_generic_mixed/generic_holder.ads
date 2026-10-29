generic
package Generic_Holder is
   function Identity (Value : Integer) return Integer;

   package Inner is
      procedure Put (Value : Integer);

      package Deeper is
         procedure Put (Value : Integer);
      end Deeper;
   end Inner;
end Generic_Holder;
