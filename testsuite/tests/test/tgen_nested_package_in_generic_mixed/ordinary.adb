package body Ordinary is
   package body Inner is
      function Identity (Value : Integer) return Integer is (Value);
   end Inner;
end Ordinary;
