(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Ggate;

PROCEDURE P0(x : INTEGER) : INTEGER;
  VAR y : INTEGER;
BEGIN
  IF x = 10 THEN
    y := 1;
  ELSIF x = 20 THEN
    y := 2;
  ELSE
    y := 3;
  END;
  RETURN y;
END P0;

END Ggate.
