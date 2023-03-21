MODULE Random;
IMPORT
  Console,
  RandomNumbers;

PROCEDURE Test*;
  VAR
    i : INTEGER;
    r : REAL;
    n : LONGINT;
BEGIN
  RandomNumbers.InitSeed(151);
  i := 0;
  WHILE i < 100 DO
    r := RandomNumbers.Uniform();
    n := ENTIER(r * 100);
    Console.Int(n, 3);
    Console.Ln;
    INC(i);
  END;
END Test;

END Random.
