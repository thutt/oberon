(* Copyright (c) 2022 Logic Magicians Software
 *
 * This module demonstrates GSA format for simple local variable
 * assignment and update thorugh a function call.
 *)
MODULE M00000;

PROCEDURE Read(VAR x : CHAR);
END Read;

PROCEDURE P0000;
  VAR
    kind : CHAR;
BEGIN
  kind := 0FFX;
  Read(kind);
END P0000;

PROCEDURE P0001(kind : CHAR);
BEGIN
  Read(kind);
END P0001;

PROCEDURE P0002(VAR kind : CHAR);
BEGIN
  kind := 0FFX;
  Read(kind);
END P0002;

END M00000.
