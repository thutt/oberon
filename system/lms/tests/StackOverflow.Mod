MODULE StackOverflow;
IMPORT
  Console;

VAR
  depth : LONGINT;

PROCEDURE OverflowStack(a, b, c, d : INTEGER);
BEGIN
  Console.Str("Depth: ");
  Console.Int(depth, 3);
  Console.Ln;
  INC(depth);
  OverflowStack(a + 1, b + 3, c + 5, d + 7);
END OverflowStack;


PROCEDURE Test*;
BEGIN
  depth := 0;
  OverflowStack(0, 1, 3, 5);
END Test;

END StackOverflow.
