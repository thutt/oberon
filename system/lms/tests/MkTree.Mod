(* Copyright (c) 2022 Logic Magicians Software *)
MODULE MkTree;
IMPORT Console, FileDir;


PROCEDURE Create*;
  VAR
    r : BOOLEAN;
BEGIN
  r := FileDir.MkTree("/tmp/gungla/alpha/beta/gamma/delta");
  ASSERT(r);
END Create;


PROCEDURE Remove*;
  VAR
    r : BOOLEAN;
BEGIN
  r := FileDir.RmTree("/tmp/gungla");
  ASSERT(r);
END Remove;


PROCEDURE Test*;
BEGIN
  Create;
  Remove;
END Test;


END MkTree.
