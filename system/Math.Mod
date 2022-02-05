MODULE Math;

(* Math.Functions of the 387 *)
(* ARD, 21. 9. 92 *)
(* ARD, 10. 6. 94 diff between sin and cos of 386 and 486??? --> 1.0 not on tos *)


IMPORT SYSTEM;

CONST e* =    2.7182818285;
VAR
  pi- : REAL;
  
PROCEDURE -Sin(x: REAL):REAL
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FEH,        (* FSIN ST(0) *)
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE -Cos(x: REAL):REAL
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FFH,        (* FCOS ST(0) *)
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE -Arctan(x: REAL):REAL
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0E8H,        (* FLD1 *)
  0D9H, 0F3H,        (* FPATAN ST(1)/ST(0) *)
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE -Sqrt(x: REAL):REAL
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0FAH,        (* FSQRT ST(0) *)
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE -Ln(x: REAL):REAL
  0D9H, 0E8H,        (* FLD1 *)
  0D9H, 0EAH,         (* FLDL2E *)
  0DEH, 0F9H,        (* FDIVP ST(1)/ST(0) *)
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
  0D9H, 0F1H,        (* FYL2X *)
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE -Pi():REAL
  0D9H, 0EBH;        (* FLDPI *)

PROCEDURE -Exp(x: REAL):REAL
  0D9H, 44H, 24H, 04H,     (* FLD ST(0), 4[ESP] *)
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
  83H, 0C4H, 4;    (* ADD ESP, 4 (pop parameter from stack) *)

PROCEDURE sin*(x: REAL): REAL;
BEGIN IF x < 0.0 THEN RETURN -Sin(-x) ELSE RETURN Sin(x) END
END sin;

PROCEDURE cos*(x: REAL): REAL;
BEGIN IF x < 0.0 THEN RETURN Cos(-x) ELSE RETURN Cos(x) END
END cos;

PROCEDURE arctan*(x: REAL): REAL;
BEGIN RETURN Arctan(x)
END arctan;

PROCEDURE sqrt*(x: REAL): REAL;
VAR Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN
    IF x = 0 THEN RETURN 0 ELSE Error := "NEGATIVE ARGUMENT"; HALT(1280) END
  ELSE RETURN Sqrt(x)
  END
END sqrt;

PROCEDURE ln*(x: REAL): REAL;
VAR Error: ARRAY 32 OF CHAR;
BEGIN
  IF x <= 0 THEN Error := "NEGATIVE ARGUMENT"; HALT(1280)
  ELSE RETURN Ln(x)
  END
END ln;

PROCEDURE exp*(x: REAL): REAL;
BEGIN RETURN Exp(x)
END exp;

BEGIN
  pi := Pi();
END Math.
