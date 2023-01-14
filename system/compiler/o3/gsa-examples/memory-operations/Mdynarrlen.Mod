(* Copyright (c) 1997-2023 Logic Magicians Software *)
(*$ Mdynarrlen: shows code generated for various applications of LEN
 *  The following is an exhaustive consideration sizes for array types
 *
 * 1) global variable
 *    a) static size
 * 2) local variable
 *    a) static size
 * 2) dynamic array (heap-based)
 *    a) static size
 *    b) dynamic size
 * 3) by-value parameter
 *    a) static size
 *    b) open array
 * 4) by-reference parameter
 *    a) static size
 *    b) open array
 * 5) record field
 *    a) static size
 *    b) dynamic size
 * 6) array element
 *    a) static size
 *    b) dynamic size
 *)
MODULE Mdynarrlen;

TYPE
  A0 = POINTER TO ARRAY OF ARRAY OF INTEGER;
  A1 = POINTER TO ARRAY 151 OF ARRAY 251 OF LONGREAL;
  A2 = ARRAY 10, 20 OF A0;

  Base = RECORD
    static : ARRAY 91 OF CHAR;
    dynamic : POINTER TO ARRAY OF SHORTINT;
    array : ARRAY 121 OF A0;
    string : ARRAY 131 OF A2;
  END;

VAR
  len : LONGINT; (* Non-local to ensure a result in the output.
                  * Local variable may produce no output due to
                  * assignment of a Result to the local
                  *)
  global : ARRAY 10 OF ARRAY 20 OF CHAR;

  (*% P0: global variable, static size *)
PROCEDURE P0;
BEGIN
  len := LEN(global, 1);
END P0;

(*% P1: local variable, static size *)
PROCEDURE P1;
  VAR
    local : ARRAY 20 OF ARRAY 10 OF RECORD END;
BEGIN
  len := LEN(local, 1);
END P1;

(*% P2a: dynamic, static size *)
PROCEDURE P2a;
  VAR
    a1 : A1;
BEGIN
  len := LEN(a1^, 1);
END P2a;

(*% P2b: dynamic, dynamic size *)
PROCEDURE P2b;
  VAR
    a0 : A0;
BEGIN
  len := LEN(a0^, 1);
END P2b;

(*% P3a: by-value parameter, static size *)
PROCEDURE P3a(a : ARRAY 10, 151 OF INTEGER);
BEGIN
  len := LEN(a, 1);
END P3a;

(*% P3b: by-value parameter, open array *)
PROCEDURE P3b(a : ARRAY OF ARRAY OF INTEGER);
  VAR
    l : LONGINT;
BEGIN
  len := LEN(a, 0);
END P3b;

(*% P4a: by-value parameter, static size *)
PROCEDURE P4a(VAR a : ARRAY 10, 151 OF INTEGER);
BEGIN
  len := LEN(a, 1);
END P4a;

(*% P4b: by-value parameter, open array *)
PROCEDURE P4b(VAR a : ARRAY OF ARRAY OF INTEGER);
BEGIN
  len := LEN(a, 1);
END P4b;

(*% P5a: record field, static size *)
PROCEDURE P5a;
  VAR
    base : Base;
BEGIN
  len := LEN(base.static, 0);
END P5a;

(*% P5b: record field, dynamic size *)
PROCEDURE P5b;
  VAR
    base : Base;
BEGIN
  len := LEN(base.dynamic^, 0);
END P5b;

(*% P6a: array element, static size *)
PROCEDURE P6a;
  VAR
    base : Base;
BEGIN
  len := LEN(base.string[129], 0);
END P6a;

(*% P6b: array element, dynamic size *)
PROCEDURE P6b;
  VAR
    base : Base;
BEGIN
  len := LEN(base.array[27]^, 1);
END P6b;

END Mdynarrlen.
