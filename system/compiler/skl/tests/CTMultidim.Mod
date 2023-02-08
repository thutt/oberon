(* Copyright (c) 2023 Logic Magicians Software
 *
 * Test code generation for multidimensional array.
 *)
MODULE CTMultidim;

TYPE
  Data = ARRAY 9 OF ARRAY 6 OF BOOLEAN;

VAR
  v : Data;


PROCEDURE fn(i, j : INTEGER) : BOOLEAN;
BEGIN
  RETURN (i MOD 3 = 0) & ~ODD(j);
END fn;


PROCEDURE Test*;
  VAR
    i : INTEGER;
    j : INTEGER;
BEGIN
  ASSERT(LEN(v, 0) = 9, 1024);
  ASSERT(LEN(v, 1) = 6, 1025);

  i := 0;
  WHILE i < LEN(v, 0) DO
    j := 0;
    WHILE j < LEN(v, 1) DO
      v[i][j] := fn(i, j);
      ASSERT(v[i][j] = fn(i, j), 1027);
      INC(j);
    END;
    INC(i);
  END;
  
  i := 0;
  WHILE i < LEN(v, 0) DO
    j := 0;
    WHILE j < LEN(v, 1) DO
      ASSERT(v[i][j] = fn(i, j), 1028);
      INC(j);
    END;
    INC(i);
  END;
END Test;

BEGIN
END CTMultidim.
