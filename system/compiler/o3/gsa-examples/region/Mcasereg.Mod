(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mcasereg;

CONST
 v0 = -3;
 v1 = -1;

PROCEDURE Int0(x : INTEGER) : INTEGER;
  VAR
    y : INTEGER;
BEGIN
  y := 11;
  CASE y OF
  | 6
    : RETURN 10;

  | 11:
    y := y + 15;
  END;
  RETURN y;
END Int0;

PROCEDURE Int1(x : INTEGER) : INTEGER;
BEGIN
  x := 10;
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
      RETURN 91;

    | 11, 13..15:
      x := 2;

    | 99, 50, 31, 32, 33:
      x := 3;
    END;
  ELSE
    x := 151;
  END;
  RETURN x;
END Int1;

PROCEDURE Char(ch : CHAR) : CHAR;
BEGIN
  CASE ch OF
  | 0FFX, 0X:
    ch := 'A';

  | 'A'..'Z', 'a', 'z':
    ch := '_';
  ELSE
    ch := 0X;
  END;
  RETURN ch;
END Char;

END Mcasereg.
