(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test VMT operations.
 *)
MODULE CTVMT;
  IMPORT Console;

  TYPE
    Point = POINTER TO PointDesc;
    PointDesc = RECORD
      x : INTEGER;
      y : INTEGER;
    END;

    Point3D = POINTER TO Point3DDesc;
    Point3DDesc = RECORD (PointDesc)
      z : INTEGER;
    END;


  VAR
    i : INTEGER;
    y : INTEGER;
    s : SET;

  PROCEDURE LogWStr(s : ARRAY OF CHAR);
  BEGIN Console.Ln; Console.Str(s);  Console.Ln;
  END LogWStr;

  PROCEDURE (p : Point) Initialize;
  BEGIN
    LogWStr('Initialize');
    p.x := 0;
    p.y := 0;
  END Initialize;

  PROCEDURE (p : Point) Move(x, y : INTEGER);
  BEGIN
    LogWStr('Move');
    p.x := p.x + x;
    p.y := p.y + y;
  END Move;

  PROCEDURE VMTPoint;
    VAR
      p : Point;

  BEGIN
    NEW(p);
    p.Initialize;
    p.Move(10, 20);
  END VMTPoint;

  PROCEDURE (p : Point3D) MoveZ(x, y, z : INTEGER);
  BEGIN
    LogWStr('MoveZ');
    p.Move(x, y);
    p.z := p.z + z;
  END MoveZ;

  PROCEDURE (p : Point3D) Initialize;
  BEGIN
    LogWStr('Initialize3D');
    p.Initialize^;
    p.z := 0;
  END Initialize;

  PROCEDURE VMTPoint3D;
    VAR
      p : Point3D;

  BEGIN
    NEW(p);
    p.Initialize;
    p.MoveZ(10, 20, 30);
  END VMTPoint3D;

  PROCEDURE Test*;
  BEGIN
    VMTPoint;
    VMTPoint3D;
  END Test;

BEGIN
  i := 0;
  y := 2;
END CTVMT.
