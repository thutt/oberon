(* Copyright (c) 2022 Logic Magicians Software *)
MODULE Prime; (* Print prime numbers below 'N' *)
IMPORT Console;

CONST
  N = 100000;

VAR
  prime : ARRAY N OF BOOLEAN;

PROCEDURE Init;
  VAR
    i : LONGINT;
BEGIN
  i := 0;
  WHILE i < N DO
    prime[i] := TRUE;
    INC(i);
  END;
END Init;

PROCEDURE SetSeive;
  VAR 
    i,m : LONGINT;
BEGIN
  i := 2;
  WHILE i < N DIV 2 DO
    m := 2;
    WHILE m * i < N DO
      prime[m * i] := FALSE;
      INC(m);
    END;
    INC(i);
  END;
END SetSeive;

PROCEDURE ShowPrimes;
  VAR
    i, j : LONGINT;
BEGIN
  i := 1;
  j := 1;
  WHILE i < N DO
    IF prime[i] THEN
      Console.Int(j, 5);
      Console.Str(".  ");
      Console.Int(i, 5);
      Console.Ln;
      INC(j);
    END;
    INC(i);
  END;
END ShowPrimes;

PROCEDURE Execute*;
BEGIN
  Init;
  SetSeive;
  ShowPrimes;
END Execute;

END Prime.
