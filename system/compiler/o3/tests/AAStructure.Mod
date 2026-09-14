MODULE AAInteger;

TYPE
  Record = POINTER TO RecordDesc;

  RecordDesc = RECORD
    x : INTEGER;
  END;

TYPE
  Extension = POINTER TO ExtensionDesc;
  ExtensionDesc = RECORD (RecordDesc)
    y : CHAR;
  END;

VAR
  X  : INTEGER;
  LX : LONGINT;
  RP : Record;
  R  : RecordDesc;
  EP : Extension;
  E  : ExtensionDesc;
  S  : ARRAY 10 OF CHAR;

PROCEDURE StructureField(VAR r : RecordDesc);
BEGIN
  INC(r.x);
  ASSERT(r.x = R.x);
END StructureField;

PROCEDURE Array(VAR s : ARRAY 10 OF CHAR);
BEGIN
  S[5] := '?';
  ASSERT(s[5] = S[5]);
END Array;


PROCEDURE Integer(cc : BOOLEAN; y : INTEGER; VAR x : INTEGER);
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
END Integer;

END AAInteger.
