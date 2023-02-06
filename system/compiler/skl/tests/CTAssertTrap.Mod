(* Copyright (c) 2021, 2023 Logic Magicians Software
 *)
MODULE CTAssertTrap;
IMPORT Console;

CONST
  FnLength* = 256; (* maximum pathname length (FILENAME_MAX) *)


PROCEDURE Test*;
BEGIN
  ASSERT(FnLength < 100, 2049);
END Test;

END CTAssertTrap.
