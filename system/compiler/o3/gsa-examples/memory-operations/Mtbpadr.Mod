(* Copyright (c) 1997-2023 Logic Magicians Software *)
MODULE Mtbpadr;
TYPE
  Base = POINTER TO BaseDesc;
  BaseDesc = RECORD
    field : INTEGER;
  END;

  Ext0 = POINTER TO Ext0Desc;
  Ext0Desc = RECORD (BaseDesc) END;
  Ext1 = POINTER TO Ext1Desc;
  Ext1Desc = RECORD (BaseDesc) END;

PROCEDURE (VAR x : BaseDesc) RefMethod(y : INTEGER);
BEGIN
END RefMethod;

PROCEDURE (x : Ext0) Method(y : INTEGER);
BEGIN
END Method;

PROCEDURE (x : Ext1) Method(y : INTEGER);
BEGIN
END Method;

PROCEDURE (x : Base) PtrMethod(y : INTEGER);
BEGIN
END PtrMethod;

PROCEDURE PointerCaller;
  VAR
    b : Base;
BEGIN
  b.PtrMethod(10);
END PointerCaller;

PROCEDURE VarParmCaller(VAR b : Base);
BEGIN
  b.PtrMethod(20);
END VarParmCaller;

PROCEDURE VarParmRefCaller(VAR b : BaseDesc);
BEGIN
  b.RefMethod(21);
END VarParmRefCaller;

PROCEDURE ParmCaller(b : Base);
BEGIN
  b.PtrMethod(20);
END ParmCaller;

PROCEDURE VarRefCaller;
  VAR
    b : BaseDesc;
BEGIN
  b.RefMethod(21);
END VarRefCaller;

PROCEDURE ParmRefCaller(b : BaseDesc);
BEGIN
  b.RefMethod(21);
END ParmRefCaller;

PROCEDURE NotCongruent;
  VAR
    b : Base;
BEGIN
  b{Ext0}.Method(0);
  b{Ext1}.Method(0);
END NotCongruent;

END Mtbpadr.
