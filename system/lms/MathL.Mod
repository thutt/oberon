(* Copyright (c) 2023 Logic Magicians Software *)
MODULE MathL;

(* Math.Functions of the 387 *)
(* ARD, 21. 9. 92 *)
(* ARD, 10. 6. 94 diff between sin and cos of 386 and 486??? --> 1.0 not on tos *)

IMPORT SYSTEM;

CONST
  e* = 2.718281828459045D0;
  pi = 3.14159265358979323846D0;


PROCEDURE - Arctan(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  00H, 00H, 21H, 34H;           (* arctan R1, R1 *)


PROCEDURE - Cos(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  01H, 00H, 21H, 34H;           (* cos R1, R1 *)


PROCEDURE - Exp(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  02H, 00H, 21H, 34H;           (* exp R1, R1 *)


PROCEDURE - Ln(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  03H, 00H, 21H, 34H;           (* ln R1, R1 *)


PROCEDURE - Sin(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  04H, 00H, 21H, 34H;           (* sin R1, R1 *)


PROCEDURE - Sqrt(x: LONGREAL) : LONGREAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  05H, 00H, 21H, 34H;           (* sqrt R1, R1 *)


PROCEDURE - Tan(x: REAL) : REAL
  07H, 00H, 20H, 28H,           (* popd R1 *)
  06H, 00H, 21H, 34H;           (* tan R1, R1 *)


PROCEDURE sin*(x: LONGREAL) : LONGREAL;
BEGIN
  IF x < 0.0D0 THEN
    RETURN -Sin(-x);
  ELSE
    RETURN Sin(x);
  END;
END sin;


PROCEDURE cos*(x: LONGREAL) : LONGREAL;
BEGIN
  IF x < 0.0D0 THEN
    RETURN Cos(-x);
  ELSE
    RETURN Cos(x);
  END;
END cos;


PROCEDURE arctan*(x: LONGREAL) : LONGREAL;
BEGIN
  RETURN Arctan(x);
END arctan;


PROCEDURE tan*(x: REAL) : REAL;  (* x is radians *)
BEGIN
  RETURN Tan(x);
END tan;


PROCEDURE sqrt*(x: LONGREAL) : LONGREAL;
  VAR
    Error: ARRAY 32 OF CHAR;
BEGIN
  IF x = 0 THEN
    RETURN 0;
  ELSIF x < 0 THEN
    Error := "NEGATIVE ARGUMENT";
    HALT(1080);
  ELSE
    RETURN Sqrt(x);
  END;
END sqrt;


PROCEDURE ln*(x: LONGREAL) : LONGREAL;
  VAR
    Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN
    Error := "NEGATIVE ARGUMENT";
    HALT(1080);
  ELSE
    RETURN Ln(x);
  END;
END ln;

PROCEDURE exp*(x: LONGREAL) : LONGREAL;
BEGIN
  RETURN Exp(x);
END exp;

END MathL.
