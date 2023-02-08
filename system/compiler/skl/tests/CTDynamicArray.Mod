(* Copyright (c) 2023 Logic Magicians Software
 *
 * Test code generation for pointer to multidimensional dynamic array.
 *)
MODULE CTDynamicArray;

TYPE
  Data = POINTER TO ARRAY OF ARRAY OF ARRAY OF BOOLEAN;

VAR
  v : Data;


PROCEDURE fn(i, j, k : INTEGER) : BOOLEAN;
BEGIN
  RETURN (i MOD 3 = 0) & ~ODD(j + k) OR ODD(k);
END fn;

PROCEDURE Set(v : Data);
  VAR
    i : INTEGER;
    j : INTEGER;
    k : INTEGER;
    b : BOOLEAN;
BEGIN
  ASSERT(LEN(v^, 0) = 9, 1024);
  ASSERT(LEN(v^, 1) = 6, 1025);
  ASSERT(LEN(v^, 2) = 3, 1026);

  i := 0;
  WHILE i < LEN(v^, 0) DO
    j := 0;
    WHILE j < LEN(v^, 1) DO
      k := 0;
      WHILE k < LEN(v^, 2) DO
        b := fn(i, j, k);
        v[i][j][k] := b;
        ASSERT(v[i][j][k] = fn(i, j, k), 1027);
        INC(k);
      END;
      INC(j);
    END;
    INC(i);
  END;
END Set;

PROCEDURE Verify(v : Data);
  VAR
    i   : INTEGER;
    j   : INTEGER;
    k   : INTEGER;
    b   : BOOLEAN;
    val : BOOLEAN;
BEGIN
  ASSERT(LEN(v^, 0) = 9, 2048);
  ASSERT(LEN(v^, 1) = 6, 2049);
  ASSERT(LEN(v^, 2) = 3, 2050);

  i := 0;
  WHILE i < LEN(v^, 0) DO
    j := 0;
    WHILE j < LEN(v^, 1) DO
      k := 0;
      WHILE k < LEN(v^, 2) DO
        b := fn(i, j, k);
        val := v[i][j][k];
        ASSERT(val = b, 2051);
        INC(k);
      END;
      INC(j);
    END;
    INC(i);
  END;
END Verify;


PROCEDURE Test*;
BEGIN
  Set(v);
  Verify(v);
END Test;

BEGIN
  NEW(v, 9, 6, 3);
END CTDynamicArray.
