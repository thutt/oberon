(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mvarparm;

  IMPORT SYSTEM;

TYPE
  Record = RECORD x : INTEGER; END;
  Pointer = POINTER TO Record;
  Array = ARRAY 10 OF Record;
  PointerArray = POINTER TO ARRAY OF Record;

PROCEDURE UpdBYTE(VAR v : SYSTEM.BYTE);
  VAR
    b : SYSTEM.BYTE;
BEGIN
  v := b;
END UpdBYTE;

PROCEDURE UpdCHAR(VAR v : CHAR);
  VAR
    c : CHAR;
BEGIN
  v := c;
END UpdCHAR;

PROCEDURE UpdSHORTINT(VAR v : SHORTINT);
  VAR
    si : SHORTINT;
BEGIN
  v := si;
END UpdSHORTINT;

PROCEDURE UpdINTEGER(VAR v : INTEGER);
  VAR
    i : INTEGER;
BEGIN
  v := i;
END UpdINTEGER;

PROCEDURE UpdLONGINT(VAR v : LONGINT);
  VAR
    li : LONGINT;
BEGIN
  v := li;
END UpdLONGINT;

PROCEDURE UpdREAL(VAR v : REAL);
  VAR
    r : REAL;
BEGIN
  v := r;
END UpdREAL;

PROCEDURE UpdLONGREAL(VAR v : LONGREAL);
  VAR
    lr : LONGREAL;
BEGIN
  v := lr;
END UpdLONGREAL;

PROCEDURE UpdRecord(VAR v : Record);
  VAR
    record : Record;
BEGIN
  v := record; v.x := 0;
END UpdRecord;

PROCEDURE UpdPointer(VAR v : Pointer);
  VAR
    pointer : Pointer;
BEGIN
  v := pointer;
END UpdPointer;

PROCEDURE UpdArray(VAR v : Array);
  VAR
    array : Array;
BEGIN
  v := array;
END UpdArray;

PROCEDURE UpdPointerArray(VAR v : PointerArray);
  VAR
    pointerarray : PointerArray;
BEGIN
  v := pointerarray;
END UpdPointerArray;

PROCEDURE AccBYTE(VAR v : SYSTEM.BYTE);
  VAR
    b : SYSTEM.BYTE;
BEGIN
  b := v;
END AccBYTE;

PROCEDURE AccCHAR(VAR v : CHAR);
  VAR
    c : CHAR;
BEGIN
  c := v;
END AccCHAR;

PROCEDURE AccSHORTINT(VAR v : SHORTINT);
  VAR
    si : SHORTINT;
BEGIN
  si := v;
END AccSHORTINT;

PROCEDURE AccINTEGER(VAR v : INTEGER);
  VAR
    i : INTEGER;
BEGIN
  i := v;
END AccINTEGER;

PROCEDURE AccLONGINT(VAR v : LONGINT);
  VAR
    li : LONGINT;
BEGIN
  li := v;
END AccLONGINT;

PROCEDURE AccREAL(VAR v : REAL);
  VAR
    r : REAL;
BEGIN
  r := v;
END AccREAL;

PROCEDURE AccLONGREAL(VAR v : LONGREAL);
  VAR
    lr : LONGREAL;
BEGIN
  lr := v;
END AccLONGREAL;

PROCEDURE AccRecord(VAR v : Record);
  VAR
    record : Record;
BEGIN
  record := v;
  record.x := v.x;
END AccRecord;

PROCEDURE AccPointer(VAR v : Pointer);
  VAR
    pointer : Pointer;
BEGIN
  pointer := v;
END AccPointer;

PROCEDURE AccArray(VAR v : Array);
  VAR
    array : Array;
BEGIN
  array := v;
END AccArray;

PROCEDURE AccPointerArray(VAR v : PointerArray);
  VAR
    pointerarray : PointerArray;
BEGIN
  pointerarray := v;
END AccPointerArray;

END Mvarparm.
