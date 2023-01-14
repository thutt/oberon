(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gcase;

CONST
 v0 = -3;
 v1 = -1;

PROCEDURE Int(x : INTEGER);
BEGIN
  IF x = 10 THEN
    CASE x OF
    | -4:
      x := 302;

    | v0..v1, 0..3:
      x := 301;

    | 5:
      x := 0;

    | 6..10:
      x := 1;
      RETURN;

    | 11, 13..15:
      x := 2;

    | 99, 50, 31, 32, 33:
      x := 3;
    END;
  ELSE
    x := 151;
  END;
  x := -1;
END Int;

PROCEDURE Char(ch : CHAR);
BEGIN
  CASE ch OF
  | 0FFX, 0X:
    ch := 'A';

  | 'A'..'Z', 'a', 'z':
    ch := '_';

  ELSE
    ch := 0X;
  END;
END Char;

END Gcase.
