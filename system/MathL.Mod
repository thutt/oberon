MODULE MathL;

(* Math.Functions of the 387 *)
(* ARD, 21. 9. 92 *)
(* ARD, 10. 6. 94 diff between sin and cos of 386 and 486??? --> 1.0 not on tos *)

IMPORT SYSTEM;

CONST e* = 2.718281828459045D0;

VAR
  pi- : LONGREAL;
  
PROCEDURE -Sin(x: LONGREAL):LONGREAL
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FEH,        (* FSIN ST(0) *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE -Cos(x: LONGREAL):LONGREAL
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FFH,        (* FCOS ST(0) *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE -Arctan(x: LONGREAL):LONGREAL
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0E8H,        (* FLD1 *)
  0D9H, 0F3H,        (* FPATAN ST(1)/ST(0) *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE -Sqrt(x: LONGREAL):LONGREAL
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FAH,        (* FSQRT ST(0) *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE -Ln(x: LONGREAL):LONGREAL
  0D9H, 0E8H,        (* FLD1 *)
  0D9H, 0EAH,         (* FLDL2E *)
  0DEH, 0F9H,        (* FDIVP ST(1)/ST(0) *)
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0F1H,        (* FYL2X *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE -Pi():LONGREAL
  0D9H, 0EBH;        (* FLDPI *)

PROCEDURE -Exp(x: LONGREAL):LONGREAL
  0DDH, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0EAH,         (* FLDL2E *)
  0DEH, 0C9H,         (* FMULP ST(1), ST(0) *)
  0D9H, 0C0H,        (* FLD ST(0) *)
  0D9H, 0FCH,        (* FRNDINT *)
  0D9H, 0C9H,         (* FXCH ST(1), ST(0) *)
  0D8H, 0E1H,        (* FSUB ST(0), ST(1) *)
  0D9H, 0F0H,         (* F2XM1 *)
  0D9H, 0E8H,        (* FLD1 *)
  0DEH, 0C1H,         (* FADDP ST(1), ST(0) *)
  0D9H, 0FDH,         (* FSCALE *)
  0DDH, 0D9H,        (* FSTP ST(1) *)
  83H, 0C4H, 8;    (* ADD ESP, 8 (pop parameter from stack) *)

PROCEDURE sin*(x: LONGREAL): LONGREAL;
BEGIN IF x < 0.0D0 THEN RETURN -Sin(-x) ELSE RETURN Sin(x) END
END sin;

PROCEDURE cos*(x: LONGREAL): LONGREAL;
BEGIN IF x < 0.0D0 THEN RETURN Cos(-x) ELSE RETURN Cos(x) END
END cos;

PROCEDURE arctan*(x: LONGREAL): LONGREAL;
BEGIN RETURN Arctan(x)
END arctan;

PROCEDURE sqrt*(x: LONGREAL): LONGREAL;
VAR Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN
    IF x = 0 THEN RETURN 0 ELSE Error := "NEGATIVE ARGUMENT"; HALT(1080); END;
  ELSE RETURN Sqrt(x)
  END
END sqrt;

PROCEDURE ln*(x: LONGREAL): LONGREAL;
VAR Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN Error := "NEGATIVE ARGUMENT"; HALT(1080);
  ELSE RETURN Ln(x)
  END
END ln;

PROCEDURE exp*(x: LONGREAL): LONGREAL;
BEGIN RETURN Exp(x)
END exp;

BEGIN
  pi := Pi();
END MathL.
