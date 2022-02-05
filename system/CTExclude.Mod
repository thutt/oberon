(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTExclude;
IMPORT Console;

CONST
  avail = { 1..28 };

VAR
  free  : SET;

PROCEDURE use(r : LONGINT);
BEGIN
  EXCL(free, r);
END use;

PROCEDURE Test*;
CONST
  r = 28;

VAR
  expected : SET;
BEGIN
  expected := avail - {r};
  ASSERT(r IN avail);
  use(28);
  Console.Str(" free: "); Console.Set(free); Console.Ln;
  Console.Str(" expected: "); Console.Set(expected); Console.Ln;
END Test;

BEGIN
  free := avail;
END CTExclude.
