(* Copyright (c) 2021 Logic Magicians Software
 *
 * This module is used to exercise the garbage collector.
 *)
MODULE CTGC;
IMPORT Kernel, Console;

CONST
  StringLength = 23;            (* 22 characters + 0X. *)
  ArrLength = 11;

TYPE
  (* There are 10 unique types of memory blocks that can
   * be allocated in Oberon.
   *
   * T0. POINTER TO <record type>
   * T1. POINTER TO ARRAY OF <simple type>
   * T2. POINTER TO ARRAY OF <pointer type>
   * T3. POINTER TO ARRAY OF <record type>
   * T4. POINTER TO ARRAY OF <static array> OF <simple type>
   * T5. POINTER TO ARRAY OF <static array> OF <pointer type>
   * T6. POINTER TO ARRAY OF <static array> OF <record type>
   * T7. POINTER TO <static array> OF <simple type>
   * T8. POINTER TO <static array> OF <pointer type>
   * T9. POINTER TO <static array> OF <record type>
   *
   *)
  T0Desc = RECORD
    v : LONGINT;
  END;

  T0 = POINTER TO T0Desc;

  T1 = POINTER TO ARRAY OF CHAR;
  T2 = POINTER TO ARRAY OF T0;
  T3 = POINTER TO ARRAY OF T0Desc;

  T4 = POINTER TO ARRAY OF ARRAY StringLength OF CHAR;
  T5 = POINTER TO ARRAY OF ARRAY ArrLength OF T0;
  T6 = POINTER TO ARRAY OF ARRAY ArrLength OF T0Desc;

  T7 = POINTER TO ARRAY StringLength OF CHAR;
  T8 = POINTER TO ARRAY ArrLength OF T0;
  T9 = POINTER TO ARRAY ArrLength OF T0Desc;

  List = POINTER TO ListDesc;
  ListDesc = RECORD
    next : List;
    t0   : T0;
    t1   : T1;
    t2   : T2;
    t3   : T3;
    t4   : T4;
    t5   : T5;
    t6   : T6;
    t7   : T7;
    t8   : T8;
    t9   : T9;
  END;

VAR
  head : List;

PROCEDURE Allocate;
  CONST
    ModT0   = 5;
    ModT1   = 7;
    ModT2   = 9;
    ModT3   = 11;
    ModT4   = 13;
    ModT5   = 15;
    ModT6   = 17;
    ModT7   = 19;
    ModT8   = 23;
    ModT9   = 29;
    nAlloc  = 5000;          (* Number of allocations. *)

  VAR
    i : INTEGER;
    p : List;

  PROCEDURE FillString(VAR s : ARRAY OF CHAR);
    VAR
      l : INTEGER;
  BEGIN
    ASSERT(LEN(s) >= StringLength);
    l := i MOD StringLength;
    s[l] := 0X;
    WHILE l > 0 DO
      DEC(l);
      s[l] := CHR(ORD('A') + l);
    END;
  END FillString;


  PROCEDURE AllocateT0 (p : List);
  BEGIN
    NEW(p.t0);
    p.t0.v := 06131970H;
  END AllocateT0;

  PROCEDURE AllocateT1(p : List);
  BEGIN
    NEW(p.t1, StringLength);
    FillString(p.t1^);
  END AllocateT1;

  PROCEDURE AllocateT2(p : List);
    VAR
      l : INTEGER;
  BEGIN
    NEW(p.t2, ArrLength);
    l := 0;
    WHILE l < LEN(p.t2^) DO
      NEW(p.t2[l]);
      p.t2[l].v := 11161967H;
      INC(l);
    END;
  END AllocateT2;

  PROCEDURE AllocateT3(p : List);
    VAR
      l : INTEGER;
  BEGIN
    NEW(p.t3, ArrLength);
    l := 0;
    WHILE l < LEN(p.t3^) DO
      p.t3[l].v := 03051965H;
      INC(l);
    END;
  END AllocateT3;

  PROCEDURE AllocateT4(p : List);
    VAR
      l : INTEGER;
  BEGIN
    NEW(p.t4, ArrLength);
    l := 0;
    WHILE l < LEN(p.t4^) DO
      FillString(p.t4[l]);
      INC(l);
    END;
  END AllocateT4;

  PROCEDURE AllocateT5(p : List);
    VAR
      l, k : INTEGER;
  BEGIN
    NEW(p.t5, ArrLength);
    l := 0;
    WHILE l < LEN(p.t5^) DO
      k := 0;
      WHILE k < ArrLength DO
        NEW(p.t5[l][k]);
        p.t5[l][k].v := 02161963H;
        INC(k);
      END;
      INC(l);
    END;
  END AllocateT5;

  PROCEDURE AllocateT6(p : List);
    VAR
      l, k : INTEGER;
  BEGIN
    NEW(p.t6, ArrLength);
    l := 0;
    WHILE l < LEN(p.t6^) DO
      k := 0;
      WHILE k < ArrLength DO
        p.t6[l][k].v := 09021942H;
        INC(k);
      END;
      INC(l);
    END;
  END AllocateT6;

  PROCEDURE AllocateT7(p : List);
  BEGIN
    NEW(p.t7);
    FillString(p.t7^);
  END AllocateT7;

  PROCEDURE AllocateT8(p : List);
    VAR
      l : INTEGER;
  BEGIN
    NEW(p.t8);
    l := 0;
    WHILE l < LEN(p.t8^) DO
      NEW(p.t8[l]);
      p.t8[l].v := 02022004H;
      INC(l);
    END;
  END AllocateT8;

  PROCEDURE AllocateT9(p : List);
    VAR
      l : INTEGER;
  BEGIN
    NEW(p.t9);
    l := 0;
    WHILE l < LEN(p.t9^) DO
      p.t9[l].v := 06131937H;
      INC(l);
    END;
  END AllocateT9;

