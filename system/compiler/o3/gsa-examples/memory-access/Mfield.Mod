(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mfield;
TYPE
  RecDesc = RECORD
    x, y, z : INTEGER;
  END;

PROCEDURE access;
  VAR
    v : RecDesc;
    x : INTEGER;
BEGIN
  x := v.y;
END access;

PROCEDURE update;
  VAR
    v : RecDesc;
    x : INTEGER;
BEGIN
  v.y := x;
END update;

END Mfield.
