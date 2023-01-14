(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Melement;

PROCEDURE access;
  VAR
    a : ARRAY 15 OF LONGREAL;
    ch : LONGREAL;
BEGIN
  ch := a[5];
END access;

PROCEDURE update;
  VAR
    a : ARRAY 15 OF CHAR;
    ch : CHAR;
BEGIN
  a[5] := 'A';
END update;

END Melement.
