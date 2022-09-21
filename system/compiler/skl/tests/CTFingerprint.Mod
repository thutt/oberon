(* Copyright (c) 2022 Logic Magicians Software *)

(* This module demonstrates fingerprinting failures in the compiler.
 *
 * Every time this module is compiled, err 125 is produced; which will
 * be fixed in SKLIE.Mod, or SKLST.Mod
 *
 *)
MODULE CTFingerprint;
TYPE
  String*       = POINTER TO ARRAY OF CHAR;
  Pathname*     = POINTER TO PathnameDesc;
  PathnameDesc* = RECORD
    alpha : String;
    beta : String;
  END;


PROCEDURE (self : Pathname) Recompose*() : String;
END Recompose;


PROCEDURE (self : Pathname) Delete*(beg, end : INTEGER);
END Delete;


PROCEDURE (self : Pathname) Insert*(beg : INTEGER;
                                    path : Pathname);
END Insert;


PROCEDURE Create*(path : ARRAY OF CHAR) : Pathname;
END Create;


PROCEDURE Test*;
END Test;

END CTFingerprint.
