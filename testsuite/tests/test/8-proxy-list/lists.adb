with Ada.Text_IO; use Ada.Text_IO;

package body Lists is

   function To_DLL (Arr : Int_Array) return DLL_Access is
      Current, Res : DLL_Access := null;
   begin
      if Arr'Length = 0 then
         return null;
      end if;
      Res := new DLL'(Value => Arr (Arr'First), Prev => null, Next => Null);
      Current := Res;
      for I in Arr'First + 1 .. Arr'Last loop
         Current := new DLL'(Prev => Current, Value => Arr (I), Next => Null);
         Current.Prev.Next := Current;
      end loop;
      return Res;
   end To_DLL;

   procedure Check_And_Print_DLL (List : DLL_Access) is
      Cur : DLL_Access := List;
   begin
      if List = null then
         Put_Line ("[]");
         return;
      end if;
      loop
         if Cur.Prev /= null and then Cur.Prev.Next /= Cur then
            raise Constraint_Error with "malformed doubly linked list";
         end if;
         Put ("[" & Cur.Value'Image & "]");
         Cur := Cur.Next;
         exit when Cur = null;
         Put(" <-> ");
      end loop;
      New_Line;
   end Check_And_Print_DLL;

end Lists;
