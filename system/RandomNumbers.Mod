(* Random Number Generator, page 12 *)
MODULE RandomNumbers;
IMPORT Math;

VAR
  Z: LONGINT;

PROCEDURE Uniform*(): REAL;
  CONST
    a = 16807;
    m = 2147483647;
    q = m DIV a;
    r = m MOD a;

  VAR
    g: LONGINT;
BEGIN
  g := a * (Z MOD q) - r * (Z DIV q);
  IF g > 0 THEN
    Z := g;
  ELSE
    Z := g + m;
  END;
  RETURN Z * (1.0 / m);
END Uniform;

PROCEDURE Exp*(mu: REAL): REAL;
BEGIN
  RETURN -Math.ln(Uniform()) / mu;
END Exp;

PROCEDURE InitSeed*(seed: LONGINT);
BEGIN
  Z := seed;
END InitSeed;

BEGIN
  Z := 1;
END RandomNumbers.	(* Copyright M. Reiser, 1992 *)
