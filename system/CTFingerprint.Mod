MODULE CTFingerprint;
TYPE
  String*       = POINTER TO ARRAY OF CHAR;
  Pathname*     = POINTER TO PathnameDesc;
  PathnameDesc* = RECORD
    alpha : String;
    beta : String;
  END;


PROCEDURE (self : Pathname) Initialize(path : ARRAY OF CHAR);
END Initialize;


PROCEDURE (self : Pathname) pub*;
END pub;


PROCEDURE (self : Pathname) prv;
END prv;

PROCEDURE Test*;
END Test;

END CTFingerprint.
