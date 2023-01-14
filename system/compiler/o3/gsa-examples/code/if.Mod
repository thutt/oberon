(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE if;

  PROCEDURE P0(x, y : INTEGER);
  BEGIN
    IF x = 10 THEN y := 10;
    ELSE y := 12;
    END;
  END P0;

  PROCEDURE P1(x, y : INTEGER) : INTEGER;
  BEGIN
    x := 10;
    y := 10;
    IF (x = 10) & (y = 10) THEN
      y := 151;
    ELSE
      y := 12;
    END;
    RETURN y;
  END P1;

  PROCEDURE P2(x, y : INTEGER);
  BEGIN
    IF (x = 10) OR (y = 10) THEN
      y := 10;
    ELSE
      y := 12;
    END;
  END P2;

END if.
