(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE looping;

PROCEDURE loop(j : INTEGER) : INTEGER;
  VAR
    i : INTEGER;
BEGIN
  i := 100;
  j := 10;
  LOOP
    IF i = 100 THEN
      j := j + i + 1;
      EXIT;
    END;
  END;
  RETURN i + j;
END loop;

PROCEDURE repeat(j : INTEGER) : INTEGER;
  VAR
    i : INTEGER;
BEGIN
  i := 100;
  REPEAT
    INC(i);
  UNTIL i > j;
  RETURN i;
END repeat;

PROCEDURE while(j : INTEGER) : INTEGER;
  VAR
    i : INTEGER;
BEGIN
  i := 100;
  j := 99;
  WHILE i <= 100 DO
    INC(i);
  END;
  RETURN i;
END while;

END looping.