BEGIN
  i := 0;
  WHILE i < nAlloc DO
    INC(i);
    IF i MOD 100 = 0 THEN
      Console.Str("Allocating ");
      Console.Int(i, 10);
      Console.Ln;
    END;

    NEW(p);
    p.next := head.next;

    IF i MOD ModT0 = 0 THEN
      AllocateT0(p);
    END;

    IF i MOD ModT1 = 0 THEN
      AllocateT1(p);
    END;

    IF i MOD ModT2 = 0 THEN
      AllocateT2(p);
    END;

    IF i MOD ModT3 = 0 THEN
      AllocateT3(p);
    END;

    IF i MOD ModT4 = 0 THEN
      AllocateT4(p);
    END;

    IF i MOD ModT5 = 0 THEN
      AllocateT5(p);
    END;

    IF i MOD ModT6 = 0 THEN
      AllocateT6(p);
    END;

    IF i MOD ModT7 = 0 THEN
      AllocateT7(p);
    END;

    IF i MOD ModT8 = 0 THEN
      AllocateT8(p);
    END;

    IF i MOD ModT9 = 0 THEN
      AllocateT9(p);
    END;
  END;
END Allocate;

PROCEDURE Test*;
 VAR
   p : List;
   n : List;
   t1 : T1;
   i : INTEGER;
BEGIN
  i := 1116H;
  NEW(t1, 32);
  COPY("STACK BLOCK. Should GC!", t1^);
  NEW(t1, 32);
  COPY("STACK BLOCK. Should not GC!", t1^);
  Console.Str("--- Garbage collecting."); Console.Ln;
  Kernel.DumpHeap;
  Kernel.GC;
  Allocate;
  Console.Str("--- Garbage collecting."); Console.Ln;
  Kernel.GC;
  Kernel.GC;

  Kernel.DumpHeap;

  Console.Str("--- Removing every other node."); Console.Ln;

  i := 0;
  n := head;
  p := head.next;
  (* There must be at least three elements on the list. *)
  WHILE p # NIL DO
    IF ODD(i) THEN (* Remove 'p' from list. *)
      n.next := p.next;
      p      := p.next;
    ELSE
      n := p;
      p := p.next;
    END;
    INC(i);
  END;

  head := NIL;
  Kernel.GC;
  Kernel.DumpHeap;
END Test;

BEGIN
  NEW(head);                    (* Make dummy list head. *)
  head.next := NIL;
END CTGC.
