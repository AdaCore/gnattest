------------------------------------------------------------------------------
--                                                                          --
--                                 GNATtest                                 --
--                                                                          --
--                      Copyright (C) 2014-2026, AdaCore                    --
--                                                                          --
-- GNATtest  is  free  software; you  can  redistribute  it  and/or  modify --
-- it  under  terms of the  GNU  General  Public  License  as  published by --
-- the Free Software Foundation;  either version 3, or (at your option) any --
-- later version. This software  is distributed in the hope that it will be --
-- useful but  WITHOUT  ANY  WARRANTY; without even the implied warranty of --
-- MERCHANTABILITY  or  FITNESS  FOR A PARTICULAR PURPOSE.                  --
--                                                                          --
-- As a special  exception  under  Section 7  of  GPL  version 3,  you are  --
-- granted additional  permissions described in the  GCC  Runtime  Library  --
-- Exception, version 3.1, as published by the Free Software Foundation.    --
--                                                                          --
-- You should have received a copy of the GNU General Public License and a  --
-- copy of the GCC Runtime Library Exception along with this program;  see  --
-- the files COPYING3 and COPYING.RUNTIME respectively.  If not, see        --
-- <http://www.gnu.org/licenses/>.                                          --
------------------------------------------------------------------------------

package Test.Stub.Write is

   --  Child package of Test.Stub which specifically is used to generate
   --  the stubbing files.

   procedure Generate_Body_Stub
     (Body_File_Name : String;
      Data           : Stubbing_Data;
      Markered_Data  : in out MD_Map);
   --  Generates stub body

   procedure Generate_Stub_Data
     (Stub_Data_File_Spec : String;
      Stub_Data_File_Body : String;
      Data                : Stubbing_Data);
   --  Generates Stub_Data package which contains setters

   procedure Rewrite_Spec
     (Unit_Node : Package_Decl; Stubbed_Spec_Name : String);
   --  Rewrite Unit_Node to remove all the Import pragmas and aspects of
   --  subprograms in Unit_Node and write the resulting spec file in
   --  Stubbed_Spec_Name.
   --
   --  The rewriting is then aborted to avoid reparsing, thus Unit_Node is
   --  still valid and usable.

end Test.Stub.Write;
