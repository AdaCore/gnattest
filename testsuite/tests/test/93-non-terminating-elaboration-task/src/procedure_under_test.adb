package body Procedure_Under_Test is

   ----------
   -- Test --
   ----------

   procedure Test (Some_Value : Integer) is
   begin
      null;
   end Test;

   --  Make task T loop forever - the GNATfuzz runtime will need to terminate
   --  it after executing the subprogram under test
   task body T is
   begin
      loop
         null;
      end loop;
   end T;

end Procedure_Under_Test;
