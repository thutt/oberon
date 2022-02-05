(* Copyright (c) 2021, 2022 Logic Magicians Software
 *
 * Test code generation with PROCEDURE and type bound procedures.
 *)
MODULE CTInstructionCount;
IMPORT Kernel, Console;

  PROCEDURE Test*;
    VAR beg, end : LONGINT;
  BEGIN
    beg := Kernel.InstructionCount();
    end := Kernel.InstructionCount();
    Console.Str("beg: ");
    Console.Int(beg, 10);
    Console.Ln;
    Console.Str("end: ");
    Console.Int(end, 10);
    Console.Ln;

    Console.Str("cnt: ");
    Console.Int(end - beg, 10);
    Console.Ln;
  END Test;

END CTInstructionCount.
