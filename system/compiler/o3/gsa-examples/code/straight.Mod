(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE straight;

TYPE
   Base = POINTER TO BaseDesc;
   Ext  = POINTER TO ExtDesc;
   BaseDesc = RECORD dummy0 : CHAR; bx, by : INTEGER; END;
   ExtDesc = RECORD (BaseDesc) dummy1 : BOOLEAN; ex, ey : INTEGER; END;

VAR
  x, y : INTEGER;
  b0, b1 : Base;
  bd0, bd1 : BaseDesc;
  e0, e1 : Ext;

PROCEDURE IntegralNone;
BEGIN x := 10; y := 10;
END IntegralNone;

PROCEDURE IntegralVarNonLocal(VAR x : INTEGER);
BEGIN
  x := 10;
  IF y = 10 THEN
    y := 0;
  END;
END IntegralVarNonLocal;

PROCEDURE IntegralNonLocalVar(VAR y : INTEGER);
BEGIN
  x := 10;
  IF y = 10 THEN
    y := 0;
  END;
END IntegralNonLocalVar;

PROCEDURE IntegralVarVar(VAR x, y : INTEGER);
BEGIN
  x := 10;
  IF y = 10 THEN
    y := 0;
  END;
END IntegralVarVar;

PROCEDURE PtrNone;
BEGIN
  b0 := NIL;
  b1 := NIL;
END PtrNone;

PROCEDURE PtrVarNonLocal(VAR b0 : Base);
BEGIN
  b0 := NIL;
  IF b1 # NIL THEN
    b1 := NIL;
  END;
END PtrVarNonLocal;

PROCEDURE PtrNonLocalVar(VAR b1 : Base);
BEGIN
  b0 := NIL;
  IF b1 # NIL THEN
    b1 := NIL;
  END;
END PtrNonLocalVar;

PROCEDURE PtrVarVar(VAR b0, b1 : Base);
BEGIN
  b0 := NIL;
  IF b1 # NIL THEN
    b1 := NIL;
  END;
END PtrVarVar;

PROCEDURE PtrFld(b0, b1 : Base);
BEGIN
  b0.bx := 0;
  IF b1.bx = 0 THEN
    b1.bx := 2;
  END;
END PtrFld;

PROCEDURE RecordFldLocal;
  VAR
    b0, b1 : BaseDesc;
BEGIN
  b0.bx := 0;
  b1.bx := 0;
END RecordFldLocal;

PROCEDURE RecordNonLocal;
BEGIN
  bd0 := bd1;
  bd1 := bd0;
END RecordNonLocal;

(* There are no possible aliases here because the data is
 * completely global.  Furthermore, the $access instruction (of the
 * global variables) both have a dynamic type of 'record', so there
 * is no match with the $update-field instructions
 *)
PROCEDURE RecordFldNonLocal;
BEGIN
  bd0.bx := 10;
  bd1.bx := 20;
END RecordFldNonLocal;
END straight.
