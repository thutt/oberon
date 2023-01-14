(* Copyright (c) 1997-2023 Logic Magicians Software *)
(*$ Marraycopy: demonstrate $arraycopy
 *
 * Only array compatible arrays can be assigned
 * to one another, so this vastly simplifies the
 * codes that can actually generate $arraycopy.
 *
 *)
MODULE Marraycopy;

PROCEDURE P0;
  VAR
    a, b : ARRAY 30 OF INTEGER;
BEGIN
  a := b;
END P0;

PROCEDURE P1(VAR a, b : ARRAY 10 OF CHAR);
BEGIN
  b := a;
END P1;

PROCEDURE P2(a : ARRAY 10 OF CHAR);
END P2;

END Marraycopy.
