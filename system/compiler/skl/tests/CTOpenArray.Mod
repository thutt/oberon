(* Copyright (c) 2021, 2023 Logic Magicians Software
 *
 * Test code generation for open array array bounds checking.
 *)
MODULE CTOpenArray;

TYPE
  DataType = INTEGER;
  String = POINTER TO ARRAY OF DataType;


PROCEDURE Ch(ch : DataType);
END Ch;

PROCEDURE P0(VAR s : ARRAY OF DataType); (* In / Out open array *)
BEGIN
(*
  ASSERT(LEN(s) = 20);
  s[5] := 'A';
*)
END P0;


PROCEDURE P11(s : ARRAY OF ARRAY OF DataType); (* In-only open array *)
END P11;

PROCEDURE P1(s : ARRAY OF DataType); (* In-only open array *)
BEGIN
(*
  ASSERT(LEN(s) = 20);
  s[5] := 'A';
  P0(s);
*)
END P1;

(*
PROCEDURE P2(s : String); (* Heap-based open array *)
BEGIN
  ASSERT(LEN(s^) = 17);
  s[5] := 'A';
  P0(s^);
END P2;
*)

(* Stack:  [from sp]  [from SYSTEM.ADR(s)]
 *             +14H     +0CH    LEN(s, 0)
 *             +10H     +08H    LEN(s, 1)
 *             +0CH     +04H    LEN(s, 2)
 *             +08H     +00H    SYSTEM.ADR(s)
 *             +04H             return address
 *             +00H             stack pointer
 *)
PROCEDURE P3(VAR s : ARRAY OF ARRAY OF ARRAY OF DataType);
BEGIN
(*
  ASSERT(LEN(s, 0) = 2);
  ASSERT(LEN(s, 1) = 3);
  ASSERT(LEN(s, 2) = 20);
*)
  P1(s[2][3]);
END P3;

PROCEDURE Test*;
 VAR
   s : ARRAY 20 OF DataType;
   s3 : ARRAY 2 OF ARRAY 3 OF ARRAY 20 OF DataType;
   heap : String;

BEGIN
(*
  COPY("Hello, world", s);
  P0(s);
  P1(s);

  NEW(heap, 17);
  COPY("Hello, world", heap^);
  P2(heap);
  P3(s3);
 *)
(*
  P1(s3[1][2]);
  s3[0][0][0] := ' ';
  P1(s3[0][0]);
  P1(s3[0][1]);
  P1(s3[0][2]);
  P1(s3[1][0]);

  P11(s3[0]);
  P11(s3[1]);
  P11(s3[2]);
*)
END Test;

END CTOpenArray.
