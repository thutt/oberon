(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mheap;
TYPE
  Rec = POINTER TO RecDesc;
  RecDesc = RECORD
    x : INTEGER;
  END;

VAR Gv : Rec;

PROCEDURE AccessLocal;
  VAR
    y : INTEGER;
    v : Rec;
BEGIN
  y := v.x;
END AccessLocal;

PROCEDURE AccessGlobal;
  VAR
    y : INTEGER;
BEGIN
  y := Gv.x;
END AccessGlobal;

PROCEDURE AccessHeap;
  VAR
    y : RecDesc;
    py : Rec;
BEGIN
  y := py^;
END AccessHeap;

PROCEDURE AccessNonlocal;
  VAR nl : Rec;

  PROCEDURE nla;
    VAR y : INTEGER;
  BEGIN
    y := nl.x;
  END nla;
END AccessNonlocal;

PROCEDURE UpdateLocal;
  VAR
    y : INTEGER;
    v : Rec;
BEGIN
  v.x := y;
END UpdateLocal;

PROCEDURE UpdateGlobal;
  VAR
    y : INTEGER;
BEGIN
  Gv.x := y;
END UpdateGlobal;

PROCEDURE UpdateNonlocal;
  VAR
    nl : Rec;
  PROCEDURE nlu;
    VAR
      y : INTEGER;
  BEGIN
    nl.x := y;
  END nlu;
END UpdateNonlocal;

PROCEDURE UpdateHeap;
  VAR
    y : RecDesc;
    py : Rec;
BEGIN
  py^ := y;
END UpdateHeap;

END Mheap.
