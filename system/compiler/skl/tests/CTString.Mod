(* Copyright (c) 2021, 2022 Logic Magicians Software
 *
 * Test code generation for string cmoparisons.
 *)
MODULE CTString;
IMPORT Console;

TYPE
  String = POINTER TO ARRAY OF CHAR;
  CompareFn = PROCEDURE(VAR l, r : ARRAY OF CHAR) : BOOLEAN;


PROCEDURE Equals(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l = r;
END Equals;


PROCEDURE NotEquals(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l # r;
END NotEquals;


PROCEDURE Greater(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l > r;
END Greater;


PROCEDURE LessEqual(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l <= r;
END LessEqual;


PROCEDURE Less(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l < r;
END Less;


PROCEDURE GreaterEqual(VAR l, r : ARRAY OF CHAR) : BOOLEAN;
BEGIN
  RETURN l >= r;
END GreaterEqual;


PROCEDURE Exercise(op : ARRAY OF CHAR;
                   compare : CompareFn;
                   VAR l, r : ARRAY OF CHAR);
  VAR
    result : BOOLEAN;
BEGIN
  result := compare(l, r);
  Console.Ch("'");
  Console.Str(l);
  Console.Str("' ");
  Console.Str(op);
  Console.Str(" '");
  Console.Str(r);
  Console.Str("' : ");
  Console.Bool(result);
  Console.Ln;
END Exercise;


PROCEDURE InvokeTest(l, r : ARRAY OF CHAR);
BEGIN
  Exercise('=', Equals, l, r);
  Exercise('#', NotEquals, l, r);
  Exercise('>', Greater, l, r);
  Exercise('>=', GreaterEqual, l, r);
  Exercise('<', Less, l, r);
  Exercise('<=', LessEqual, l, r);
END InvokeTest;  


PROCEDURE Test*;
  VAR
    l, r : ARRAY 20 OF CHAR;
    byte : String;
BEGIN
  NEW(byte, 5);
  COPY("BYTE", byte^);
  InvokeTest("ADR", byte^);
  InvokeTest("", "FileDesc");
  InvokeTest("File", "");
  InvokeTest("File", "FileDesc");
  InvokeTest("FileDesc", "File");
  InvokeTest("FileDesc", "FileDesc");
END Test;

END CTString.
