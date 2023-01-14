MODULE Pmayalias;

TYPE
  Record = POINTER TO RecordDesc;

  RecordDesc = RECORD
    x : INTEGER;
  END;

TYPE
  Extension = POINTER TO ExtensionDesc;
  ExtensionDesc = RECORD (RecordDesc)
    y : INTEGER;
  END;

VAR
  X  : INTEGER;
  LX : LONGINT;
  RD : RecordDesc;

PROCEDURE VarParmRecord(VAR r : RecordDesc; VAR i : INTEGER);
BEGIN
  r.x := 10;
  IF i = 10 THEN
    r.x := X;
    i := 12;
  END;
END VarParmRecord;

PROCEDURE Pointer(a : Record; b : Extension);
BEGIN
  a.x := X;
  IF b.y = X THEN
    b.x := X;
  END;
END Pointer;


(* X and x may alias *)
PROCEDURE Two(cc : BOOLEAN; y : INTEGER; VAR x : INTEGER);
  VAR z : INTEGER;
BEGIN
  INC(y);
  LX := LONG(x);
  z := X;
  INC(x);
  ASSERT(x = X);
  ASSERT(y = X);
  DEC(X);
  IF cc THEN
    X := z;
  ELSE
    x := y;
  END;
  x := X;
  y := x;
END Two;

(* X, x, and y may alias *)
PROCEDURE Three(cc : BOOLEAN; VAR y : INTEGER; VAR x : INTEGER);
  VAR z : INTEGER;
BEGIN
  INC(y);
  LX := LONG(x);
  z := X;
  INC(x);
  ASSERT(x = X);
  ASSERT(y = X);
  DEC(X);
  IF cc THEN
    X := z;
  ELSE
    x := y;
  END;
  x := X;
  y := x;
END Three;

END Pmayalias.
