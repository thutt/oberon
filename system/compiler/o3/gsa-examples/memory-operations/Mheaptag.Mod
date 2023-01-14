(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mheaptag;
TYPE
  Rec = POINTER TO RecDesc;
  RecDesc = RECORD END;

PROCEDURE UpdateHeap;
  VAR
    y : RecDesc;
    py : Rec;
BEGIN
  py^ := y;
END UpdateHeap;
END Mheaptag.
