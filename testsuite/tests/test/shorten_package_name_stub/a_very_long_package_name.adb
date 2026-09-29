with Dep;

package body A_Very_Long_Package_Name is
   function Add (X, Y : Integer) return Integer is
   begin
      return Dep.Id (X) + Y;
   end Add;
end A_Very_Long_Package_Name;
