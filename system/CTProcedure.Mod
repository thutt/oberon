(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test code generation with PROCEDURE and type bound procedures.
 *)
MODULE CTProcedure;
IMPORT Console;

TYPE
  Procedure = PROCEDURE(a : INTEGER);

  PROCEDURE Callback(p : Procedure);
  BEGIN
    p(151);
  END Callback;

  PROCEDURE cb(a : INTEGER);
  BEGIN
    Console.Str("callback: ");
    Console.Int(a, 5);
    Console.Ln;
  END cb;

  PROCEDURE Test*;
  BEGIN
    Callback(cb);
  END Test;

END CTProcedure.
