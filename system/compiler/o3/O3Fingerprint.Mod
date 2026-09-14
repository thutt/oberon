MODULE O3Fingerprint;
  IMPORT
    SYSTEM;

  PROCEDURE FPrint*(VAR fp : LONGINT; val : LONGINT);
  BEGIN  fp := SYSTEM.ROT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, fp) / SYSTEM.VAL(SET, val)), 1);
  END FPrint;

  PROCEDURE FPrintSet*(VAR fp : LONGINT; val : SET);
  BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, val))
  END FPrintSet;

  PROCEDURE FPrintReal*(VAR fp : LONGINT; val : REAL);
  BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, val))
  END FPrintReal;

  PROCEDURE FPrintLReal*(VAR fp : LONGINT; val : LONGREAL);
    VAR l, h: LONGINT;
  BEGIN SYSTEM.GET(SYSTEM.ADR(val), l); SYSTEM.GET(SYSTEM.ADR(val)+4, h); FPrint(fp, l); FPrint(fp, h)
  END FPrintLReal;

  PROCEDURE FPrintBool*(VAR fp : LONGINT; val : BOOLEAN);
  BEGIN IF val THEN FPrint(fp, 1); ELSE FPrint(fp, 0); END;
  END FPrintBool;

END O3Fingerprint.
