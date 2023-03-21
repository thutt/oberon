(* Copyright (c) 2023 Logic Magicians Software *)
MODULE Math;
IMPORT SYSTEM;

CONST
  e*  = 2.7182818285;
  pi* = 3.1415926536;

PROCEDURE - Arctan(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  00H, 00H, 21H, 34H;           (* arctan R1, R1 *)


PROCEDURE - Cos(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  01H, 00H, 21H, 34H;           (* cos R1, R1 *)


PROCEDURE - Exp(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  02H, 00H, 21H, 34H;           (* exp R1, R1 *)


PROCEDURE - Ln(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  03H, 00H, 21H, 34H;           (* ln R1, R1 *)


PROCEDURE - Sin(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  04H, 00H, 21H, 34H;           (* sin R1, R1 *)


PROCEDURE - Sqrt(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  05H, 00H, 21H, 34H;           (* sqrt R1, R1 *)


PROCEDURE - Tan(x: REAL) : REAL
  06H, 00H, 20H, 28H,           (* popf R1 *)
  06H, 00H, 21H, 34H;           (* sqrt R1, R1 *)


PROCEDURE sin*(x: REAL) : REAL;  (* x is radians *)
BEGIN
  IF x < 0.0 THEN
    RETURN -Sin(-x);
  ELSE
    RETURN Sin(x);
  END;
END sin;


PROCEDURE cos*(x: REAL) : REAL;  (* x is radians *)
BEGIN
  IF x < 0.0 THEN
    RETURN Cos(-x);
  ELSE
    RETURN Cos(x);
  END;
END cos;


PROCEDURE arctan*(x: REAL) : REAL;  (* x is radians *)
BEGIN
  RETURN Arctan(x);
END arctan;


PROCEDURE tan*(x: REAL) : REAL;  (* x is radians *)
BEGIN
  RETURN Tan(x);
END tan;


PROCEDURE sqrt*(x: REAL) : REAL;
  VAR
    Error: ARRAY 32 OF CHAR;
BEGIN
  IF x = 0 THEN
    RETURN 0;
  ELSIF x < 0 THEN
    Error := "NEGATIVE ARGUMENT";
    HALT(1280);
  ELSE
    RETURN Sqrt(x);
  END;
END sqrt;


PROCEDURE ln*(x: REAL) : REAL;  (* log base e of x *)
  VAR
    Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN
    Error := "NEGATIVE ARGUMENT";
    HALT(1280);
  ELSE
    RETURN Ln(x);
  END;
END ln;


PROCEDURE exp*(x: REAL) : REAL;  (* e^x *)
BEGIN
  RETURN Exp(x);
END exp;

END Math.
