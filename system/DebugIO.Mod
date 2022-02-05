MODULE DebugIO;
  IMPORT Kernel, Reals, Files;

  CONST
    Filename = '.DiagnosticOutput';
    maxD = 9;

  VAR
    f : Files.File;
    r : Files.Rider;

  PROCEDURE Close*;
  BEGIN Files.Register(f);
  END Close;

  PROCEDURE Create;
  BEGIN f := Files.New(Filename); 
    Files.Set(r, f, 0); Files.WriteString(r, 'Oberon Diagnostic Output File'); 
    Files.Write(r, 0AX);
  END Create;

  PROCEDURE Open*;
  BEGIN f := Files.Old(Filename); Files.Set(r, f, Files.Length(f));
  END Open;

  PROCEDURE Header*(mod : Kernel.Module; f : ARRAY OF CHAR);
  BEGIN
    IF mod # NIL THEN Files.WriteString(r, mod.name^);
    ELSE Files.WriteString(r, '(no module)');
    END;
    Files.Write(r, '.'); Files.WriteString(r, f); Files.WriteString(r, ': ');
  END Header;

  PROCEDURE LCh(ch : CHAR); (* local character output; subverts frequent file opening and closing *)
  BEGIN Files.Write(r, ch);
  END LCh;

  PROCEDURE Ch*(ch : CHAR);
  BEGIN LCh(ch);
  END Ch;

  PROCEDURE LStr(s : ARRAY OF CHAR);
  BEGIN Files.WriteString(r, s);
  END LStr;
  
  PROCEDURE Str*(s : ARRAY OF CHAR);
  BEGIN LStr(s);
  END Str;
  
  PROCEDURE Bool*(b : BOOLEAN);
  BEGIN
    IF b THEN Files.WriteString(r, "TRUE");
    ELSE Files.WriteString(r, "FALSE");
    END;
  END Bool;
  
  PROCEDURE Hex*(x : LONGINT);
    VAR  i: LONGINT; y: LONGINT; a: ARRAY 10 OF CHAR;
  BEGIN
    i := 0;
    REPEAT
      y := x MOD 10H;
      IF y < 10 THEN a[i] := CHR(y + 30H) ELSE a[i] := CHR(y + 37H) END;
      x := x DIV 10H; INC(i)
    UNTIL i = 8;
    a[i] := 0X;
    REPEAT DEC(i); Ch(a[i]); UNTIL i = 0;
  END Hex;
  
  PROCEDURE LInt(x, n : LONGINT);
    VAR i: INTEGER; x0: LONGINT; a: ARRAY 11 OF CHAR;
  BEGIN i := 0;
    IF x < 0 THEN
      IF x = MIN(LONGINT) THEN Str(" -2147483648"); RETURN
      ELSE DEC(n); x0 := -x
      END
    ELSE x0 := x
    END;
    REPEAT a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i) UNTIL x0 = 0;
    WHILE n > i DO LCh(" "); DEC(n) END;
    IF x < 0 THEN LCh("-") END;
    REPEAT DEC(i); LCh(a[i]) UNTIL i = 0;
  END LInt;
  
  PROCEDURE Int*(x, n : LONGINT);
  BEGIN LInt(x, n);
  END Int;
  
  PROCEDURE Set*(s : SET);
    VAR i, j: INTEGER; notfirst: BOOLEAN;
  BEGIN
    i := 0; notfirst := FALSE; LCh("{");
    WHILE i <= MAX(SET) DO
      IF i IN s THEN
        IF notfirst THEN LStr(", ")
        ELSE notfirst := TRUE
        END ;
        j := i; LInt(i, 1); INC(i);
        WHILE (i <= MAX(SET)) & (i IN s) DO INC(i) END ;
        IF i - 1 > j THEN
          IF i - 2 = j THEN LStr(", ") ELSE LStr("..") END ;
          LInt(i - 1, 1)
        END
      END ;
      INC(i)
    END ;
    LCh("}");
  END Set;

  PROCEDURE Real*(x : REAL; n : INTEGER);
    VAR e: INTEGER; x0: REAL; d: ARRAY maxD OF CHAR;
  BEGIN e := Reals.Expo(x);
    IF e = 0 THEN LStr("  0"); REPEAT LCh(' '); DEC(n) UNTIL n <= 3
    ELSIF e = 255 THEN LStr(' NaN'); WHILE n > 4 DO LCh(' '); DEC(n) END
    ELSE
      IF n <= 9 THEN n := 3 ELSE DEC(n, 6) END;
      REPEAT LCh(' '); DEC(n) UNTIL n <= 8;
      (*there are 2 < n <= 8 digits to be written*)
      IF x < 0.0 THEN LCh('-'); x := -x ELSE LCh(' ') END;
      e := (e - 127) * 77  DIV 256;
      IF e >= 0 THEN x := x / Reals.Ten(e) ELSE x := Reals.Ten(-e) * x END;
      IF x >= 10.0 THEN x := 0.1*x; INC(e) END;
      x0 := Reals.Ten(n-1); x := x0*x + 0.5;
      IF x >= 10.0*x0 THEN x := x*0.1; INC(e) END;
      Reals.Convert(x, n, d);
      DEC(n); LCh(d[n]); LCh('.');
      REPEAT DEC(n); LCh(d[n]) UNTIL n = 0;
      LCh('E');
      IF e < 0 THEN LCh('-'); e := -e ELSE LCh('+'); END;
      LCh(CHR(e DIV 10 + 30H)); LCh(CHR(e MOD 10 + 30H));
    END;
  END Real;
  
  PROCEDURE LReal*(x : LONGREAL; n : INTEGER);
    CONST maxD = 16;
    VAR e: INTEGER; x0: LONGREAL; d: ARRAY maxD OF CHAR;
  BEGIN e := Reals.ExpoL(x);
    IF e = 0 THEN LStr("  0"); REPEAT LCh(' '); DEC(n) UNTIL n <= 3
    ELSIF e = 2047 THEN LStr(' NaN'); WHILE n > 4 DO LCh(' '); DEC(n) END
    ELSE
      IF n <= 10 THEN n := 3 ELSE DEC(n, 7) END;
      REPEAT LCh(' '); DEC(n) UNTIL n <= maxD;
      (*there are 2 <= n <= maxD digits to be written*)
      IF x < 0 THEN LCh('-'); x := -x ELSE LCh(' '); END;
      e := SHORT(LONG(e - 1023) * 77 DIV 256);
      IF e >= 0 THEN x := x / Reals.TenL(e) ELSE x := Reals.TenL(-e) * x END ;
      IF x >= 10.0D0 THEN x := 0.1D0 * x; INC(e) END ;
      x0 := Reals.TenL(n-1); x := x0*x + 0.5D0;
      IF x >= 10.0D0*x0 THEN x := 0.1D0 * x; INC(e) END ;
      Reals.ConvertL(x, n, d);
      DEC(n); LCh(d[n]); LCh('.');
      REPEAT DEC(n); LCh(d[n]) UNTIL n = 0;
      LCh('D');
      IF e < 0 THEN LCh('-'); e := -e ELSE LCh('+'); END;
      LCh(CHR(e DIV 100 + 30H)); e := e MOD 100; LCh(CHR(e DIV 10 + 30H)); LCh(CHR(e MOD 10 + 30H));
    END;
  END LReal;
  
  PROCEDURE Ln*;
  BEGIN Files.Write(r, 0AX);
  END Ln;

  PROCEDURE Init;
  BEGIN Create;
  END Init;
  
BEGIN Init;
END DebugIO.
