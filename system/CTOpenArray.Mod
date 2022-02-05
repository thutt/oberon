(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation for open array array bounds checking.
 *)
MODULE CTOpenArray;

PROCEDURE Str(VAR s : ARRAY OF CHAR);
BEGIN
  s[5] := 'X';
END Str;

PROCEDURE Test*;
 VAR
   s : ARRAY 20 OF CHAR;
BEGIN
  COPY("Hello, world", s);
  Str(s);
END Test;

END CTOpenArray.
