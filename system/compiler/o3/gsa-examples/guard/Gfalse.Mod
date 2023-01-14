(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Gfalse;
PROCEDURE P0;
  VAR
    g : INTEGER;
BEGIN
  IF FALSE THEN
    g := 100;
  ELSE
    g := 10;
  END;
END P0;
END Gfalse.
