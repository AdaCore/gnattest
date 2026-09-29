package body A_Very_Long_Package_Name is
   package body Nested is
      function Add (X, Y : Integer) return Integer is
      begin
         return X + Y;
      end Add;
   end Nested;
end A_Very_Long_Package_Name;
