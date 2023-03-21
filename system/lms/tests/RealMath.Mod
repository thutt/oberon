MODULE RealMath;
IMPORT
  Console,
  Math,
  MathL;

PROCEDURE Real;
BEGIN
  Console.Real(Math.pi, 15);                   (* 3.1415927E+00 *)
  Console.Ln;

  Console.Real(Math.arctan(Math.pi / 2), 15);  (* 1.0038848E+00 *)
  Console.Ln;

  Console.Real(Math.cos(Math.pi / 2), 15);     (* -4.3711388E-08 *)
  Console.Ln;

  Console.Real(Math.exp(Math.pi / 2), 15);     (* 4.8104777E+00 *)
  Console.Ln;

  Console.Real(Math.exp(Math.pi / 2), 15);     (* 4.8104777E+00 *)
  Console.Ln;

  Console.Real(Math.ln(Math.pi / 2), 15);      (* 4.5158273E-01 *)
  Console.Ln;

  Console.Real(Math.sqrt(Math.pi / 2), 15);    (* 1.2533141E+00 *)
  Console.Ln;

  Console.Real(Math.tan(Math.pi / 2), 15);     (* -2.2877329E+07 *)
  Console.Ln;
END Real;


PROCEDURE LongReal;
BEGIN
  Console.LReal(Math.pi, 15);                   (* 3.141593D+000 *)
  Console.Ln;

  Console.LReal(Math.arctan(Math.pi / 2), 15);  (* 1.003885D+000 *)
  Console.Ln;

  Console.LReal(Math.cos(Math.pi / 2), 15);     (* -4.371139D-008 *)
  Console.Ln;

  Console.LReal(Math.exp(Math.pi / 2), 15);     (* 4.810478D+000 *)
  Console.Ln;

  Console.LReal(Math.exp(Math.pi / 2), 15);     (* 4.810478D+000 *)
  Console.Ln;

  Console.LReal(Math.ln(Math.pi / 2), 15);      (* 4.515827D-001 *)
  Console.Ln;

  Console.LReal(Math.sqrt(Math.pi / 2), 15);    (* 1.253314D+000 *)
  Console.Ln;

  Console.LReal(Math.tan(Math.pi / 2), 15);     (* -2.287733D+007 *)
  Console.Ln;
END LongReal;

PROCEDURE Test*;
BEGIN
  Real;
  Console.Ln;
  LongReal;
END Test;

END RealMath.
