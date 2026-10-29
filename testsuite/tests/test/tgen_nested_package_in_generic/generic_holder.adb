package body Generic_Holder is
   package body Inner is
      Last : Integer := 0;
      procedure Put (Value : Integer) is
      begin
         Last := Value;
      end Put;
   end Inner;
end Generic_Holder;
