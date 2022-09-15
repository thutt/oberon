(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for conditional set instructions.
 *)
MODULE CTTrapNil;
IMPORT Console;

VAR
  v : LONGINT;


PROCEDURE Nil;
  VAR p : POINTER TO ARRAY 2 OF CHAR;
BEGIN
  p[0] := 'A';                  (* Trap with a NIL pointer exception. *)
  p[1] := 0X;
END Nil;


PROCEDURE Test*;
BEGIN
  Nil;
END Test;

END CTTrapNil.
