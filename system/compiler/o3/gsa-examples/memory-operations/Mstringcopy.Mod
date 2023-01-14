(* Copyright (c) 1997-2023 Logic Magicians Software *)
(*$ Mstringcopy: demonstrate string copy
 *
 * 1) literal source
 *    a) static local variable destination
 *    b) static global variable destination
 *    c) by-ref open array parm
 *    d) by-value open array parm
 *    e) by-ref static array parm
 *    f) by-value static array parm
 *    g) dynamic array
 * 2) static array source
 *    a) local array destination
 * 3) by-ref static array source
 *    a) local array destination
 * 4) by-value static array source
 *    a) local array destination
 * 5) by-ref open array source
 *    a) local array destination
 * 6) by-value open array source
 *    a) local array destination
 * 7) dynamic array source
 *    a) local array destination
 *)
MODULE Mstringcopy;

TYPE
  Base = RECORD
    field : ARRAY 151 OF CHAR;
  END;

VAR
  gd : Base;

(*% P1a: local variable destination *)
PROCEDURE P1a;
  VAR
    d : ARRAY 10 OF CHAR;
BEGIN
  COPY("hello", d);
END P1a;

(*% P1b: global variable destination *)
PROCEDURE P1b;
BEGIN
  COPY("hello", gd.field);
END P1b;

(*% P1c: by-ref open array parm *)
PROCEDURE P1c(VAR d : ARRAY OF CHAR);
BEGIN
  COPY("hello", d);
END P1c;

(*% P1d: by-value open array parm *)
PROCEDURE P1d(d : ARRAY OF CHAR);
BEGIN
  COPY("hello", d);
END P1d;

(*% P1e: by-ref static array parm *)
PROCEDURE P1e(VAR d : ARRAY 131 OF CHAR);
BEGIN
  COPY("hello", d);
END P1e;

(*% P1f: by value static array parm *)
PROCEDURE P1f(d : ARRAY 141 OF CHAR);
BEGIN
  COPY("hello", d);
END P1f;

(*% P1g: dynamic array *)
PROCEDURE P1g;
  VAR
    d : POINTER TO ARRAY OF CHAR;
BEGIN
  COPY("hello", d^);
END P1g;

(*% P2a: static array to static array *)
PROCEDURE P2a;
  VAR
    d : ARRAY 21 OF CHAR;
    array : ARRAY 31 OF CHAR;
BEGIN
  COPY(array, d);
END P2a;

(*% P3a: by-ref static array to static array *)
PROCEDURE P3a(VAR  array : ARRAY 31 OF CHAR);
  VAR
    d : ARRAY 21 OF CHAR;
BEGIN
  COPY(array, d);
END P3a;

(*% P4a: by-value static array to static array *)
PROCEDURE P4a(array : ARRAY 31 OF CHAR);
  VAR
    d : ARRAY 21 OF CHAR;
BEGIN
  COPY(array, d);
END P4a;

(*% P5a: by-ref open array to static array *)
PROCEDURE P5a(VAR array : ARRAY OF CHAR);
  VAR
    d : ARRAY 21 OF CHAR;
BEGIN
  COPY(array, d);
END P5a;

(*% P6a: by-value open array to static array *)
PROCEDURE P6a(array : ARRAY OF CHAR);
  VAR
    d : ARRAY 21 OF CHAR;
BEGIN
  COPY(array, d);
END P6a;

(*% P7a: dynamic array to static array *)
PROCEDURE P7a;
  VAR
    d : ARRAY 21 OF CHAR;
    array : POINTER TO ARRAY OF CHAR;
BEGIN
  COPY(array^, d);
END P7a;

END Mstringcopy.
