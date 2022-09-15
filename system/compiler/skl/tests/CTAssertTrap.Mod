(* Copyright (c) 2021 Logic Magicians Software
 *)
MODULE CTAssertTrap;
IMPORT Console;

CONST
  FnLength* = 256; (* maximum pathname length (FILENAME_MAX) *)


PROCEDURE Test*;
BEGIN
  ASSERT(FnLength < 100);
END Test;

END CTAssertTrap.
