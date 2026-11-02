generic
package Generic_Holder is
   procedure Start (Target : Integer);
private
   protected Control is
      procedure Set_Target (Target : Integer);
   private
      Current : Integer := 0;
   end Control;
end Generic_Holder;
