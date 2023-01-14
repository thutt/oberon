(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Hget;
IMPORT SYSTEM;

PROCEDURE P0;
  VAR
    v : LONGINT;
BEGIN
  SYSTEM.GET(151, v);
END P0;

PROCEDURE P1;
  VAR
    v : CHAR;
BEGIN
  SYSTEM.GET(151, v);
END P1;

END Hget.
