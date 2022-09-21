(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test SET operations.
 *)
MODULE CTSET;
  IMPORT Console;

  PROCEDURE SetRange(x, y : INTEGER) : SET;
    VAR s : SET;
  BEGIN
    s := {x..y};
    Console.Str("Set: ");
    Console.Set(s);
    Console.Ln;
    RETURN s;
  END SetRange;

  PROCEDURE Test*;
    VAR s : SET;
  BEGIN
    s := SetRange(3, 8);
    s := SetRange(0, MAX(SET) - 1);
    s := SetRange(0, MAX(SET));
  END Test;

END CTSET.
