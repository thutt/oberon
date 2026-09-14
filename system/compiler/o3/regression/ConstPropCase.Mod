(* Copyright (c) 2022 Logic Magicians Software
 *
 *)
MODULE ConstPropCase;

PROCEDURE Read(VAR ch : CHAR);
END Read;
git st
PROCEDURE UsesBlock;
  VAR
    kind : CHAR;
BEGIN
  CASE kind OF
  | 1X:
    Read(kind);
  ELSE
  END;
END UsesBlock;

END ConstPropCase.
