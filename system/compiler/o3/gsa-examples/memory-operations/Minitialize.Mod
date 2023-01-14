(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Minitialize;
IMPORT SYSTEM;

TYPE
  Base = RECORD
    x : LONGINT;
  END;

VAR
  gBase : Base;
  gArr : ARRAY 10 OF Base;

PROCEDURE P;
  VAR
    bool : BOOLEAN; byte : SYSTEM.BYTE;
    ch : CHAR;
    si : SHORTINT; i : INTEGER;
    li : LONGINT;
    r : REAL;
    lr : LONGREAL;
    s : SET;
    pointer : POINTER TO Base;
    procedure : PROCEDURE;
    record : Base;
    array : ARRAY 10 OF Base;
BEGIN
END P;

END Minitialize.
