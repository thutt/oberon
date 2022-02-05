(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test nested functions and non-local variables.
 *)
MODULE CTNest;
  IMPORT Console;

  PROCEDURE LogWStr(s : ARRAY OF CHAR);
  BEGIN Console.Ln; Console.Str(s);  Console.Ln;
  END LogWStr;

  PROCEDURE Scaled;
    VAR
      arr : ARRAY 10 OF INTEGER;
      x : INTEGER;

    PROCEDURE ScaleNonLocal(i : INTEGER);
      PROCEDURE ScaleNonNonLocal(x : INTEGER);
      BEGIN
        arr[x + 1] := x;
      END ScaleNonNonLocal;

    BEGIN
      arr[i] := i;
      ScaleNonNonLocal(i);
    END ScaleNonLocal;

  BEGIN
    x := 0;
    WHILE x < LEN(arr) DO
      arr[x] := 151;
      INC(x);
    END;

    ScaleNonLocal(2);
    ScaleNonLocal(7);
    x := 0;
    WHILE x < LEN(arr) DO
      Console.Int(x, 5);
      Console.Ch(' ');
      Console.Int(arr[x], 5);
      Console.Ln;
      INC(x);
    END;
  END Scaled;


  (* The correct output from Global should look like this:
   *
   *  ---- a:     1 b:    -1 c:    -1 d:    -1
   *  L1.0 a:     1 b:     1 c:    -1 d:    -1
   *  L2.0 a:     2 b:     1 c:     3 d:    -1
   *  L2.1 a:     2 b:     4 c:     3 d:    -1
   *  L3.0 a:     2 b:     4 c:     3 d:     5
   *  L1.0 a:     2 b:     7 c:    -1 d:    -1
   *  L2.0 a:     8 b:     7 c:     9 d:    -1
   *  L2.1 a:     8 b:    10 c:     9 d:    -1
   *  L3.0 a:     8 b:    10 c:     9 d:    11
   *  L1.0 a:     8 b:    13 c:    -1 d:    -1
   *  L1.1 a:    14 b:    13 c:    -1 d:    -1
   *  L3.1 a:    14 b:    16 c:     9 d:    11
   *  L2.3 a:    14 b:    16 c:     9 d:    -1
   *  L1.1 a:    14 b:    16 c:    -1 d:    -1
   *  L3.1 a:    14 b:    10 c:     3 d:     5
   *  L2.3 a:    14 b:    10 c:     3 d:    -1
   *  L1.1 a:    14 b:    10 c:    -1 d:    -1
   *)
  PROCEDURE Global(a : INTEGER);
    PROCEDURE Log(label : ARRAY OF CHAR; l1, l2, l3 : INTEGER);
    BEGIN
      Console.Str(label);
      Console.Str(' a: ');
      Console.Int(a, 5);
      Console.Str(' b: ');
      Console.Int(l1, 5);
      Console.Str(' c: ');
      Console.Int(l2, 5);
      Console.Str(' d: ');
      Console.Int(l3, 5);
      Console.Ln;
    END Log;

    PROCEDURE L1(b : INTEGER);
      PROCEDURE L2(c : INTEGER);
        PROCEDURE L3(d : INTEGER);
        BEGIN
          Log("L3.0", b, c, d);
          b := c + 7;
          L1(d + 2);
          Log("L3.1", b, c, d);
        END L3;

      BEGIN
        Log("L2.0", b, c, -1);
        b := c + 1;
        Log("L2.1", b, c, -1);
        L3(c + 2);
        Log("L2.3", b, c, -1);
      END L2;

    BEGIN
      Log("L1.0", b, -1, -1);
      a := b + 1;
      IF b < 10 THEN
        L2(b + 2);
      END;
      Log("L1.1", b, -1, -1);
    END L1;

  BEGIN
    Log("----", -1, -1, -1);
    L1(1);
  END Global;

  PROCEDURE Test*;
  BEGIN
    Global(1);
    Scaled;
  END Test;

END CTNest.
