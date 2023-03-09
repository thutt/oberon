(* Copyright (c) 2021, 2023 Logic Magicians Software
 *
 * Test code generation for open array array bounds checking.
 *)
MODULE CTOpenArray;
IMPORT
  SYSTEM;

CONST
  Dim1 = 2;
  Dim2 = 3;
  Dim3 = 20;

TYPE
  ADDRESS  = LONGINT;
  DataType = LONGINT;
  HeapData = POINTER TO ARRAY OF DataType;


PROCEDURE VerifyAddress(base    : ADDRESS;
                        element : ADDRESS;
                        i, lenI : LONGINT;
                        j, lenJ : LONGINT;
                        k, lenK : LONGINT);
  VAR
    a0, a1, computed : ADDRESS;
BEGIN
  a0 := i * lenJ;
  a1 := (a0 + j) * lenK;
  computed := base + (a1 + k) * SIZE(DataType);
  ASSERT(i < lenI, 1124);
  ASSERT(j < lenJ, 1125);
  ASSERT(k < lenK, 1126);
  ASSERT(element = computed);
END VerifyAddress;


PROCEDURE P0(s : ARRAY OF DataType; len : LONGINT); (* In / Out open array *)
BEGIN
  ASSERT(LEN(s) = len);
END P0;


PROCEDURE P11(ss : ARRAY OF ARRAY OF DataType); (* In-only open array *)
BEGIN
  ASSERT(LEN(ss, 0) = Dim2, 1024);
  ASSERT(LEN(ss, 1) = Dim3, 1025);
END P11;

PROCEDURE P1(VAR s : ARRAY OF DataType); (* In-only open array *)
BEGIN
  ASSERT(LEN(s) = Dim3, 1024);
  P0(s, LEN(s));
END P1;

PROCEDURE P2(s : HeapData); (* Heap-based open array *)
BEGIN
  ASSERT(LEN(s^) IN {17,Dim3}, 1024);
  P0(s^, LEN(s^));
END P2;


PROCEDURE Verify3D(VAR s : ARRAY OF ARRAY OF ARRAY OF DataType);
  VAR
   i, j, k : INTEGER;
BEGIN
  i := 0;
  WHILE i < LEN(s, 0) DO
    j := 0;
    WHILE j < LEN(s, 1) DO
      k := 0;
      WHILE k < LEN(s, 2) DO
        VerifyAddress(SYSTEM.ADR(s),
                      SYSTEM.ADR(s[i]),
                      i, LEN(s, 0),
                      0, LEN(s, 1),
                      0, LEN(s, 2));

        VerifyAddress(SYSTEM.ADR(s),
                      SYSTEM.ADR(s[i][j]),
                      i, LEN(s, 0),
                      j, LEN(s, 1),
                      0, LEN(s, 2));

        VerifyAddress(SYSTEM.ADR(s),
                      SYSTEM.ADR(s[i][j][k]),
                      i, LEN(s, 0),
                      j, LEN(s, 1),
                      k, LEN(s, 2));

        INC(k);
      END;
      INC(j);
    END;
    INC(i);
  END;
END Verify3D;


(* Stack:  [from sp]
 *             +14H   LEN(s, 0)
 *             +10H   LEN(s, 1)
 *             +0CH   LEN(s, 2)
 *             +08H   SYSTEM.ADR(s)
 *             +04H   return address
 *             +00H   stack pointer
 *)
PROCEDURE P3Var(base : ADDRESS;
                VAR s : ARRAY OF ARRAY OF ARRAY OF DataType);
BEGIN
  ASSERT(LEN(s, 0) = Dim1, 1024);
  ASSERT(LEN(s, 1) = Dim2, 1025);
  ASSERT(LEN(s, 2) = Dim3, 1026);

  ASSERT(base = SYSTEM.ADR(s), 1027);
  P1(s[1][2]);
END P3Var;


(* Stack:  [from sp]
 *             +14H   LEN(s, 0)
 *             +10H   LEN(s, 1)
 *             +0CH   LEN(s, 2)
 *             +08H   SYSTEM.ADR(s)
 *             +04H   return address
 *             +00H   stack pointer
 *)
PROCEDURE P3(s : ARRAY OF ARRAY OF ARRAY OF DataType);
BEGIN
  Verify3D(s);
  ASSERT(LEN(s, 0) = Dim1, 1024);
  ASSERT(LEN(s, 1) = Dim2, 1025);
  ASSERT(LEN(s, 2) = Dim3, 1026);
  P1(s[1][2]);
END P3;



PROCEDURE Test*;
 VAR
   s3 : ARRAY Dim1 OF ARRAY Dim2 OF ARRAY Dim3 OF DataType;
BEGIN
  Verify3D(s3);
  P3Var(SYSTEM.ADR(s3), s3);
  P3(s3);
END Test;

PROCEDURE Length(s : ARRAY OF CHAR) : INTEGER;
  VAR i : INTEGER; ch : CHAR;
BEGIN
  ch := s[i];
END Length;

END CTOpenArray.
