(* Copyright (c) 2022 Logic Magicians Software
 *)
MODULE CTEnvironment;
IMPORT Console, Environment;

PROCEDURE lookup(s : ARRAY OF CHAR);
  VAR
    v : Environment.Text;
BEGIN
  v := Environment.Lookup(s);
  Console.Str("key: '");
  Console.Str(s);
  Console.Str("'");
  IF v # NIL THEN
    Console.Str("  value: '");
    Console.Str(v^);
    Console.Str("'");
  ELSE
    Console.Str("  <not found>");
  END;
  Console.Ln;
END lookup;

PROCEDURE split;
  VAR
    v : Environment.Text;

  PROCEDURE verify(v : Environment.Text);
    VAR
      elem : Environment.Elements;
      i : INTEGER;
  BEGIN
    elem := Environment.Split(v, ':');
    Console.Str("Split '");
    Console.Str(v^);
    Console.Str("'  ");
    IF elem # NIL THEN
      Console.Int(LEN(elem^), 5);
      Console.Ln;
      WHILE i < LEN(elem^) DO
        Console.Str("  ");
        Console.Str(elem[i]^);
        Console.Ln;
        INC(i);
      END;
    ELSE
      Console.Str("<no data>");
    END;
    Console.Ln;
    i := 0;
  END verify;

  PROCEDURE work(val : ARRAY OF CHAR);
  BEGIN
    Environment.Set("SKL_DIR", val);
    v := Environment.Lookup("SKL_DIR");
    verify(v);
  END work;

BEGIN
  work(":::");
  work("alpha");
  work(":alpha");
  work("alpha:::");
  work("alpha::beta");
  work("alpha::beta:gamma");
END split;


PROCEDURE Test*;
BEGIN
  lookup("SKL_DIR");
  lookup("SKL_BUILD_DIR");
  lookup("SKL_BUILD_OPTIONS");
  lookup("SKL_BUILD_TYPE");
  lookup("GUNGLA");

  split;

  lookup("SKL_DIR");
  Environment.Delete("SKL_DIR");
  lookup("SKL_DIR");
END Test;

END CTEnvironment.
