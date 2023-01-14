(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mnonlocal;
  IMPORT SYSTEM;

TYPE
  Record = RECORD x : INTEGER; END;
  Pointer = POINTER TO Record;
  Array = ARRAY 10 OF Record;
  PointerArray = POINTER TO ARRAY OF Record;

VAR
  b : SYSTEM.BYTE;
  c : CHAR;
  si : SHORTINT;
  i : INTEGER;
  li : LONGINT;
  r : REAL;
  lr : LONGREAL;
  record : Record;
  pointer : Pointer;
  array : Array;
  pointerarray : PointerArray;

PROCEDURE AccBYTE(v : SYSTEM.BYTE);
BEGIN
  v := b;
END AccBYTE;

PROCEDURE AccCHAR(v : CHAR);
BEGIN
  v := c;
END AccCHAR;

PROCEDURE AccSHORTINT(v : SHORTINT);
BEGIN
  v := si;
END AccSHORTINT;

PROCEDURE AccINTEGER(v : INTEGER);
BEGIN
  v := i;
END AccINTEGER;

PROCEDURE AccLONGINT(v : LONGINT);
BEGIN
  v := li;
END AccLONGINT;

PROCEDURE AccREAL(v : REAL);
BEGIN
  v := r;
END AccREAL;

PROCEDURE AccLONGREAL(v : LONGREAL);
BEGIN
  v := lr;
END AccLONGREAL;

PROCEDURE AccRecord(v : Record);
BEGIN
  v := record;
END AccRecord;

PROCEDURE AccPointer(v : Pointer);
BEGIN
  v := pointer;
END AccPointer;

PROCEDURE AccArray(v : Array);
BEGIN
  v := array;
END AccArray;

PROCEDURE AccPointerArray(v : PointerArray);
BEGIN
  v := pointerarray;
END AccPointerArray;

PROCEDURE UpdBYTE(v : SYSTEM.BYTE);
BEGIN
  b := v;
END UpdBYTE;

PROCEDURE UpdCHAR(v : CHAR);
BEGIN
  c := v;
END UpdCHAR;

PROCEDURE UpdSHORTINT(v : SHORTINT);
BEGIN
  si := v;
END UpdSHORTINT;

PROCEDURE UpdINTEGER(v : INTEGER);
BEGIN
  i := v;
END UpdINTEGER;

PROCEDURE UpdLONGINT(v : LONGINT);
BEGIN
  li := v;
END UpdLONGINT;

PROCEDURE UpdREAL(v : REAL);
BEGIN
  r := v;
END UpdREAL;

PROCEDURE UpdLONGREAL(v : LONGREAL);
BEGIN
  lr := v;
END UpdLONGREAL;

PROCEDURE UpdRecord(v : Record);
BEGIN
  record := v;
END UpdRecord;

PROCEDURE UpdPointer(v : Pointer);
BEGIN
  pointer := v;
END UpdPointer;

PROCEDURE UpdArray(v : Array);
BEGIN
  array := v;
END UpdArray;

PROCEDURE UpdPointerArray(v : PointerArray);
BEGIN
  pointerarray := v;
END UpdPointerArray;

END Mnonlocal.
