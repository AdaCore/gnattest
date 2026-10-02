with Dep;
with Other;

package body Put is
   function F return Integer is (Dep.Get + Other.H);
end Put;
