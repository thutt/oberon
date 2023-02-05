MODULE SKLSP; (* Oberon parser *)
IMPORT
  ST:=SKLST,
  TB:=SKLTB,
  T:=SKLT,
  SP:=SKLSTP,
  E:=SKLE,
  PU:=SKLPU,
  OPS:=SKLOS,
  OPM:=SKLMD,
  IE:=SKLIE,
  EL:=SKLERR;

  VAR
    ImportList, ImportListTail : T.Import;
    LoopLevel : INTEGER;

  PROCEDURE ^ DeclarationSequence(VAR nestedProcs : T.Enter;
                                  VAR body : T.StmtList;
                                  VAR decl : T.Declaration);
  PROCEDURE ^ Type(banned: ST.Type) : ST.Type;

  PROCEDURE err(n : INTEGER);
  BEGIN
    OPM.err(n);
  END err;

  PROCEDURE CheckSysFlag(VAR sysflag: INTEGER; default: INTEGER);
    VAR
      x: T.Expr;
      sf: LONGINT;
  BEGIN
    IF PU.token = OPS.lbrak THEN
      OPS.Get(PU.token);
      x := E.ConstExpression();
      sf := default;
      IF x.type.form IN ST.IntSet THEN
        sf := x.val.i0;
      ELSE
        err(EL.NotInteger);
      END ;
      IF (sf < 0) OR (sf > OPM.MaxSysFlag) THEN
        sf := default;
        err(EL.IllegalValue);
      END;
      sysflag := SHORT(sf);
      PU.Match(OPS.rbrak);
      IF ~ST.SYSimported THEN
        err(EL.SystemNotImported);
      END;
    ELSE
      sysflag := default;
    END
  END CheckSysFlag;

  PROCEDURE FormalParameters(VAR firstPar : ST.Symbol; VAR resTyp: ST.Type);
    VAR
      mode: SHORTINT;
      par, first, res : ST.Symbol;
      parmType, pt : ST.Type;
  BEGIN
    firstPar := ST.FirstScopeVar(ST.topScope);
    IF (PU.token = OPS.ident) OR (PU.token = OPS.var) THEN
      LOOP
        first := NIL;
        PU.SetParmMode(mode);
        LOOP
          IF PU.token = OPS.ident THEN
            par := ST.NewBasicSym(mode);
            ST.Insert(OPS.name, par);
            OPS.Get(PU.token);
            IF first = NIL THEN
              first := par;
            END;
            IF firstPar = NIL THEN
              firstPar := par;
            END;
          ELSE
            err(EL.IdentExpected);
          END;

          CASE PU.token OF
          | OPS.comma:
            OPS.Get(PU.token);

          | OPS.ident:
            err(EL.CommaExpected);

          | OPS.var:
            err(EL.CommaExpected);
            OPS.Get(PU.token);
          ELSE
            EXIT;
          END;
        END ;
        PU.Match(OPS.colon);
        parmType := Type(ST.notyp);
        IF parmType.form = ST.dynarr THEN
          (* set flags so type size can calculate properly *)
          pt := parmType;
          WHILE pt.form = ST.dynarr DO
            INCL(pt.flags, ST.typDynArrParm);
            pt := pt(ST.Array).of;
          END;
        END;
        IF first # NIL THEN
          (* only if no parse error occurred *)
          PU.DistributeType(first, par, parmType, FALSE);
          IF mode = ST.par THEN
            (* pbused included when parameter type is parsed. *)
            INCL(par.type.flags, ST.pvused);
          END;
        END;

        CASE PU.token OF
        | OPS.semicolon: OPS.Get(PU.token);
        | OPS.ident: err(EL.SemicolonExpected);
        ELSE
          EXIT;
        END;
      END;
    END;

    PU.Match(OPS.rparen);
    resTyp := ST.notyp;
    IF PU.token = OPS.colon THEN
      (* result type *)
      OPS.Get(PU.token);
      IF PU.token = OPS.ident THEN
        PU.qualident(res);
        IF res.kind = ST.type THEN
          IF res.type.form IN ST.ReturnSet THEN
            resTyp := res.type;
          ELSE
            err(EL.IllegalResult);
          END;
        ELSE
          err(EL.NotAType);
        END;
      ELSE
        err(EL.IdentExpected);
      END;
    END
  END FormalParameters;

  PROCEDURE TypeDecl(banned: ST.Type) : ST.Type;
    VAR
      type : ST.Type;

    PROCEDURE RecordType(banned: ST.Type) : ST.Type;
      VAR
        type : ST.Record;
        base : ST.Symbol;
        sysflag: INTEGER;
        fld, first : ST.Symbol;
    BEGIN
      type := ST.NewRecordType();
      CheckSysFlag(sysflag, OPM.DefaultSysFlag);
      IF PU.token = OPS.lparen THEN
        OPS.Get(PU.token); (*record extension*)
        IF PU.token = OPS.ident THEN
          PU.qualident(base);
          IF (base.kind = ST.type) & (base.type.form = ST.record) THEN
            IF base.type # banned THEN
              (* private part implicitly needed by extension *)
              INCL(base.type.flags, ST.pvused);
              type.ancestor := base.type(ST.Record);
              type.extlev := base.type(ST.Record).extlev + 1;
              IF type.extlev > OPM.RecMaxExtension THEN
                (* remove for version 2 type descriptor layout *)
                err(EL.TooManyExtensions);
              END;
              (* should not be allowed to override base sysflag *)
              type.sysflag := base.type.sysflag;
            ELSE
              err(EL.RecursiveType);
            END;
          ELSE
            err(EL.NotAType);
          END;
        ELSE
          err(EL.IdentExpected)
        END;
        PU.Match(OPS.rparen)
      END;

      IF sysflag # OPM.DefaultSysFlag THEN
        type.sysflag := sysflag
      END;
      ST.OpenRecordScope();
      LOOP
        first := NIL;
        IF PU.token = OPS.ident THEN
          LOOP
            IF PU.token = OPS.ident THEN
              fld := ST.FindField(OPS.name, type.ancestor);
              IF fld # NIL THEN
                err(EL.MultipleDefinition)
              END;
              fld := ST.NewBasicSym(ST.field);
              ST.Insert(OPS.name, fld);
              PU.SetVis(fld.vis);
              IF first = NIL THEN
                first := fld;
              END;
            ELSE
              err(EL.IdentExpected)
            END;

            CASE PU.token OF
            | OPS.comma: OPS.Get(PU.token);
            | OPS.ident: err(EL.CommaExpected);
            ELSE
              EXIT;
            END;
          END;
          PU.Match(OPS.colon);
          PU.DistributeType(first, fld, Type(banned), TRUE);
          INCL(fld.type.flags, ST.pvused);
        END;

        CASE PU.token OF
        | OPS.semicolon: OPS.Get(PU.token);
        | OPS.ident: err(EL.SemicolonExpected);
        ELSE
          EXIT;
        END;
      END ;
      type.scope := ST.CloseScope();
      RETURN type;
    END RecordType;

    PROCEDURE ArrayType(banned: ST.Type) : ST.Type;
      VAR
        x: T.Expr;
        n: LONGINT;
        sysflag: INTEGER;
        atyp : ST.Array;
    BEGIN
      CheckSysFlag(sysflag, 0);

      IF PU.token = OPS.of THEN
        (*dynamic array*)
        atyp := ST.NewArrayType(ST.dynarr);
        OPS.Get(PU.token);
        atyp.of := Type(banned);
        INCL(atyp.of.flags, ST.pvused);
        (* Each dimension of a dynamic array shares the same td.
           It is not the same for static arrays. *)
        IF atyp.of.form = ST.dynarr THEN
          atyp.n := atyp.of(ST.Array).n + 1;
          ST.SetTD(atyp, ST.GetTD(atyp.of));
        ELSE
          atyp.n := 0
        END
      ELSE
        (* regular array *)
        atyp := ST.NewArrayType(ST.array);
        x := E.ConstExpression();
        IF (x.type.form IN ST.IntSet) THEN
          n := x.val.i0;
          IF (n <= 0) OR (n > OPM.MaxIndex) THEN
            err(EL.IllegalValue);
            n := 1;
          END
        ELSE
          err(EL.NotInteger); n := 1
        END ;
        atyp.n := n;

        IF PU.token = OPS.of THEN
          OPS.Get(PU.token);
          atyp.of := Type(banned);
          INCL(atyp.of.flags, ST.pvused);
        ELSIF PU.token = OPS.comma THEN
          OPS.Get(PU.token);
          IF PU.token # OPS.of THEN
            atyp.of := ArrayType(banned);
          END;
        ELSE
          err(EL.BadArrayDecl);
        END;
        IF atyp.of.form = ST.dynarr THEN
          err(EL.IllegalOpenArray);
          atyp.of:= ST.undftyp;
        END;
      END;
      atyp.sysflag := sysflag;
      RETURN atyp;
    END ArrayType;

    PROCEDURE PointerType() : ST.Type;
      VAR
        id: ST.Symbol;
        ptyp : ST.Pointer;
    BEGIN
      ptyp := ST.NewPointerType();
      CheckSysFlag(ptyp.sysflag, 0);
      PU.Match(OPS.to);
      IF PU.token = OPS.ident THEN
        id := ST.Find(OPS.name);
        IF id = NIL THEN
          PU.NewForwardType(ptyp, OPS.name);
          OPS.Get(PU.token);
        ELSE
          PU.qualident(id);
          IF id.kind = ST.type THEN
            IF id.type.form IN ST.AggregateSet THEN
              ptyp.to := id.type;
            ELSE
              ptyp.to := ST.undftyp;
              err(EL.IllegalPointsTo);
            END;
          ELSE
            err(EL.NotAType);
            ptyp.to := ST.undftyp;
          END;
        END;
      ELSE
        (* array, dynarr or record *)
        ptyp.to := Type(ST.notyp);
        IF ~(ptyp.to.form IN ST.AggregateSet) THEN
          err(EL.IllegalPointsTo);
          ptyp.to := ST.undftyp;
        END
      END;
      RETURN ptyp;
    END PointerType;

    PROCEDURE ProcedureType() : ST.Type;
      VAR
        ptype : ST.Procedure;
        dummy : ST.SymbolScope;
    BEGIN
      OPS.Get(PU.token);
      ptype := ST.NewProcedureType();
      CheckSysFlag(ptype.sysflag, 0);
      IF PU.token = OPS.lparen THEN
        OPS.Get(PU.token);
        ST.OpenProcedureScope(PU.level, NIL);
        FormalParameters(ptype.parms, ptype.result);
        dummy := ST.CloseScope();
      ELSE
        ptype.result := ST.notyp;
        ptype.parms := NIL;
      END;
      RETURN ptype;
    END ProcedureType;

    PROCEDURE TypeId() : ST.Type;
      VAR
        id: ST.Symbol;
        t : ST.Type;
    BEGIN
      t := ST.undftyp;
      PU.qualident(id);
      IF id.kind = ST.type THEN
        IF id.type # banned THEN
          t := id.type
        ELSE
          err(EL.RecursiveType);
        END;
      ELSE
        err(EL.NotAType);
      END;
      RETURN t;
    END TypeId;

  BEGIN
    type := ST.undftyp;
    PU.Sync(OPS.lparen, 12);
    CASE PU.token OF
    | OPS.ident:
      type := TypeId();

    | OPS.array:
      OPS.Get(PU.token);
      type := ArrayType(banned);

    | OPS.pointer:
      OPS.Get(PU.token);
      type := PointerType();

    | OPS.record:
      OPS.Get(PU.token);
      type := RecordType(banned);
      PU.Match(OPS.end);

    | OPS.procedure:
      type := ProcedureType();
    ELSE
      err(EL.BadTypeStart);
    END;

    LOOP
      CASE PU.token OF
      | OPS.semicolon..OPS.else, OPS.rparen, OPS.eof: EXIT;
      ELSE
        IF PU.token = OPS.ident THEN
          EXIT;
        END;
        err(EL.BadDeclEnd); OPS.Get(PU.token)
      END;
    END;
    RETURN type;
  END TypeDecl;

  PROCEDURE Type(banned: ST.Type) : ST.Type;
    VAR
      typ : ST.Type;
  BEGIN
    typ := TypeDecl(banned);
    (* do not allow POINTER TO undef in declarations *)
    IF (typ.form = ST.pointer) &
       (typ(ST.Pointer).to = ST.undftyp) &
       ~PU.IsForward(typ) THEN
      err(EL.UndeclaredIdent)
    END;
    RETURN typ;
  END Type;

  PROCEDURE StatSeq(VAR stmt : T.StmtList);
    VAR
      lhs : T.Design;
      rhs : T.Expr;
      headStmt, lastStmt, curStmt : T.StmtList;
      id, fp : ST.Symbol; (* formal parm list *)
      aparm : T.Arg;
      owner : ST.Symbol;

    PROCEDURE CheckBool(x: T.Expr) : T.Expr;
    BEGIN
      IF (x.class = T.Ndsgn) & ~(x.subcl IN T.RValueSet) THEN
        err(EL.RvalueRequired); x := TB.NewBoolConst(FALSE)
      END;
      IF x.type # ST.booltyp THEN
        err(EL.BooleanRequired);
        x := TB.NewBoolConst(FALSE);
      END;
      RETURN x;
    END CheckBool;

    PROCEDURE Assign(lhs : T.Design) : T.Assign;
      VAR
        rhs : T.Expr;
    BEGIN
      IF PU.token = OPS.eql THEN
        err(EL.BecomesExpected);
      END;
      OPS.Get(PU.token);
      rhs := E.Expression();
      IF (lhs.class = T.Ndsgn) & (lhs.subcl IN T.RValueSet) THEN
        IF T.readonly IN lhs.flags THEN
          err(EL.ReadOnlyVariable);
        END;
        rhs := E.AssignCompat(lhs.type, rhs);
      ELSE
        err(EL.NotAVariable);
      END;
      RETURN TB.NewAssign(lhs, rhs, lhs.type);
    END Assign;

    PROCEDURE IfStat() : T.StmtList;
      VAR
        test : T.Expr;
        stmt, else : T.StmtList;
        if, elsif, tif : T.IfBody;
    BEGIN
      test := CheckBool(E.Expression());
      PU.Match(OPS.then);
      StatSeq(stmt);
      if := T.NewIfBodyNode(test, stmt);
      tif := if;
      WHILE PU.token = OPS.elsif DO
        OPS.Get(PU.token);
        test := CheckBool(E.Expression());
        PU.Match(OPS.then);
        StatSeq(stmt);
        elsif := T.NewIfBodyNode(test, stmt);
        T.BindIfElsif(tif, elsif);
        tif := elsif;
      END;
      IF PU.token = OPS.else THEN
        OPS.Get(PU.token);
        StatSeq(else);
      ELSE
        else := TB.NewNullStmt();
      END;
      PU.Match(OPS.end);
      RETURN T.NewIfElseNode(if, else);
    END IfStat;

    PROCEDURE  CaseStat() : T.StmtList;
      TYPE
        CaseEntry = RECORD
          low, high: LONGINT;
        END;
        CaseTable = ARRAY OPM.MaxCases OF CaseEntry;

      VAR
        stmt, else : T.StmtList;
        expr : T.Expr;
        tab : CaseTable;
        cases, caseTail : T.SingleCase;
        label : T.CaseBounds;
        range : ST.Const;
        low, high : LONGINT;
        n : INTEGER;

      PROCEDURE CaseLabelList(LabelForm : INTEGER;
                              VAR n : INTEGER;
                              VAR tab : CaseTable) : T.CaseBounds;
        VAR
          head : T.CaseBounds;
          lo, hi : T.Expr;
          loval, hival : LONGINT;
          i : INTEGER;
          hf, f : SHORTINT;

      BEGIN
        head := NIL;
        LOOP
          lo := E.ConstExpression();
          f := lo.type.form;
          IF f IN ST.IntSet + {ST.char} THEN
            loval := lo.val.i0;
          ELSE
            err(EL.IllegalLabelType);
            loval := 1;
          END;

          IF f IN ST.IntSet THEN
            IF LabelForm < f THEN
              err(EL.WrongLabelType);
            END;
          ELSIF LabelForm # f THEN
            err(EL.WrongLabelType);
          END;

          IF PU.token = OPS.upto THEN
            OPS.Get(PU.token);
            hi := E.ConstExpression();
            hival := hi.val.i0;
            hf := hi.type.form;
            IF (hf # f) & ~((f IN ST.IntSet) & (hf IN ST.IntSet)) THEN
              err(EL.WrongLabelType);
            END;
            IF hival < loval THEN
              err(EL.IllegalValue);
              hival := loval;
            END;
          ELSE
            hival := loval;
          END;
          lo.val.i1 := hival;

          (*enter label range into ordered table*)
          i := n;
          IF i < OPM.MaxCases THEN
            LOOP
              IF i = 0 THEN
                EXIT;
              END;
              IF tab[i - 1].low <= hival THEN
                IF tab[i - 1].high >= loval THEN
                  err(EL.DuplicateLabel);
                END;
                EXIT;
              END;
              tab[i] := tab[i - 1];
              DEC(i);
            END ;
            tab[i].low := loval;
            tab[i].high := hival;
            INC(n)
          ELSE
            err(EL.TooManyCases)
          END;

          head := T.BindCaseBounds(head, T.NewCaseBoundsNode(lo.val));

          CASE PU.token OF
          | OPS.comma: OPS.Get(PU.token);
          | OPS.number, OPS.ident: err(EL.CommaExpected);
          ELSE
            EXIT;
          END;
        END;
        RETURN head;
      END CaseLabelList;

    BEGIN
      n := 0;
      cases := NIL;
      caseTail := NIL;
      expr := E.Expression();
      PU.Match(OPS.of);
      IF ~(expr.type.form IN {ST.char..ST.lint}) THEN
        err(EL.InvalidCaseType);
        expr := TB.NewIntConst(0);
      END;
      LOOP
        IF (PU.token = OPS.ident) OR (PU.token = OPS.number) THEN
          label := CaseLabelList(expr.type.form, n, tab);
          PU.Match(OPS.colon);
          StatSeq(stmt);
          caseTail := T.BindSingleCase(caseTail,
                                       T.NewSingleCaseNode(label, stmt));
          IF cases = NIL THEN
            cases := caseTail;
          END;
        END;
        IF PU.token = OPS.bar THEN
          OPS.Get(PU.token);
        ELSE
          EXIT;
        END;
      END;

      IF n > 0 THEN
        low := tab[0].low;
        high := tab[n - 1].high;
        IF high - low > OPM.MaxCaseRange THEN
          err(EL.CaseRangeTooLarge)
        END;
      ELSE
        low := 1;
        high := 0;
      END;

      IF PU.token = OPS.else THEN
        OPS.Get(PU.token);
        StatSeq(else)
      ELSE
        else := T.NewHaltNode(TB.NewBoolConst(FALSE),
                              TB.NewIntConst(OPM.HaltCase));
      END;
      PU.Match(OPS.end);
      RETURN T.NewCaseNode(expr, T.NewCaseStatNode(low, high, cases, else));
    END CaseStat;

    PROCEDURE  WhileStat() : T.StmtList;
      VAR
        x : T.Expr;
        s : T.StmtList;
    BEGIN
      x := CheckBool(E.Expression());
      PU.Match(OPS.do);
      StatSeq(s);
      PU.Match(OPS.end);
      RETURN TB.NewWhile(x, s);
    END WhileStat;

    PROCEDURE  RepeatStat() : T.StmtList;
      VAR
        x : T.Expr;
        s : T.StmtList;
    BEGIN
      StatSeq(s);
      PU.Match(OPS.until);
      x := CheckBool(E.Expression());
      RETURN TB.NewRepeat(x, s);
    END RepeatStat;

    PROCEDURE  LoopStat() : T.StmtList;
      VAR
        s : T.StmtList;
    BEGIN
      INC(LoopLevel);
      StatSeq(s);
      PU.Match(OPS.end);
      DEC(LoopLevel);
      RETURN T.NewLoopNode(s);
    END LoopStat;

    PROCEDURE ForStat() : T.StmtList;
      VAR
        ctrlV : ST.Symbol;
        control : T.Design;
        lower, upper, step : T.Expr;
        body : T.StmtList;
    BEGIN
      IF PU.token = OPS.ident THEN
        PU.qualident(ctrlV);
        control := TB.NewDesign(ctrlV);
        PU.Match(OPS.becomes);
        lower := E.Expression();
        PU.Match(OPS.to);
        upper := E.Expression();
        IF PU.token = OPS.by THEN
          OPS.Get(PU.token);
          step := E.ConstExpression();
          IF ~(step.type.form IN ST.IntSet) OR (step.val.i0 = 0) THEN
            err(EL.IllegalValue);
            step := TB.NewIntConst(1);
          END;
        ELSE
          step := TB.NewIntConst(1);
        END;
        PU.Match(OPS.do);
        StatSeq(body);
        PU.Match(OPS.end);
        RETURN TB.NewFor(control, lower, upper, step.val.i0, body);
      ELSE
        err(EL.IdentExpected);
        RETURN TB.NewNullStmt();
      END;
    END ForStat;

    PROCEDURE WithStat() : T.StmtList;
      VAR
        cvar, typ : ST.Symbol;
        origType : ST.Type;
        else, stmt : T.StmtList;
        withL, curWith, lastWith : T.WithList;
        ctrl, testtype : T.Design;
    BEGIN
      origType := NIL;
      withL := NIL;
      LOOP
        IF PU.token = OPS.ident THEN
          PU.qualident(cvar);
          ctrl := TB.NewDesign(cvar);
          PU.Match(OPS.colon);
          IF PU.token = OPS.ident THEN
            PU.qualident(typ);
            testtype := TB.NewDesign(typ);
            origType := cvar.type;
            cvar.type := typ.type;
          ELSE
            err(EL.IdentExpected);
          END;
        ELSE
          err(EL.IdentExpected);
        END;
        PU.Match(OPS.do);
        StatSeq(stmt);
        IF origType # NIL THEN
          cvar.type := origType;
          origType := NIL;
        END;

        curWith := TB.NewWithType(ctrl, testtype, stmt);
        IF withL = NIL THEN
          withL := curWith;
        ELSE
          lastWith.next := curWith;
        END;
        lastWith := curWith;

        IF PU.token = OPS.bar THEN
          OPS.Get(PU.token)
        ELSE
          EXIT;
        END;
      END;
      IF PU.token = OPS.else THEN
        OPS.Get(PU.token);
        StatSeq(else);
      ELSE
        else := T.NewHaltNode(TB.NewBoolConst(FALSE),
                              TB.NewIntConst(OPM.HaltWith));
      END;
      PU.Match(OPS.end);
      RETURN T.NewWithNode(withL, else);
    END WithStat;

    PROCEDURE  ExitStat() : T.StmtList;
    BEGIN
      IF LoopLevel = 0 THEN
        err(EL.MisplacedExit);
      END;
      RETURN TB.NewExit();
    END ExitStat;

    PROCEDURE  ReturnStat() : T.Return; (* this allows a type name to be
                                         * returned RETURN TypeName! error *)
      VAR
        ret : T.Return;
        x : T.Expr;
        sym : ST.Symbol;
        proc : ST.SymbolProc;
    BEGIN
      IF PU.token < OPS.semicolon THEN
        x := E.Expression();
      ELSE
        x := NIL;
      END;
      IF PU.level > 0 THEN
        sym := ST.ScopeOwner(ST.topScope);
        ASSERT(sym # NIL);
        proc := sym(ST.SymbolProc);
        IF x # NIL THEN
          x := E.AssignCompat(proc.type(ST.Procedure).result, x);
          ret := T.NewReturnNode(proc, x);
        ELSE
          IF proc.type(ST.Procedure).result # ST.notyp THEN
            err(EL.ResultTypeMismatch);
          END;
          ret := T.NewReturnNode(proc, NIL);
        END;
      ELSE
        (* return from module *)
        ret := T.NewReturnNode(NIL, NIL);
      END;
      RETURN ret;
    END ReturnStat;

  BEGIN
    lastStmt := TB.NewNullStmt();
    headStmt := NIL;
    LOOP
      PU.Sync(OPS.ident, 14);
      IF PU.token = OPS.ident THEN
        PU.qualident(id);
        lhs := TB.NewDesign(id);
        lhs := E.selector(lhs);
        IF (PU.token = OPS.becomes) OR (PU.token = OPS.eql) THEN
          curStmt := Assign(lhs);
        ELSIF (lhs.class = T.Ndsgn) & (lhs.subcl = T.Dstdproc) THEN
          curStmt := SP.StdProcCall(lhs, E.StdArgs());
        ELSE
          (* normal procedure or method call *)
          lhs := TB.SetupCall(lhs, fp, aparm);
          IF PU.token = OPS.lparen THEN
            OPS.Get(PU.token);
            aparm := E.ActualParameters(fp, aparm);
            PU.Match(OPS.rparen);
          ELSIF (fp # NIL) & ~(fp.kind IN {ST.par, ST.varpar}) THEN
            err(EL.TooFewAparm);
          END;
          curStmt := TB.NewProcCall(T.NewFuncCallNode(lhs, aparm));
          IF PU.level > 0 THEN
            owner := ST.ScopeOwner(ST.topScope);
            IF owner # NIL THEN
              EXCL(owner.flags, ST.leaf);
            END;
          END;
        END;
      ELSE
        CASE PU.token OF
        | OPS.if:
          OPS.Get(PU.token);
          curStmt := IfStat();

        | OPS.case:
          OPS.Get(PU.token);
          curStmt := CaseStat();

        | OPS.while:
          OPS.Get(PU.token);
          curStmt := WhileStat();

        | OPS.repeat:
          OPS.Get(PU.token);
          curStmt := RepeatStat();

        | OPS.loop:
          OPS.Get(PU.token);
          curStmt := LoopStat();

        | OPS.for:
          OPS.Get(PU.token);
          curStmt := ForStat();

        | OPS.with:
          OPS.Get(PU.token);
          curStmt := WithStat();

        | OPS.exit:
          OPS.Get(PU.token);
          curStmt := ExitStat();

        | OPS.return:
          OPS.Get(PU.token);
          curStmt := ReturnStat();
        ELSE
          EXIT;
        END;
      END;
      lastStmt := T.BindStmtList(lastStmt, curStmt);
      IF headStmt = NIL THEN
        headStmt := lastStmt;
      END;
      CASE PU.token OF
      | OPS.semicolon: OPS.Get(PU.token);
      | OPS.ident, OPS.case..OPS.return: err(EL.SemicolonExpected);
      ELSE
        EXIT;
      END;
    END;
    IF headStmt = NIL THEN
      stmt := lastStmt;
    ELSE
      stmt := headStmt;
    END;
  END StatSeq;

  PROCEDURE ProcDecl(VAR x : T.Enter);
    VAR
      fwd : ST.Symbol;
      proc : ST.SymbolProc;
      name : OPS.Name;
      mode, vis : SHORTINT;
      forward : BOOLEAN;
      sysflag : INTEGER;

    PROCEDURE GetCode;
      VAR
        ext: ST.ConstExt;
        n: INTEGER;
        c: LONGINT;
        cproc : ST.SymbolCodeProc;
    BEGIN
      cproc := proc(ST.SymbolCodeProc);
      ext := cproc.code;
      n := 0;
      LOOP
        IF PU.token = OPS.number THEN
          c := OPS.intval;
          INC(n);
          IF (c < 0) OR (c > 255) OR (n = ST.MaxCodeProcLen) THEN
            err(EL.TooManyAparm);
            c := 1;
            n := 1;
          END ;
          OPS.Get(PU.token); ext[n] := CHR(c)
        END ;

        CASE PU.token OF
        | OPS.comma: OPS.Get(PU.token);
        | OPS.number: err(EL.CommaExpected);
        ELSE
          ext[0] := CHR(n);
          EXIT;
        END;
      END ;
      INCL(cproc.flags, ST.body);
    END GetCode;

    PROCEDURE GetParams;
      VAR
        ptype : ST.Procedure;
        dummy : ST.SymbolScope;
    BEGIN
      proc.vis := vis;
      proc.kind := mode;
      ptype := proc.type(ST.Procedure);
      ptype.result := ST.notyp;
      proc.flags := proc.flags - ST.symSpecificFlags;
      IF PU.token = OPS.lparen THEN
        OPS.Get(PU.token);
        FormalParameters(ptype.parms, ptype.result);
      ELSE
        (* method procedure w/ no parameters -- 'self' gets set up *)
        ptype.parms := ST.FirstScopeVar(ST.topScope);
      END;
      IF fwd # NIL THEN
        E.CheckParamMatch(proc.type(ST.Procedure).parms,
                          fwd.type(ST.Procedure).parms, TRUE);
        IF proc.type(ST.Procedure).result # fwd.type(ST.Procedure).result THEN
          err(EL.ResultMismatch);
        END;
        (* we have a forward procedure, drop newly created scope and use
           existing one *)
        proc := fwd(ST.SymbolProc);
        dummy := ST.CloseScope();
        ST.ReopenScope(fwd(ST.SymbolProc).scope, fwd);
      END;
    END GetParams;

    PROCEDURE Body;
      VAR
        lProc : T.Enter;
        stmt: T.StmtList;
        c: LONGINT;
        decl : T.Declaration;
    BEGIN
      OPM.GetCurrentSourcePos(c);
      INCL(proc.flags, ST.body);
      PU.Match(OPS.semicolon);
      DeclarationSequence(lProc, stmt, decl);
      x := T.NewEnterNode(proc, lProc, stmt, decl, NIL, NIL);
      x.pos := c;
      IF PU.token = OPS.ident THEN
        IF OPS.name # proc.name^ THEN
          err(EL.IdentMismatch);
        END;
        OPS.Get(PU.token);
      ELSE
        err(EL.IdentExpected);
      END;
    END Body;

    PROCEDURE TProcDecl;
      VAR
        self, oldSelf, baseProc, ovrrideParms, baseParms: ST.Symbol;
        objTyp, recTyp, baseSelfType : ST.Type;
        selfName: OPS.Name;
        objMode: SHORTINT;

      PROCEDURE Receiver(VAR mode: SHORTINT;
                         VAR self: OPS.Name;
                         VAR typ, rec : ST.Type);
        VAR
          obj: ST.Symbol;
          tf, rf : SHORTINT;

      BEGIN
        typ := ST.undftyp;
        rec := NIL;
        PU.SetParmMode(mode);
        self := OPS.name;
        PU.Match(OPS.ident);
        PU.Match(OPS.colon);
        IF PU.token = OPS.ident THEN
          obj := ST.Find(OPS.name);
          OPS.Get(PU.token);
          IF obj = NIL THEN
            err(EL.UndeclaredIdent); (* no record *)
          ELSIF obj.kind # ST.type THEN
            err(EL.BadReceiver);
          ELSE
            typ := obj.type;
            rec := typ;
            tf := typ.form;
            IF tf = ST.pointer THEN
              rec := typ(ST.Pointer).to;
            END;
            rf := rec.form;

            IF ~((mode = ST.par) & (tf = ST.pointer) & (rf = ST.record) OR
                 (mode = ST.varpar) & (tf = ST.record)) THEN
              err(EL.ReceiverError);
              rec := NIL
            END;

            IF (rec # NIL) & (rec.mno # PU.level) THEN
              err(EL.BadReceiver);
              rec := NIL;
            END;
          END;
        ELSE
          err(EL.IdentExpected);
        END;
        PU.Match(OPS.rparen);
        IF rec = NIL THEN
          rec := ST.NewRecordType();
          ST.OpenRecordScope();
          rec(ST.Record).scope := ST.CloseScope();
        END;
      END Receiver;

    BEGIN
      OPS.Get(PU.token);
      mode := ST.tproc;
      IF PU.level > 0 THEN
        err(EL.MustBeGlobalProc);
      END;
      Receiver(objMode, selfName, objTyp, recTyp);
      IF PU.token = OPS.ident THEN
        name := OPS.name;
        PU.SetVis(vis);
        fwd := ST.FindField(name, recTyp(ST.Record));
        baseProc := ST.FindField(name, recTyp(ST.Record).ancestor);

        IF (baseProc # NIL) & (baseProc.kind # ST.tproc) THEN
          baseProc := NIL;
        END;
        IF fwd = baseProc THEN
          fwd := NIL;
        END;

        proc := ST.NewProcedureSym();
        INCL(proc.flags, ST.leaf);
        IF (fwd # NIL) & (fwd.mnolev # PU.level) THEN
          fwd := NIL;
        END;
        IF (fwd # NIL) & (fwd.kind = ST.tproc) & ~(ST.body IN fwd.flags) THEN
          (* there exists a corresponding forward declaration *)
          IF fwd.vis # vis THEN
            err(EL.ExportMismatch)
          END;
        ELSE
          IF fwd # NIL THEN
            err(EL.MultipleDefinition);
            fwd := NIL;
          END;
          ST.ReopenScope(recTyp(ST.Record).scope, NIL);
          ST.Insert(name, proc);
          recTyp(ST.Record).scope := ST.CloseScope();
        END ;

        INC(PU.level);
        ST.OpenProcedureScope(PU.level, proc);
        self := ST.NewBasicSym(objMode);
        self.type := objTyp;
        ST.Insert(selfName, self);
        GetParams;
        IF baseProc # NIL THEN
          (* override base procedure *)
          oldSelf := baseProc.type(ST.Procedure).parms;
          baseSelfType := oldSelf.type;
          IF (objMode # oldSelf.kind) OR
             ~ST.Extends(objTyp, baseSelfType) THEN
            err(EL.ParmMismatch);
          END ;
          baseParms := ST.FirstParm(baseProc.type(ST.Procedure));
          ovrrideParms := ST.FirstParm(proc.type(ST.Procedure));
          E.CheckParamMatch(ST.NextParm(ovrrideParms),
                            ST.NextParm(baseParms),
                            FALSE);
          IF proc.type(ST.Procedure).result #
             baseProc.type(ST.Procedure).result THEN
            err(EL.ResultMismatch)
          END;
          IF (baseProc.vis = ST.export) &
             (proc.vis = ST.internal) &
             (recTyp.sym # NIL) &
             (recTyp.sym.vis = ST.export) THEN
            err(EL.ExportOverride)
          END ;
          INCL(proc.flags, ST.redef);
        END;
        proc.type(ST.Procedure).parms := ST.FirstScopeVar(ST.topScope);
        proc.type(ST.Procedure).sysflag := sysflag;
        IF ~forward THEN
          Body;
        END;
        DEC(PU.level);
        proc.scope := ST.CloseScope();
      ELSE
        err(EL.IdentExpected);
      END;
    END TProcDecl;

  BEGIN
    proc := NIL;
    forward := FALSE;
    x := NIL;
    mode := ST.lproc;
    sysflag := 0;

    IF (PU.token # OPS.ident) & (PU.token # OPS.lparen) THEN
      (* tproc or lexical mark *)
      CASE PU.token OF
      | OPS.times: (* used as proc variable, no effect *)
      | OPS.arrow: forward := TRUE;
      | OPS.minus: mode := ST.cproc; (* code proc *)
      | OPS.plus: mode := ST.iproc; (* interrupt proc *)
      | OPS.lbrak: CheckSysFlag(sysflag, 0);
      ELSE
        err(EL.IdentExpected);
      END;
      IF (mode IN {ST.cproc, ST.iproc}) & ~ST.SYSimported THEN
        err(EL.SystemNotImported);
      END;
      IF (PU.token <= MAX(SET)) & (PU.token IN {OPS.times, OPS.arrow,
                                                OPS.minus, OPS.plus}) THEN
        OPS.Get(PU.token); (* CheckSysFlag positions at correct token *)
      END;
    END;

    IF PU.token = OPS.lparen THEN
      TProcDecl;
    ELSIF PU.token = OPS.ident THEN
      fwd := ST.Find(OPS.name);
      name := OPS.name;
      PU.SetVis(vis);
      IF (vis IN {ST.export, ST.exportR}) & (mode = ST.lproc) THEN
        mode := ST.xproc;
      END;

      IF (fwd # NIL) & (fwd.mnolev # PU.level) THEN
        fwd := NIL;
      END;
      IF (fwd # NIL) &
         (fwd.kind IN {ST.lproc, ST.xproc}) &
         ~(ST.body IN fwd.flags) THEN
        (* there exists a corresponding forward declaration;
         * don't include in PU.symtab *)
        proc := ST.NewProcedureSym();
        INCL(proc.flags, ST.leaf);
        IF fwd.vis # vis THEN
          err(EL.ExportMismatch);
        END;
      ELSE
        IF mode IN {ST.lproc, ST.xproc, ST.iproc} THEN
          proc := ST.NewProcedureSym();
        ELSE
          proc := ST.NewCodeProcSym();
        END;
        IF fwd # NIL THEN
          err(EL.MultipleDefinition);
          fwd := NIL;
        END;
        ST.Insert(name, proc);
      END;
      IF (mode # ST.lproc) & (PU.level > 0) THEN
        err(EL.MustBeGlobalProc); (* incorrect mark *)
      END;

      INC(PU.level);
      ST.OpenProcedureScope(PU.level, proc);
      ST.LinkSymbol(proc, NIL);
      GetParams;

      proc.type(ST.Procedure).parms := ST.FirstScopeVar(ST.topScope);
      IF mode = ST.cproc THEN
        GetCode;
      ELSIF ~forward THEN
        Body;
      END;
      DEC(PU.level);
      proc.scope := ST.CloseScope();
      proc.type(ST.Procedure).sysflag := sysflag;
    ELSE
      err(EL.IdentExpected);
    END;
  END ProcDecl;

  PROCEDURE DeclarationSequence(VAR nestedProcs : T.Enter;
                                VAR body : T.StmtList;
                                VAR decl : T.Declaration);
    VAR
      firstSym, symbol : ST.Symbol;
      expr : T.Expr;
      typ : ST.Type;
      proc: T.Enter;
      symconst : ST.SymbolConst;
      i : INTEGER;
      nested : T.StmtList;
      DeclList, DeclListTail : T.Declaration;

    PROCEDURE NewDeclaration(sym : ST.Symbol);
      VAR
        n : T.Declaration;
        dn : T.Node;
    BEGIN
      n := T.NewDeclarationNode(sym, PU.IsForward(sym.type));
      IF DeclList = NIL THEN
        DeclList := n;
      END;
      dn := T.BindNodes(DeclListTail, n);
      DeclListTail := dn(T.Declaration);
    END NewDeclaration;

  BEGIN
    DeclList := NIL;
    DeclListTail := NIL;
    PU.InitForwardType;
    LOOP
      IF PU.token = OPS.type THEN
        OPS.Get(PU.token);
        WHILE PU.token = OPS.ident DO
          symbol := ST.NewBasicSym(ST.type);
          ST.Insert(OPS.name, symbol);
          PU.SetVis(symbol.vis);
          CASE PU.token OF
          | OPS.eql, OPS.becomes, OPS.colon:
             IF PU.token # OPS.eql THEN
               err(EL.EqlExpected);
             END;
             OPS.Get(PU.token);
             symbol.type := TypeDecl(symbol.type);
          ELSE
            err(EL.EqlExpected);
          END;

          NewDeclaration(symbol);
          IF symbol.type.sym = NIL THEN
            symbol.type.sym := symbol;
          END;
          IF symbol.type.form IN {ST.record, ST.array, ST.dynarr} THEN
            PU.FixupForwardType(symbol);
          END;
          PU.Match(OPS.semicolon);
        END;
      ELSIF PU.token = OPS.const THEN
        OPS.Get(PU.token);
        WHILE PU.token = OPS.ident DO
          symconst := ST.NewConstSym(ST.undftyp);
          ST.Insert(OPS.name, symconst);
          PU.SetVis(symconst.vis);
          CASE PU.token OF
          | OPS.eql, OPS.becomes, OPS.colon:
            IF PU.token # OPS.eql THEN
              err(EL.EqlExpected);
            END;
            OPS.Get(PU.token);
            expr := E.ConstExpression();
          ELSE
            err(EL.EqlExpected);
            expr := TB.NewIntConst(1);
          END;
          NewDeclaration(symconst);
          symconst.val := expr.val;
          symconst.type := expr.type;
          PU.Match(OPS.semicolon);
        END;
      ELSIF PU.token = OPS.var THEN
        OPS.Get(PU.token);
        WHILE PU.token = OPS.ident DO
          firstSym := NIL;
          LOOP
            IF PU.token = OPS.ident THEN
              symbol := ST.NewBasicSym(ST.var);
              ST.Insert(OPS.name, symbol);
              PU.SetVis(symbol.vis);
              IF symbol.vis = ST.internal THEN
                INCL(symbol.flags, ST.leaf);
              END;
              IF firstSym = NIL THEN
                firstSym := symbol;
              END;
              NewDeclaration(symbol);
            ELSE
              err(EL.IdentExpected);
            END;

            CASE PU.token OF
            | OPS.comma: OPS.Get(PU.token);
            | OPS.ident: err(EL.CommaExpected);
            ELSE
              EXIT;
            END;
          END;
          PU.Match(OPS.colon);
          PU.DistributeType(firstSym, symbol, Type(ST.notyp), TRUE);
          INCL(symbol.type.flags, ST.pvused);
          PU.Match(OPS.semicolon);
        END;
      ELSE
        EXIT; (* ~(token IN {var, const, type}) *)
      END;
    END;
    PU.CheckForwardTypes;

    nestedProcs := NIL;
    WHILE PU.token = OPS.procedure DO
      OPS.Get(PU.token);
      ProcDecl(proc);
      IF proc # NIL THEN
        nested := T.BindStmtList(proc, nestedProcs);
        nestedProcs := proc(T.Enter);
      END;
      PU.Match(OPS.semicolon);
    END;

    IF PU.token = OPS.begin THEN
      OPS.Get(PU.token);
      StatSeq(body);
    ELSE
      body := TB.NewNullStmt();
    END;
    decl := DeclList;
    PU.Match(OPS.end);
  END DeclarationSequence;

  PROCEDURE Module*(VAR tree : T.Node);
    VAR
      localproc : T.Enter;
      body : T.StmtList;
      enter : T.Enter;
      modname, name, alias : OPS.Name;
      done : BOOLEAN;
      import : T.Import;
      impSym : ST.Symbol;
      decl : T.Declaration;

      PROCEDURE MakeModuleSymbol();
        VAR
          m : ST.SymbolProc;
      BEGIN
        m := ST.NewProcedureSym();
        m.kind := ST.xproc;
        m.vis := ST.export;
        INCL(m.flags, ST.modinit);
        m.scope := ST.topScope;
        ST.Insert(modname, m);
        ST.SetModuleSymbol(ST.topScope(ST.ModuleScope), m);
      END MakeModuleSymbol;

  BEGIN
    OPS.Get(PU.token);
    IF PU.token = OPS.module THEN
      OPS.Get(PU.token);
      IF PU.token = OPS.ident THEN
        COPY(OPS.name, modname);
        ST.SetModuleName(modname);
        OPS.Get(PU.token);
        PU.Match(OPS.semicolon);
        IF PU.token = OPS.import THEN
          OPS.Get(PU.token);
          LOOP
            IF PU.token = OPS.ident THEN
              COPY(OPS.name, alias);
              COPY(alias, name);
              OPS.Get(PU.token);
              IF PU.token = OPS.becomes THEN
                OPS.Get(PU.token);
                IF PU.token = OPS.ident THEN
                  COPY(OPS.name, name);
                  OPS.Get(PU.token);
                ELSE
                  err(EL.IdentExpected);
                END;
              END;
              IE.Import(alias, name, done);
              IF ~done THEN
                err(EL.ImportFailed);
              ELSE
                impSym :=  ST.Find(alias);
                IF impSym.name^ # "SYSTEM" THEN
                  (* init procedure from imported module needs to be used
                     instead of the scope symbol so that CGH.Enter can handle
                     fixups to externals properly *)
                  (* aliased import init codes still have original name *)
                  impSym := ST.FindImport(impSym(ST.SymbolProc), name);
                  import := T.NewImportNode(impSym);
                ELSE
                  import := T.NewImportNode(impSym);
                  INCL(import.flags, T.noinit); (* SYSTEM has no init code *)
                END;
                import.next := ImportList;
                ImportList := import;
                IF ImportListTail = NIL THEN
                  ImportListTail := import;
                END;
              END;
            ELSE
              err(EL.IdentExpected);
            END;
            IF PU.token = OPS.comma THEN
              OPS.Get(PU.token);
            ELSIF PU.token = OPS.ident THEN
              err(EL.CommaExpected);
            ELSE
              EXIT;
            END;
          END;
          PU.Match(OPS.semicolon);
        END;
      ELSE
        err(EL.IdentExpected);
      END;

      body := NIL;
      IF OPM.noerr THEN
        MakeModuleSymbol();
        DeclarationSequence(localproc, body, decl);
        tree := T.NewEnterNode(ST.topScope, localproc, body, decl,
                               NIL, ImportList);
        INCL(tree.flags, T.main);

        IF PU.token = OPS.ident THEN
          IF OPS.name # modname THEN
            err(EL.IdentMismatch);
          END;
          OPS.Get(PU.token);
        ELSE
          err(EL.IdentExpected);
        END;
        IF PU.token # OPS.period THEN
          err(EL.PeriodExpected)
        END;
      END;
    ELSE
      err(EL.ModuleExpected);
    END;
  END Module;

  PROCEDURE NILGlobalPointers;
  BEGIN
    ImportList := NIL;
    ImportListTail := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin*;
  BEGIN
    LoopLevel := 0;
    NILGlobalPointers;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN
    NILGlobalPointers;
  END ModuleEnd;

BEGIN
END SKLSP.
