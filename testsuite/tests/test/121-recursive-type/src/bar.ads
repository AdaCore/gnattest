package Bar is

   type Node;
   type Node_Acc is access all Node with TGen_Proxy => Get_Parent;
   type Node is record
      Parent : Node_Acc;
   end record;

   function Make_Node (Parent : Node_Acc) return Node is
     (Node'(Parent => Parent));

   function Get_Parent (N : Node) return Node_Acc is (N.Parent);

end Bar;
