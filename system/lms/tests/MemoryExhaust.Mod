(* Copyright (c) 2022 Logic Magicians Software *)
(*
 * This test module continues allocating data until the heap is
 * exhausted, and NEW sets the allocated pointer to NIL.
 *
 * This output file:
 *
 *   ${SKL_BUILD_DIR}/${SKL_BUILD_TYPE}/MemoryExhaust.out
 *
 * Will contain the log of the test run.  This will show the amount of
 * heap allocated after every call to Allocation.
 *
 * With the default 64Mb heap, the final lines of output should
 * look something like this:
 *
 *   1003240  69205824  allocated heap bytes
 *   1003241  69205888  allocated heap bytes
 *   1003242  69205968  allocated heap bytes
 *   1003243  69169376  allocated heap bytes [after vacuous GC]
 *   1003244  2249568  allocated heap bytes [after GC]
 *
 * The most interesting thing here is that the GC of this Oberon
 * implementation correctly marks, sweeps & collects stack-based
 * pointers.  The original ETH implementation could only be invoked if
 * there were no open procedures on the stack containing pointers; this
 * implementation can be invoked regardless the contents of the stack.
 *)
MODULE MemoryExhaust;
IMPORT
  Console,
  Kernel;

TYPE
  Data = POINTER TO DataDesc;
  DataDesc = RECORD
    next : Data;
    name : POINTER TO ARRAY OF CHAR;
  END;

VAR
  iterations : LONGINT;

PROCEDURE GetLength(m : LONGINT) : LONGINT;
  VAR
    r : LONGINT;
BEGIN
  REPEAT
    r := Kernel.InstructionCount() MOD m;
  UNTIL r # 0;
  RETURN r;
END GetLength;


PROCEDURE Allocate() : Data;
  VAR
    p : Data;
BEGIN
  NEW(p);
  IF p # NIL THEN
    p.next := NIL;
    NEW(p.name, GetLength(64));
  END;
  IF (p = NIL) OR (p.name = NIL) THEN
    RETURN NIL;
  ELSE
    RETURN p;
  END;
END Allocate;

PROCEDURE Status(final, gc : BOOLEAN);
BEGIN
  INC(iterations);
  Console.Int(iterations, 5);
  Console.Str("  ");
  Console.Int(Kernel.heap.allocated, 5);
  Console.Str("  allocated heap bytes");

  IF final THEN
    IF gc THEN
      Console.Str(" [after GC]");
    ELSE
      Console.Str(" [after vacuous GC]");
    END;
  END;
  Console.Ln;
END Status;


PROCEDURE Test*;
 VAR
   head : Data;
   p    : Data;
BEGIN
  LOOP
    Status(FALSE, FALSE);
    p := Allocate();
    IF p # NIL THEN
      p.next := head;
      head := p;
    ELSE
      Kernel.GC;
      Status(TRUE, FALSE); (* head is not NIL; GC vacuous *)

      head := NIL;
      Kernel.GC;
      Status(TRUE, TRUE);
      EXIT;
    END;
  END;
END Test;

BEGIN
  iterations := 0;
END MemoryExhaust.
