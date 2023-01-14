(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Madr;
IMPORT SYSTEM;

VAR
  global : INTEGER;

PROCEDURE UserGenerated;
  VAR
    li : LONGINT;
BEGIN
  li := SYSTEM.ADR(li);
END UserGenerated;

PROCEDURE CompilerGenerated;
BEGIN
  global := 0;
END CompilerGenerated;
END Madr.
