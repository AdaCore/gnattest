with Ada.Real_Time;

package Pkg is
   function Do_Stuff
     (X : Ada.Real_Time.Seconds_Count)
      return Ada.Real_Time.Seconds_Count
   is (X);
end Pkg;
