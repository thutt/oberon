(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mnewrecord;

TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD
    f : INTEGER;
    x : Base;
  END;

PROCEDURE P0;
  VAR
    p : Base;
BEGIN
  NEW(p);
  p.x.f := 151;
END P0;

PROCEDURE P1;
  VAR
    p, q : Base;
BEGIN
  NEW(p);
  NEW(q);
  p.x.f := 151;
  q.x := NIL;
END P1;

PROCEDURE P2;
  VAR
    p : Base;
BEGIN
  NEW(p);
  p.x.f := 151;
  NEW(p);
  p.x := NIL;
END P2;

PROCEDURE P3(VAR p : Base);
BEGIN
  NEW(p);
  NEW(p);
END P3;

PROCEDURE P4(VAR p : Base);
BEGIN
  NEW(p);
  NEW(p.x);
END P4;
END Mnewrecord.
