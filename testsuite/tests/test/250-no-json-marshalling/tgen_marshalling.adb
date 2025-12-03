with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Pkg;
with Pkg.TGen_Support;
with TGen;
with TGen.TGen_Support;
with Marshaller;

procedure TGen_Marshalling is

   package Integer_Marshaller is new
     Marshaller
       (T             => TGen.TGen_Std.Integer,
        Type_Name     => "Integer",
        Marshal_Value =>
          TGen.TGen_Support.TGen_Marshalling_standard_integer_Input);

   package Answer_Marshaller is new
     Marshaller
       (T             => TGen.TGen_Std.Pkg.Answer,
        Type_Name     => "Answer",
        Marshal_Value => Pkg.TGen_Support.TGen_Marshalling_pkg_answer_Input);

   package Answers_Marshaller is new
     Marshaller
       (T             => TGen.TGen_Std.Pkg.Answer_Array,
        Type_Name     => "Answer_Array",
        Marshal_Value =>
          Pkg.TGen_Support.TGen_Marshalling_pkg_answer_array_Input);

   package User_Answer_Marshaller is new
     Marshaller
       (T             => TGen.TGen_Std.Pkg.User_Answer,
        Type_Name     => "User_Answer",
        Marshal_Value =>
          Pkg.TGen_Support.TGen_Marshalling_pkg_user_answer_Input);

   Integer_Input_Files : constant Integer_Marshaller.File_Array :=
     [To_Unbounded_String
        ("identity_int-b5693a6aa0823484f42b0512441dcf9ec1f34f9e-t1"),
      To_Unbounded_String
        ("identity_int-b5693a6aa0823484f42b0512441dcf9ec1f34f9e-t2"),
      To_Unbounded_String
        ("identity_int-b5693a6aa0823484f42b0512441dcf9ec1f34f9e-t3"),
      To_Unbounded_String
        ("identity_int-b5693a6aa0823484f42b0512441dcf9ec1f34f9e-t4"),
      To_Unbounded_String
        ("identity_int-b5693a6aa0823484f42b0512441dcf9ec1f34f9e-t5")];

   Answer_Input_Files : constant Answer_Marshaller.File_Array :=
     [To_Unbounded_String
        ("identity_answer-60e02304b78676d9f32ebf521cd31a0d6d089a6a-t1"),
      To_Unbounded_String
        ("identity_answer-60e02304b78676d9f32ebf521cd31a0d6d089a6a-t2"),
      To_Unbounded_String
        ("identity_answer-60e02304b78676d9f32ebf521cd31a0d6d089a6a-t3"),
      To_Unbounded_String
        ("identity_answer-60e02304b78676d9f32ebf521cd31a0d6d089a6a-t4"),
      To_Unbounded_String
        ("identity_answer-60e02304b78676d9f32ebf521cd31a0d6d089a6a-t5")];

   Answers_Input_Files : constant Answers_Marshaller.File_Array :=
     [To_Unbounded_String
        ("identity_answers-091bc9ea9ee47396f7bc696c10a6eb8f53e23c5a-t1"),
      To_Unbounded_String
        ("identity_answers-091bc9ea9ee47396f7bc696c10a6eb8f53e23c5a-t2"),
      To_Unbounded_String
        ("identity_answers-091bc9ea9ee47396f7bc696c10a6eb8f53e23c5a-t3"),
      To_Unbounded_String
        ("identity_answers-091bc9ea9ee47396f7bc696c10a6eb8f53e23c5a-t4"),
      To_Unbounded_String
        ("identity_answers-091bc9ea9ee47396f7bc696c10a6eb8f53e23c5a-t5")];

   User_Answer_Files : constant User_Answer_Marshaller.File_Array :=
     [To_Unbounded_String
        ("identity_user_answer-39fe8db9ece8998ee1ddab50681b4e4f6561d113-t1"),
      To_Unbounded_String
        ("identity_user_answer-39fe8db9ece8998ee1ddab50681b4e4f6561d113-t2"),
      To_Unbounded_String
        ("identity_user_answer-39fe8db9ece8998ee1ddab50681b4e4f6561d113-t3"),
      To_Unbounded_String
        ("identity_user_answer-39fe8db9ece8998ee1ddab50681b4e4f6561d113-t4")];

begin
   Integer_Marshaller.Log_Values (Integer_Input_Files);
   Answer_Marshaller.Log_Values (Answer_Input_Files);
   Answers_Marshaller.Log_Values (Answers_Input_Files);
   User_Answer_Marshaller.Log_Values (User_Answer_Files);
end TGen_Marshalling;
