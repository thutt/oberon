(* Copyright (c) 2021 Logic Magicians Software
 *
 * Test INC and DEC functionality.
 *)
MODULE CTIncDec;

  VAR
    i : INTEGER;
    y : INTEGER;
    s : SET;

  PROCEDURE IncDec(i : INTEGER);
  BEGIN
    INCL(s, i);
    INC(i, y);
    DEC(i, y);
  END IncDec;

  PROCEDURE IncDecVar(VAR i : INTEGER);
  BEGIN
    INC(i);
    DEC(i);
  END IncDecVar;

  PROCEDURE Test*;
  BEGIN
    IncDecVar(i);
    IncDec(i);
  END Test;

BEGIN
  i := 0;
  y := 2;
END CTIncDec.
