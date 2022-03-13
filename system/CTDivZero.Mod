(* Copyright (c) 2022 Logic Magicians Software
 *)
MODULE CTDivZero; (* Test divide by 0 exception *)
IMPORT Console;

PROCEDURE Divide(num, div : INTEGER) : INTEGER;
  VAR
    r : INTEGER;
BEGIN
  RETURN num DIV div;

END Divide;


PROCEDURE Test*;
 VAR 
   result : INTEGER;
BEGIN
  result := Divide(12, 0);
  Console.Str("Divide by zero: "); (* Execution should never get here. *)
  Console.Int(result, 3);
  Console.Ln;
END Test;

END CTDivZero.
