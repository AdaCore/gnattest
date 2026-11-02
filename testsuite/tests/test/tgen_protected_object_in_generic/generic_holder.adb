package body Generic_Holder is
   procedure Start (Target : Integer) is
   begin
      Control.Set_Target (Target);
   end Start;

   protected body Control is
      procedure Set_Target (Target : Integer) is
      begin
         Current := Target;
      end Set_Target;
   end Control;
end Generic_Holder;
