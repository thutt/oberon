(* Copyright (c) 1997-2023 Logic Magicians Software *)
(*$ Mrecordcopy: $recordcopy examples
 *
 *  0) equal record types
 *  1) assign from extension
 *  2) assign from extension to varparm
 *  3) assign from base(extension) to varparm
 *)
MODULE Mrecordcopy;

TYPE
  Base = POINTER TO BaseDesc;
  Extension = POINTER TO ExtDesc;
  BaseDesc = RECORD
    field : LONGREAL;
  END;

  ExtDesc = RECORD (BaseDesc)
    n : BOOLEAN;
  END;

PROCEDURE P0;
  VAR
    b0, b1 : BaseDesc;
BEGIN
  b0 := b1;
END P0;

PROCEDURE P1;
  VAR
    b0 : BaseDesc;
    b1 : ExtDesc;
BEGIN
  b0 := b1;
END P1;

PROCEDURE P2(VAR b0 : BaseDesc);
  VAR
    b1 : ExtDesc;
BEGIN
  b0 := b1;
END P2;

PROCEDURE P3(VAR b0 : BaseDesc);
  VAR
    b1 : ExtDesc;
BEGIN
  b1 := b0{ExtDesc};
END P3;

PROCEDURE P4(b0 : BaseDesc);
BEGIN
END P4;

END Mrecordcopy.
