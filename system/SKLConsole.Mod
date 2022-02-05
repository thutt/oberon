(* Copyright (c) 2021-2022 Logic Magicians Software *)
MODULE Console;
  IMPORT SYSTEM, Kernel, Reals;
  
  CONST (* SVCConsole.op *)
    svcWrite = 0;


  TYPE (* VMServiceDesc.service = Kernel.VMSVCConsole *)
    SVCConsole = RECORD (Kernel.VMServiceDesc)
      op     : LONGINT;         (* in: operation *)
      len    : LONGINT;         (* in: Number of bytes to write. *)
      buffer : LONGINT;         (* in: SYSTEM.ADR(buf) *)
    END;

  PROCEDURE ^ Hex*(x : LONGINT);
  PROCEDURE ^ Int*(x, n : LONGINT);

  PROCEDURE Bytes(VAR x : ARRAY OF SYSTEM.BYTE; len : LONGINT);
    VAR
      svc : SVCConsole;
  BEGIN
    svc.op     := svcWrite;
    svc.len    := len;
    svc.buffer := SYSTEM.ADR(x[0]);
    Kernel.VMService(Kernel.VMSVCConsole, svc);
  END Bytes;
  
  PROCEDURE Ch*(ch : CHAR);
  BEGIN Bytes(ch, 1);
  END Ch;
  
  PROCEDURE Ln*;
  BEGIN Ch(0AX);
  END Ln;

  PROCEDURE Str*(s : ARRAY OF CHAR);
    VAR i : LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      INC(i);
    END;
    Bytes(s, i);
  END Str;

  PROCEDURE Bool*(b : BOOLEAN);
  BEGIN
    IF b THEN
      Str('TRUE');
    ELSE
      Str('FALSE');
    END;
  END Bool;

  PROCEDURE Real*(x : REAL; n : INTEGER);
    (* BM 1993.4.22. Do not simplify rounding! *)
    VAR
      e : INTEGER;
      h, i: LONGINT;
      y: LONGREAL;
      z: REAL;
      d: ARRAY 8 OF CHAR;

  BEGIN
    e := Reals.Expo(x);
    IF e = 255 THEN
      WHILE n > 8 DO
        Ch(" ");
        DEC(n);
      END;
      Str("     NaN");
    ELSE
      IF n <= 8 THEN n := 1;
      ELSE DEC(n, 7);
      END;

      REPEAT
        Ch(" ");
        DEC(n);
      UNTIL n <= 7; (* 0 <= n <= 7 fraction digits *)

      IF (e # 0) & (x < 0) THEN
        Ch("-");
        x := -x;
      ELSE
        Ch(" ");
      END;
      IF e = 0 THEN
        h := 0 (* no denormals *)
      ELSE
        e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
        IF e < 38 THEN
          z := Reals.Ten(e+1);
          IF x >= z THEN
            y := LONG(x) / LONG(z);
            INC(e);
          ELSE
            y := x * Reals.Ten(-e);
          END;
        ELSE
          y := x * Reals.Ten(-38)
        END;
        IF y >= 10 THEN
          y := y * Reals.Ten(-1) + 0.5D0 / Reals.Ten(SHORT(n));
          INC(e);
        ELSE
          y := y + 0.5D0 / Reals.Ten(SHORT(n));
          IF y >= 10 THEN
            y := y * Reals.Ten(-1); INC(e);
          END;
        END;
        y := y * Reals.Ten(7);
        h := ENTIER(y);
      END;
      i := 7;
      WHILE i >= 0 DO
        d[i] := CHR(h MOD 10 + ORD("0"));
        h := h DIV 10;
        DEC(i);
      END;
      Ch(d[0]);
      Ch(".");
      i := 1;
      WHILE i <= n DO
        Ch(d[i]);
        INC(i);
      END;
      IF e < 0 THEN Str("E-"); e := - e;
      ELSE Str("E+");
      END;
      Ch(CHR(e DIV 10 + ORD("0")));
      Ch(CHR(e MOD 10 + ORD("0")));
    END;
  END Real;

  PROCEDURE LReal*(x : LONGREAL; n : INTEGER);
    (* BM 1993.4.22. Do not simplify rounding! *)
    VAR e, h, l, i: LONGINT; z: LONGREAL; d: ARRAY 16 OF CHAR;
  BEGIN
    e:= Reals.ExpoL(x);
    IF e = 2047 THEN
      WHILE n > 9 DO Ch(" "); DEC(n) END;
      Str("      NaN")
    ELSE
      IF n <= 9 THEN n:= 1 ELSE DEC(n, 8) END;
      REPEAT Ch(" "); DEC(n) UNTIL n <= 15; (* 0 <= n <= 15 fraction digits *)
      IF (e # 0) & (x < 0) THEN Ch("-"); x:= - x ELSE Ch(" ") END;
      IF e = 0 THEN h:= 0; l:= 0 (* no denormals *)
      ELSE e:= (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
        z:= Reals.TenL(SHORT(e+1));
        IF x >= z THEN x:= x/z; INC(e) ELSE x:= x * Reals.Ten(SHORT(-e)) END;
        IF x >= 10 THEN x:= x * Reals.TenL(-1) + 0.5D0 / Reals.TenL(SHORT(n)); INC(e)
        ELSE x:= x + 0.5D0 / Reals.Ten(SHORT(n));
          IF x >= 10 THEN x:= x * Reals.Ten(-1); INC(e) END
        END;
        x:= x * Reals.Ten(7); h:= ENTIER(x); x:= (x-h) * Reals.Ten(8); l:= ENTIER(x)
      END;
      i:= 15; WHILE i > 7 DO d[i]:= CHR(l MOD 10 + ORD("0")); l:= l DIV 10; DEC(i) END;
      WHILE i >= 0 DO d[i]:= CHR(h MOD 10 + ORD("0")); h:= h DIV 10; DEC(i) END;
      Ch(d[0]); Ch("."); i:= 1; WHILE i <= n DO Ch(d[i]); INC(i) END;
      IF e < 0 THEN Str("D-"); e:= - e ELSE Str("D+") END;
      Ch(CHR(e DIV 100 + ORD("0"))); e:= e MOD 100;
      Ch(CHR(e DIV 10 + ORD("0"))); Ch(CHR(e MOD 10 + ORD("0")))
    END
  END LReal;

  PROCEDURE Hex*(x : LONGINT);
    VAR  i: LONGINT; y: LONGINT; a: ARRAY 10 OF CHAR;
  BEGIN 
    i := 0;
    REPEAT
      y := x MOD 10H;
      IF y < 10 THEN
        a[i] := CHR(y + 30H)
      ELSE
        a[i] := CHR(y + 37H)
      END;
      x := x DIV 10H;
      INC(i);
    UNTIL i = 8;
    a[i] := 0X;
    REPEAT
      DEC(i);
      Ch(a[i]);
    UNTIL i = 0;
  END Hex;

  PROCEDURE Ptr*(p : SYSTEM.PTR);
  BEGIN
    Hex(SYSTEM.VAL(LONGINT, p));
  END Ptr;

  PROCEDURE Int*(x, n : LONGINT);
    VAR i: INTEGER; x0: LONGINT; a: ARRAY 11 OF CHAR;
  BEGIN
    i := 0;
    IF x < 0 THEN
      IF x = MIN(LONGINT) THEN
        Str(" -2147483648");
        RETURN;
      ELSE
        DEC(n);
        x0 := -x;
      END;
    ELSE
      x0 := x;
    END;
    REPEAT
      a[i] := CHR(x0 MOD 10 + 30H);
      x0 := x0 DIV 10;
      INC(i)
    UNTIL x0 = 0;
    WHILE n > i DO
      Ch( " ");
      DEC(n)
    END;
    IF x < 0 THEN
      Ch("-")
    END;
    REPEAT
      DEC(i);
      Ch(a[i])
    UNTIL i = 0;
  END Int;
  
  PROCEDURE Set*(s : SET);
    VAR i, j: INTEGER; notfirst: BOOLEAN;
  BEGIN
    i := 0;
    notfirst := FALSE;
    Ch("{");
    WHILE i <= MAX(SET) DO
      IF i IN s THEN
        IF notfirst THEN
          Str(", ");
        ELSE
          notfirst := TRUE;
        END;
        j := i;
        Int(i, 1);
        INC(i);
        WHILE (i <= MAX(SET)) & (i IN s) DO
          INC(i);
        END;
        IF i - 1 > j THEN
          IF i - 2 = j THEN
            Str(", ") ELSE
            Str("..");
          END;
          Int(i - 1, 1)
        END
      END ;
      INC(i)
    END ;
    Ch("}");
  END Set;

  PROCEDURE Open*; (* NOP; for API equivalence with DebugIO *)
  END Open;

  PROCEDURE Close*; (* NOP; for API equivalence with DebugIO *)
  END Close;

END Console.
