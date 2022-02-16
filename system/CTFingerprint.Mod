MODULE CTFingerprint;
TYPE
  Pathname*     = POINTER TO PathnameDesc;
  PathnameDesc* = RECORD
  END;


PROCEDURE (self : Pathname) Initialize(path : ARRAY OF CHAR);
END Initialize;


PROCEDURE (self : Pathname) pub*;
END pub;


PROCEDURE (self : Pathname) prv;
END prv;

END CTFingerprint.
