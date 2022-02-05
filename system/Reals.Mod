MODULE Reals;
  IMPORT SYSTEM;

  CONST
    Log10Conv =  2.30258509;
    Log10ConvL =  2.302585093D0;

  (* CONST H = 0; L = 4; (* big-endian machine *) *)
  CONST H = 4; L = 0; (* little-endian machine *)

  (* return biased exponent field of real number, 486 book, page 15-12 *)
  PROCEDURE Expo*(x: REAL): INTEGER;
  BEGIN RETURN SHORT(SYSTEM.LSH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, x) * { 23..30 }), -23));
  END Expo;
  
  (* return biased exponent field of longreal number, 486 book, page 15-12 *)
  PROCEDURE ExpoL*(x: LONGREAL): INTEGER;
    VAR v : LONGINT;
  BEGIN
    SYSTEM.GET(SYSTEM.ADR(x) + 4, v); (* high order dword of longreal *)
    RETURN SHORT(SYSTEM.LSH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, v) * { 20..30 }), -20));
  END ExpoL;

  (* set biased exponent of a number *)
  PROCEDURE SetExpo*(e: INTEGER; VAR x: REAL);
    VAR s : SET;
  BEGIN
    s := SYSTEM.VAL(SET, SYSTEM.LSH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, e) * {0..7}), 23));
    s := SYSTEM.VAL(SET, x) - {23..30} + s; x := SYSTEM.VAL(REAL, s);
  END SetExpo;

  PROCEDURE SetExpoL*(e: INTEGER; VAR x: LONGREAL);
    VAR s : SET;
  BEGIN
    s := SYSTEM.VAL(SET, SYSTEM.LSH(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, e) * {0..11}), 20));
    s := SYSTEM.VAL(SET, x) - {20..30} + s; x := SYSTEM.VAL(LONGREAL, s);
  END SetExpoL;

  (* return 10^e, approx: Math.exp(Log10Conv * e) *)
  PROCEDURE Ten*(e: INTEGER) : REAL;
    VAR x : REAL;
  BEGIN x := 1.0;
    IF e >= 0 THEN WHILE e > 0 DO x := x * 10.0; DEC(e); END;
    ELSE WHILE e < 0 DO x := x / 10.0; INC(e); END;
    END;
    RETURN x;
  END Ten;
  
  PROCEDURE TenL*(e: INTEGER): LONGREAL;
    VAR x : LONGREAL;
  BEGIN x := 1.0; 
    IF e >= 0 THEN WHILE e > 0 DO x := x * 10.0; DEC(e); END;
    ELSE WHILE e < 0 DO x := x / 10.0; INC(e); END;
    END;
    RETURN x;
  END TenL;
  
  (* 2 < n <= 8, prints a number into an array, padded with spaces on right *)
  PROCEDURE Convert*(x: REAL; n: INTEGER; VAR d: ARRAY OF CHAR);
    VAR y : LONGINT;
  BEGIN
    y := 0; WHILE y < LEN(d) DO d[y] := ' '; INC(y); END; (* pad with spaces *)
    REPEAT DEC(n); y := ENTIER(x / Ten(n)); d[n] := CHR(y + 30H); x := x - (y * Ten(n));
    UNTIL n = 0;
  END Convert;
  
  (* x < 10; 2 < n <= 9 *)
  PROCEDURE ConvertL*(x: LONGREAL; n: INTEGER; VAR d: ARRAY OF CHAR);
    VAR y : LONGINT;
  BEGIN
    y := 0; WHILE y < LEN(d) DO d[y] := ' '; INC(y); END; (* pad with spaces *)
    REPEAT DEC(n); y := ENTIER(x / TenL(n)); d[n] := CHR(y + 30H); x := x - (y * TenL(n));
    UNTIL n = 0;
  END ConvertL;
  
  PROCEDURE ConvertH*(x: REAL; VAR d: ARRAY OF CHAR);
    VAR v, i, j, k : LONGINT; ch : CHAR;
  BEGIN
    v := SYSTEM.VAL(LONGINT, x);
    i := 28; k := 0;
    REPEAT
      j := SYSTEM.LSH(v, -i) MOD 10H;
      IF j < 10 THEN ch := CHR(j + 30H); ELSE ch := CHR(j + 37H); END;
      d[k] := ch; INC(k); DEC(i, 4);
    UNTIL i < 0;
  END ConvertH;
  
  PROCEDURE ConvertHL*(x: LONGREAL; VAR d: ARRAY OF CHAR);
    VAR v, i, j, k : LONGINT; ch : CHAR;
  BEGIN
    i := 0; WHILE i < LEN(d) DO d[i] := '0'; INC(i); END;
    SYSTEM.GET(SYSTEM.ADR(x) + 4, v); i := 28; k := 0;
    REPEAT
      j := SYSTEM.LSH(v, -i) MOD 10H;
      IF j < 10 THEN ch := CHR(j + 30H); ELSE ch := CHR(j + 37H); END;
      d[k] := ch; INC(k); DEC(i, 4);
    UNTIL i < 0;
  
    SYSTEM.GET(SYSTEM.ADR(x), v); i := 28; k := 8;
    REPEAT
      j := SYSTEM.LSH(v, -i) MOD 10H;
      IF j < 10 THEN ch := CHR(j + 30H); ELSE ch := CHR(j + 37H); END;
      d[k] := ch; INC(k); DEC(i, 4);
    UNTIL i < 0;
  END ConvertHL;

  PROCEDURE Int* (x: REAL): LONGINT;
    VAR i: LONGINT;
  BEGIN SYSTEM.PUT(SYSTEM.ADR(i), x); RETURN i
  END Int;

  PROCEDURE IntL* (x: LONGREAL; VAR h, l: LONGINT);
  BEGIN SYSTEM.GET(SYSTEM.ADR(x) + H, h); SYSTEM.GET(SYSTEM.ADR(x) + L, l)
  END IntL;

END Reals.
