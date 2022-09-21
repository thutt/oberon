MODULE SKLPU; (* parser utilitiarian stuff *)
IMPORT
  ST:=SKLST, 
  OPS:=SKLOS, 
  OPM:=SKLMD, 
  T:=SKLT, 
  EL:=SKLERR;

  TYPE
    ForwardDesc =  RECORD
      typ : ST.Pointer;  (* declaration of the forward type *)
      name : OPS.Name;  (* name which is referenced by the forward *)
    END;

  CONST
    MaxForwardTypes = 15;

  VAR
    token* : SHORTINT;
    level* : SHORTINT;
    FwdPtr: ARRAY MaxForwardTypes OF ForwardDesc;

  PROCEDURE err(n : INTEGER);
  BEGIN OPM.err(n);
  END err;

  PROCEDURE ExprCompatPointer*(ext, base : ST.Type) : BOOLEAN;
    VAR b, e : ST.Type;
  BEGIN (* ASSERT(ext.type.form = pointer); *)
    IF base.form = ST.pointer THEN
      b := base(ST.Pointer).to; e := ext(ST.Pointer).to; RETURN ST.Extends(b, e) OR ST.Extends(e, b);
    ELSIF base.form = ST.nil THEN RETURN TRUE;
    ELSE RETURN FALSE;
    END;
  END ExprCompatPointer;

  PROCEDURE NewAnonSym*(VAR s : ST.Symbol; t : ST.Type);
  BEGIN s := ST.NewBasicSym(ST.anon); s.type := t;
  END NewAnonSym;

  PROCEDURE qualident*(VAR symb : ST.Symbol);  (* [{module} '.'] <ident> *)
    VAR id : ST.Symbol;
  BEGIN
    id := ST.Find(OPS.name); OPS.Get(token);
    IF (token = OPS.period) & (id # NIL) & ST.IsModule(id) THEN
      OPS.Get(token);
      IF token = OPS.ident THEN id := ST.FindImport(id(ST.SymbolProc), OPS.name); OPS.Get(token);
      ELSE OPM.err(EL.IdentExpected); id := NIL;
      END;
    END;
    IF id = NIL THEN OPM.err(EL.UndeclaredIdent); NewAnonSym(id, ST.undftyp);
    ELSIF (id.kind IN {ST.var, ST.par, ST.varpar}) & (id.mnolev # level) THEN EXCL(id.flags, ST.leaf);
    END;
    symb := id;
  END qualident;

  PROCEDURE Sync*(tok: SHORTINT; e : INTEGER);
  BEGIN IF token < tok THEN OPM.err(e); REPEAT OPS.Get(token) UNTIL token >= tok; END;
  END Sync;

  PROCEDURE Match*(tok : SHORTINT);
    VAR e : INTEGER;
  BEGIN
    IF token = tok THEN OPS.Get(token)
    ELSE
      CASE tok OF
        OPS.rbrak: e := EL.RbrakExpected;
      |  OPS.rbrace: e := EL.RbraceExpected;
      |  OPS.colon: e := EL.ColonExpected;
      |  OPS.rparen: e := EL.RparenExpected;
      |  OPS.to: e := EL.ToExpected;
      |  OPS.end: e := EL.EndExpected;
      |  OPS.then: e := EL.ThenExpected;
      |  OPS.of: e := EL.OfExpected;
      |  OPS.do: e := EL.DoExpected;
      |  OPS.until: e := EL.UntilExpected;
      |  OPS.becomes: e := EL.BecomesExpected;
      |  OPS.semicolon: e := EL.SemicolonExpected;
      |  OPS.ident: e := EL.IdentExpected;
      END;
      OPM.err(e);
    END;
  END Match;

  PROCEDURE InitForwardType*;
    VAR i : INTEGER;
  BEGIN
    i := 0; WHILE i < LEN(FwdPtr) DO FwdPtr[i].typ := NIL; FwdPtr[i].name[0] := 0X; INC(i); END;
  END InitForwardType;

  PROCEDURE NewForwardType*(typ : ST.Pointer; name : OPS.Name);
    VAR i : INTEGER;
  BEGIN
    i := 0; WHILE (i < LEN(FwdPtr)) & (FwdPtr[i].typ # NIL) DO INC(i); END;
    IF i < LEN(FwdPtr) THEN
      FwdPtr[i].typ := typ; COPY(name, FwdPtr[i].name); typ.to := ST.undftyp;
    ELSE err(EL.ForwardPtrs);
    END;
  END NewForwardType;

  PROCEDURE FixupForwardType*(symbol : ST.Symbol);
    VAR i : INTEGER; typ : ST.Pointer;
  BEGIN i := 0;
    WHILE i < LEN(FwdPtr) DO
      IF FwdPtr[i].name = symbol.name^ THEN
        typ := FwdPtr[i].typ; typ.to := symbol.type;
        FwdPtr[i].name[0] := 0X; FwdPtr[i].typ := NIL;
      END;
      INC(i);
    END;
  END FixupForwardType;

  PROCEDURE CheckForwardTypes*;
    VAR i : INTEGER;
  BEGIN (* check forward pointer declarations for completion *)
    i := 0;
    WHILE i < LEN(FwdPtr) DO
      IF FwdPtr[i].typ # NIL THEN err(EL.UnsatisfiedForwardType);
      ELSE FwdPtr[i].typ := NIL; (* GC *)
      END;
      INC(i);
    END;
  END CheckForwardTypes;

  PROCEDURE IsForward*(typ : ST.Type) : BOOLEAN;
    VAR i : INTEGER;
  BEGIN
    IF typ.form = ST.pointer THEN
      i := 0;
      WHILE i < LEN(FwdPtr) DO
        IF FwdPtr[i].typ = typ THEN RETURN TRUE; END;
        INC(i);
      END;
    END;
    RETURN FALSE;
  END IsForward;

  PROCEDURE SetVis*(VAR vis : SHORTINT);
  BEGIN
    OPS.Get(token);
    IF (token <= MAX(SET)) & (token IN {OPS.times, OPS.minus}) THEN
      IF level > 0 THEN err(EL.IllegalMark); END;
      IF token = OPS.times THEN vis := ST.export;
      ELSE vis := ST.exportR;
      END;
      OPS.Get(token);
    ELSE vis := ST.internal;
    END;
  END SetVis;

  PROCEDURE SetParmMode*(VAR mode : SHORTINT);
  BEGIN IF token = OPS.var THEN OPS.Get(token); mode := ST.varpar ELSE mode := ST.par END;
  END SetParmMode;
    
  PROCEDURE DistributeType*(list, stop : ST.Symbol; type : ST.Type; noDynArr : BOOLEAN);
  BEGIN
    IF noDynArr & (type.form = ST.dynarr) THEN err(EL.IllegalOpenArray); type := ST.undftyp; END;
    list.type := type;
    LOOP list.type := type;
      IF list = stop THEN EXIT; END;
      list := ST.NextSymbol(list);
    END;
  END DistributeType;
END SKLPU.
