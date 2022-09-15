(* Copyright (c) 2021 Logic Magicians Software
 *
 * This module is used to show that the Oberon heap is of the right
 * size, has reasonable content, and is of the right size.
 *)
MODULE CTDumpHeap;
IMPORT Kernel;

PROCEDURE Test*;
BEGIN
  Kernel.DumpHeap;
END Test;

END CTDumpHeap.
