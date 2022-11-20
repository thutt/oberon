(* Copyright (c) 2022 Logic Magicians Software *)

(* This purpose of this simple module is to generate a software trap.
 * The software trap is a runtime error that will will cause the Oberon
 * runtime system to dump the program stack.  As a sample, this
 * facilitates familiarity with the stack dump and helps developers
 * learn how to debug Oberon failures.
 *
 *   skl-skl-oc system/lms/TrapSample.Mod
 *   skl-oberon TrapSample.Test
 *)
MODULE TrapSample;
IMPORT
  Console;

VAR
  set : SET;

PROCEDURE Include(beg, end : SHORTINT);
BEGIN
  Console.Str("set: ");
  Console.Str(" beg: ");
  Console.Int(beg, 3);
  Console.Str(" end: ");
  Console.Int(end, 3);
  Console.Str(" set: ");
  Console.Set(set);
  Console.Str(" --> ");
  set := { beg..end };
  Console.Set(set);
  Console.Ln;
  Include(beg, end + 1);
END Include;


PROCEDURE Test*;
BEGIN
  Include(28, 29);
END Test;

BEGIN
  set := { };
END TrapSample.
