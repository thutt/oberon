MODULE O3Parser; (* Oberon parser *)
  IMPORT
    Config := O3Config, 
    Scanner := O3Scanner, 
    Symtab := O3Symtab, 
    AST := O3TreeNode, 
    ASTH := O3TreeHelper, 
    Semantics := O3Semantics,
    Expr:= O3Expression, 
    ConstExpr := O3ConstExpression,
    StdProc := O3StdProc,
    IE:= O3SymFile,
    E:=O3Errors;

  TYPE
    ForwardDesc =  RECORD
      typ : Symtab.Pointer;  (* declaration of the forward type *)
      name : Scanner.Name;  (* name which is referenced by the forward *)
    END;
    ForwardTypes = POINTER TO ARRAY OF ForwardDesc;

  VAR
    ImportList, ImportListTail : AST.Import;
    LoopLevel : INTEGER;
    FwdPtr: ForwardTypes;

  PROCEDURE ^ DeclarationSequence(VAR nestedProcs : AST.Enter; VAR body : AST.StmtList; VAR decl : AST.Declaration);
  PROCEDURE ^ Type(banned: Symtab.Type) : Symtab.Type;

  PROCEDURE ConstExpression(VAR value, expr : AST.Expr);
    VAR  cv : BOOLEAN;
  BEGIN expr := Expr.Expression(); value := ConstExpr.FoldExpression(expr, cv);
    IF ~cv THEN Config.Error(E.NotAConstant); END;
   END ConstExpression;

  PROCEDURE ExpandForwardTypes;
    CONST BlockSize = 15;
    VAR x : ForwardTypes; len, i, j : LONGINT;
  BEGIN
    IF FwdPtr = NIL THEN NEW(FwdPtr, BlockSize);
    ELSE len := LEN(FwdPtr^); j := len; INC(len, BlockSize); NEW(x, len);
      i := 0; WHILE i < j DO x[i] := FwdPtr[i]; INC(i); END;
      FwdPtr := x;
    END;
  END ExpandForwardTypes;
  
  PROCEDURE InitForwardType;
    VAR i : INTEGER;
  BEGIN ExpandForwardTypes;
    i := 0; WHILE i < LEN(FwdPtr^) DO FwdPtr[i].typ := NIL; FwdPtr[i].name[0] := 0X; INC(i); END;
  END InitForwardType;

  PROCEDURE NewForwardType(typ : Symtab.Pointer; name : Scanner.Name);
    VAR i, j : LONGINT;
  BEGIN j := LEN(FwdPtr^); 
    (* search for an empty spot *)
    i := 0; WHILE (i < j) & (FwdPtr[i].typ # NIL) DO INC(i); END;
    IF i >= j THEN (* empty spot not found; expand array *) ExpandForwardTypes; i := j;  END;
    (* inv: i = index to first available element *) 
    FwdPtr[i].typ := typ; COPY(name, FwdPtr[i].name); typ.to := Symtab.undftyp;
  END NewForwardType;

  PROCEDURE FixupForwardType(symbol : Symtab.Symbol);
    VAR i : LONGINT; typ : Symtab.Pointer;
  BEGIN i := 0;
    WHILE i < LEN(FwdPtr^) DO
      IF FwdPtr[i].name = symbol.name^ THEN
        typ := FwdPtr[i].typ; typ.to := symbol.type;
        FwdPtr[i].name[0] := 0X; FwdPtr[i].typ := NIL;
      END;
      INC(i);
    END;
  END FixupForwardType;

  PROCEDURE CheckForwardTypes;
    VAR i : INTEGER;
  BEGIN (* check forward pointer declarations for completion *)
    i := 0;
    WHILE i < LEN(FwdPtr^) DO
      IF FwdPtr[i].typ # NIL THEN Config.Error(E.UnsatisfiedForwardType);
      ELSE FwdPtr[i].typ := NIL; (* GC *)
      END;
      INC(i);
    END;
  END CheckForwardTypes;

  PROCEDURE IsForward(typ : Symtab.Type) : BOOLEAN;
    VAR i : LONGINT;
  BEGIN
    IF typ.form = Symtab.pointer THEN
      i := 0;
      WHILE i < LEN(FwdPtr^) DO
        IF FwdPtr[i].typ = typ THEN RETURN TRUE; END;
        INC(i);
      END;
    END;
    RETURN FALSE;
  END IsForward;

  PROCEDURE InsertSymbol(name : ARRAY OF CHAR; sym : Symtab.Symbol);
    VAR duplicate : BOOLEAN;
  BEGIN Symtab.Insert(name, sym, duplicate); 
    IF duplicate THEN Config.Error(E.MultipleDefinition); END;
  END InsertSymbol;
  
  PROCEDURE SetVis(VAR vis : SHORTINT);
    VAR tok : SHORTINT;
  BEGIN
    Scanner.Get(tok);
    IF (tok <= MAX(SET)) & (tok IN {Scanner.times, Scanner.minus}) THEN
      IF Semantics.level > 0 THEN Config.Error(E.IllegalMark); END;
      IF tok = Scanner.times THEN vis := Symtab.export;
      ELSE vis := Symtab.exportR;
      END;
      Scanner.Get(tok);
    ELSE vis := Symtab.internal;
    END;
  END SetVis;

  PROCEDURE SetParmMode(VAR mode : SHORTINT);
    VAR tok : SHORTINT;
  BEGIN IF Scanner.token = Scanner.var THEN Scanner.Get(tok); mode := Symtab.varpar ELSE mode := Symtab.par END;
  END SetParmMode;
    
  PROCEDURE DistributeType(list, stop : Symtab.Symbol; type : Symtab.Type; noDynArr : BOOLEAN);
  BEGIN
    IF noDynArr & (type.form IN {Symtab.dynarr, Symtab.openarr}) THEN 
      Config.Error(E.IllegalOpenArray); type := Symtab.undftyp; 
    END;
    list.type := type;
    LOOP list.type := type;
      IF list = stop THEN EXIT; END;
      list := Symtab.NextSymbol(list);
    END;
  END DistributeType;
  
  PROCEDURE CheckSysFlag(VAR sysflag: INTEGER);
    VAR x, expr: AST.Expr; sf: LONGINT;
  BEGIN sysflag := 0;
    IF Scanner.token = Scanner.lbrak THEN sf := sysflag; (* use sysflag to ensure same default value *)
      Scanner.Get(Scanner.token); ConstExpression(x, expr);
      IF x.type.form IN Symtab.IntSet THEN sf := x.val.i0;
      ELSE Config.Error(E.NotInteger);
      END ;
      sysflag := SHORT(sf); Scanner.Match(Scanner.rbrak);
      IF ~Symtab.SYSimported THEN Config.Error(E.SystemNotImported); END;
    END;
  END CheckSysFlag;

  PROCEDURE FormalParameters(VAR firstPar : Symtab.Symbol; VAR resTyp: Symtab.Type);
    VAR mode: SHORTINT; par, first, res : Symtab.Symbol; parmType, pt : Symtab.Type;
  BEGIN firstPar := Symtab.FirstScopeVar(Symtab.topScope);
    IF (Scanner.token = Scanner.ident) OR (Scanner.token = Scanner.var) THEN
      LOOP first := NIL; SetParmMode(mode);
        LOOP
          IF Scanner.token = Scanner.ident THEN
            par := Symtab.NewBasicSym(mode); InsertSymbol(Scanner.name, par); Scanner.Get(Scanner.token);
            IF first = NIL THEN first := par; END;
            IF firstPar = NIL THEN firstPar := par; END;
          ELSE Config.Error(E.IdentExpected);
          END;

          CASE Scanner.token OF
          |  Scanner.comma: Scanner.Get(Scanner.token);
          |  Scanner.ident: Config.Error(E.CommaExpected);
          |  Scanner.var: Config.Error(E.CommaExpected); Scanner.Get(Scanner.token);
          ELSE EXIT;
          END;
        END ;
        Scanner.Match(Scanner.colon);
        parmType := Type(Symtab.notyp);
        IF parmType.form = Symtab.dynarr THEN pt := parmType; 
          WHILE pt.form = Symtab.dynarr DO 
            (* Since size and offset of heap -vs- parameter open arrays are calculated differently, 
              formal parameters are 'openarr'; 'dynarr' is used for heap arrays *)
            pt.form := Symtab.openarr; 
            pt := pt(Symtab.Array).of; 
          END;
        END;
        IF first # NIL THEN (* only if no parse error occurred *)
          DistributeType(first, par, parmType, FALSE);
          IF mode = Symtab.par THEN INCL(par.type.flags, Symtab.pvused); END; (* pbused included when parameter type is parsed *)
        END;

        CASE Scanner.token OF
        |  Scanner.semicolon: Scanner.Get(Scanner.token);
        |  Scanner.ident: Config.Error(E.SemicolonExpected);
        ELSE EXIT;
        END;
      END;
    END;

    Scanner.Match(Scanner.rparen); resTyp := Symtab.notyp;
    IF Scanner.token = Scanner.colon THEN (* result type *) Scanner.Get(Scanner.token);
      IF Scanner.token = Scanner.ident THEN Expr.qualident(res);
        IF res.kind = Symtab.type THEN
          IF res.type.form IN Symtab.ReturnSet THEN resTyp := res.type;
          ELSE Config.Error(E.IllegalResult);
          END;
        ELSE Config.Error(E.NotAType);
        END;
      ELSE Config.Error(E.IdentExpected);
      END;
    END
  END FormalParameters;
  
  PROCEDURE TypeDecl(banned: Symtab.Type) : Symtab.Type;
    VAR type : Symtab.Type;

    PROCEDURE RecordType(banned: Symtab.Type) : Symtab.Type;
      VAR
        type : Symtab.Record; base : Symtab.Symbol; sysflag: INTEGER;
        fld, first : Symtab.Symbol;
    BEGIN
      type := Symtab.NewRecordType(); CheckSysFlag(sysflag);
      IF Scanner.token = Scanner.lparen THEN
        Scanner.Get(Scanner.token); (*record extension*)
        IF Scanner.token = Scanner.ident THEN
          Expr.qualident(base);
          IF (base.kind = Symtab.type) & (base.type.form = Symtab.record) THEN
            IF base.type # banned THEN INCL(base.type.flags, Symtab.pvused); (* private part implicitly needed by extension *)
              type.ancestor := base.type(Symtab.Record);
              type.extlev := base.type(Symtab.Record).extlev + 1;
              type.sysflag := base.type.sysflag; (* should not be allowed to override base sysflag *)
            ELSE Config.Error(E.RecursiveType);
            END;
          ELSE Config.Error(E.NotAType);
          END;
        ELSE Config.Error(E.IdentExpected)
        END;
        Scanner.Match(Scanner.rparen)
      END;

      type.sysflag := sysflag; 
      Symtab.OpenScopeRecord(Symtab.ScopeOwner(Symtab.topScope));
      LOOP
        first := NIL;
        IF Scanner.token = Scanner.ident THEN
          LOOP
            IF Scanner.token = Scanner.ident THEN
              fld := Symtab.FindField(Scanner.name, type.ancestor);
              IF fld # NIL THEN Config.Error(E.MultipleDefinition) END;
              fld := Symtab.NewBasicSym(Symtab.field); InsertSymbol(Scanner.name, fld); SetVis(fld.vis);
              IF first = NIL THEN first := fld; END;
            ELSE Config.Error(E.IdentExpected)
            END;

            CASE Scanner.token OF
            |  Scanner.comma: Scanner.Get(Scanner.token);
            |  Scanner.ident: Config.Error(E.CommaExpected);
            ELSE EXIT;
            END;
          END;
          Scanner.Match(Scanner.colon); DistributeType(first, fld, Type(banned), TRUE);
          INCL(fld.type.flags, Symtab.pvused);
        END;

        CASE Scanner.token OF
        |  Scanner.semicolon: Scanner.Get(Scanner.token);
        |  Scanner.ident: Config.Error(E.SemicolonExpected);
        ELSE EXIT;
        END;
      END ;
      type.scope := Symtab.CloseScope();
      RETURN type;
    END RecordType;

    PROCEDURE ArrayType(banned: Symtab.Type) : Symtab.Type;
      VAR x, expr: AST.Expr; n: LONGINT; sysflag: INTEGER; atyp : Symtab.Array;
    BEGIN
      CheckSysFlag(sysflag);

      IF Scanner.token = Scanner.of THEN  (*dynamic array; changed for formal param into 'openarr' *)
        atyp := Symtab.NewArrayType(Symtab.dynarr);
        Scanner.Get(Scanner.token); atyp.of := Type(banned); INCL(atyp.of.flags, Symtab.pvused);
        (* XXX document the fact that each dimension of a dynamic array shares the same td. *)
        IF atyp.of.form = Symtab.dynarr THEN atyp.n := atyp.of(Symtab.Array).n + 1; Symtab.SetTD(atyp, Symtab.GetTD(Symtab.topScope, atyp.of));
        ELSE atyp.n := 0
        END
      ELSE (* regular array *)
        atyp := Symtab.NewArrayType(Symtab.array); ConstExpression(x, expr);
        IF (x.type.form IN Symtab.IntSet) THEN n := x.val.i0;
          IF (n <= 0) THEN Config.Error(E.IllegalValue); n := 1 END; (* backend can make limitations of index value *)
        ELSE Config.Error(E.NotInteger); n := 1
        END ;
        atyp.n := n;

        IF Scanner.token = Scanner.of THEN Scanner.Get(Scanner.token); atyp.of := Type(banned); INCL(atyp.of.flags, Symtab.pvused);
        ELSIF Scanner.token = Scanner.comma THEN
          Scanner.Get(Scanner.token);
          IF Scanner.token # Scanner.of THEN atyp.of := ArrayType(banned) END
        ELSE Config.Error(E.BadArrayDecl);
        END;
        IF atyp.of.form = Symtab.dynarr THEN Config.Error(E.IllegalOpenArray); atyp.of:= Symtab.undftyp; END
      END;
      atyp.sysflag := sysflag;
      RETURN atyp;
    END ArrayType;

    PROCEDURE PointerType() : Symtab.Type;
      VAR id: Symtab.Symbol; ptyp : Symtab.Pointer;
    BEGIN
      ptyp := Symtab.NewPointerType(); CheckSysFlag(ptyp.sysflag); Scanner.Match(Scanner.to);
      IF Scanner.token = Scanner.ident THEN id := Symtab.Find(Scanner.name);
        IF id = NIL THEN NewForwardType(ptyp, Scanner.name); Scanner.Get(Scanner.token);
        ELSE Expr.qualident(id);
          IF id.kind = Symtab.type THEN
            IF id.type.form IN Symtab.AggregateSet THEN ptyp.to := id.type;
            ELSE ptyp.to := Symtab.undftyp; Config.Error(E.IllegalPointsTo);
            END;
          ELSE Config.Error(E.NotAType); ptyp.to := Symtab.undftyp;
          END;
        END;
      ELSE (* array, dynarr or record *)
        ptyp.to := Type(Symtab.notyp);
        IF ~(ptyp.to.form IN Symtab.AggregateSet) THEN
          Config.Error(E.IllegalPointsTo); ptyp.to := Symtab.undftyp;
        END
      END;
      RETURN ptyp;
    END PointerType;

    PROCEDURE ProcedureType() : Symtab.Type;
      VAR ptype : Symtab.Procedure; dummy : Symtab.SymbolScope;
    BEGIN
      Scanner.Get(Scanner.token); ptype := Symtab.NewProcedureType(); CheckSysFlag(ptype.sysflag);
      IF Scanner.token = Scanner.lparen THEN
        Scanner.Get(Scanner.token); Symtab.OpenScopeProcedure(Semantics.level, NIL);
        FormalParameters(ptype.parms, ptype.result); dummy := Symtab.CloseScope();
      ELSE ptype.result := Symtab.notyp; ptype.parms := NIL;
      END;
      RETURN ptype;
    END ProcedureType;

    PROCEDURE TypeId() : Symtab.Type;
      VAR id: Symtab.Symbol; t : Symtab.Type;
    BEGIN t := Symtab.undftyp; Expr.qualident(id);
      IF id.kind = Symtab.type THEN
        IF id.type # banned THEN t := id.type ELSE Config.Error(E.RecursiveType); END;
      ELSE Config.Error(E.NotAType);
      END;
      RETURN t;
    END TypeId;

  BEGIN type := Symtab.undftyp;
    Scanner.Sync(Scanner.lparen, 12);
    CASE Scanner.token OF
    |  Scanner.ident: type := TypeId();
    |  Scanner.array: Scanner.Get(Scanner.token); type := ArrayType(banned);
    |  Scanner.pointer: Scanner.Get(Scanner.token); type := PointerType();
    |  Scanner.record: Scanner.Get(Scanner.token); type := RecordType(banned); Scanner.Match(Scanner.end);
    |  Scanner.procedure: type := ProcedureType();
    ELSE Config.Error(E.BadTypeStart);
    END;

    LOOP
      CASE Scanner.token OF
      |  Scanner.semicolon..Scanner.else, Scanner.rparen, Scanner.eof: EXIT;
      ELSE
        IF Scanner.token = Scanner.ident THEN EXIT END;
        Config.Error(E.BadDeclEnd); Scanner.Get(Scanner.token)
      END;
    END;
    RETURN type;
  END TypeDecl;
  
  PROCEDURE Type(banned: Symtab.Type) : Symtab.Type;
    VAR typ : Symtab.Type;
  BEGIN typ := TypeDecl(banned);
    (* do not allow POINTER TO undef in declarations *)
    IF (typ.form = Symtab.pointer) & (typ(Symtab.Pointer).to = Symtab.undftyp) & ~IsForward(typ) THEN Config.Error(E.UndeclaredIdent) END;
    RETURN typ;
  END Type;

  PROCEDURE StatSeq(VAR stmt : AST.StmtList);
    VAR
      lhs : AST.Design;
      rhs : AST.Expr;
      headStmt, lastStmt, curStmt : AST.StmtList;
      id, fp : Symtab.Symbol; (* formal parm list *)
      aparm : AST.Arg;
      owner : Symtab.Symbol;

    PROCEDURE CheckBool(x: AST.Expr) : AST.Expr;
    BEGIN
      IF (x.class = AST.Ndsgn) & ~(x.subcl IN AST.RValueSet) THEN
        Config.Error(E.RvalueRequired); x := ASTH.NewBoolConst(FALSE)
      END;
      IF x.type # Symtab.booltyp THEN Config.Error(E.BooleanRequired); x := ASTH.NewBoolConst(FALSE) END;
      RETURN x;
    END CheckBool;

    PROCEDURE Assign(lhs : AST.Design) : AST.Assign;
      VAR rhs : AST.Expr;
    BEGIN
      IF Scanner.token = Scanner.eql THEN Config.Error(E.BecomesExpected); END;
      Scanner.Get(Scanner.token); rhs := Expr.Expression();
      IF (lhs.class = AST.Ndsgn) & (lhs.subcl IN AST.RValueSet) THEN
        IF AST.readonly IN lhs.flags THEN Config.Error(E.ReadOnlyVariable); END;
        rhs := Semantics.AssignCompat(lhs.type, rhs);
      ELSE Config.Error(E.NotAVariable);
      END;
      RETURN ASTH.NewAssign(lhs, rhs, lhs.type);
    END Assign;

    PROCEDURE IfStat() : AST.StmtList;
      VAR test : AST.Expr; stmt, else : AST.StmtList; if, elsif, tif : AST.IfBody;
    BEGIN
      test := CheckBool(Expr.Expression()); Scanner.Match(Scanner.then); StatSeq(stmt);
      if := AST.NewIfBodyNode(test, stmt); tif := if;
      WHILE Scanner.token = Scanner.elsif DO
        Scanner.Get(Scanner.token);
        test := CheckBool(Expr.Expression()); Scanner.Match(Scanner.then);
        StatSeq(stmt); elsif := AST.NewIfBodyNode(test, stmt);
        AST.BindIfElsif(tif, elsif); tif := elsif;
      END;
      IF Scanner.token = Scanner.else THEN Scanner.Get(Scanner.token); StatSeq(else);
      ELSE else := ASTH.NewNullStmt();
      END;
      Scanner.Match(Scanner.end);
      RETURN AST.NewIfElseNode(if, else);
    END IfStat;

    PROCEDURE CaseStat() : AST.StmtList;
      CONST
        MaxCases = 128;    (* maximal number of cases in a case statement: *)
        MaxCaseRange = 512;    (* max range of a case (hi - lo ~ jump table size): *)
        CaseRange = 512;

      TYPE
        CaseEntry = RECORD low, high: LONGINT; END;
        CaseTable = POINTER TO ARRAY OF CaseEntry;

      VAR
        stmt, else : AST.StmtList;
        expr : AST.Expr;
        casetab : CaseTable;
        cases, caseTail : AST.SingleCase;
        label : AST.CaseBounds;
        range : Symtab.Const;
        low, high : LONGINT;
        n : INTEGER;

      PROCEDURE EnterCase(VAR tab : CaseTable; i : INTEGER; loval, hival : LONGINT);
        CONST TableDelta = 128;
        VAR t : CaseTable; j : INTEGER; newlen : LONGINT; entry : CaseEntry;
      BEGIN 
        (* allocate or reallocate table? *)
        IF tab = NIL THEN NEW(tab, TableDelta);
        ELSIF i >= LEN(tab^) THEN newlen := LEN(tab^) + TableDelta; NEW(t, newlen); 
          j := 0; WHILE j < LEN(tab^) DO t[j] := tab[j]; INC(j); END; tab := t;
        END;
        
        (*enter label range into ordered table*)
        LOOP
          IF i = 0 THEN EXIT; END;
          IF tab[i - 1].low <= hival THEN
            IF tab[i - 1].high >= loval THEN Config.Error(E.DuplicateLabel); END;
            EXIT;
          END;
          entry := tab[i - 1];
          tab[i] := entry;
          DEC(i);
        END ;
        tab[i].low := loval; tab[i].high := hival; INC(n)
      END EnterCase;
      
      PROCEDURE CaseLabelList(LabelForm : INTEGER; VAR n : INTEGER; VAR tab : CaseTable) : AST.CaseBounds;
        VAR
          head : AST.CaseBounds;
          lo, hi, expr : AST.Expr;
          loval, hival : LONGINT;
          i : INTEGER;
          hf, f : SHORTINT;

      BEGIN head := NIL;
        LOOP
          ConstExpression(lo, expr); f := lo.type.form;
          IF f IN Symtab.IntSet + {Symtab.char} THEN loval := lo.val.i0;
          ELSE Config.Error(E.IllegalLabelType); loval := 1;
          END;

          IF f IN Symtab.IntSet THEN
            IF LabelForm < f THEN Config.Error(E.WrongLabelType); END;
          ELSIF LabelForm # f THEN Config.Error(E.WrongLabelType);
          END;

          IF Scanner.token = Scanner.upto THEN Scanner.Get(Scanner.token);
            ConstExpression(hi, expr); hival := hi.val.i0; hf := hi.type.form;
            IF (hf # f) & ~((f IN Symtab.IntSet) & (hf IN Symtab.IntSet)) THEN Config.Error(E.WrongLabelType); END;
            IF hival < loval THEN Config.Error(E.IllegalValue); hival := loval; END;
          ELSE hival := loval;
          END;
          lo.val.i1 := hival;
          EnterCase(casetab, n, loval, hival);
          head := AST.BindCaseBounds(head, AST.NewCaseBoundsNode(lo.val));

          CASE Scanner.token OF
          |  Scanner.comma: Scanner.Get(Scanner.token);
          | Scanner.number, Scanner.ident: Config.Error(E.CommaExpected);
          ELSE EXIT;
          END;
        END;
        RETURN head;
      END CaseLabelList;

    BEGIN
      n := 0; casetab := NIL; cases := NIL; caseTail := NIL; expr := Expr.Expression(); Scanner.Match(Scanner.of);
      IF ~(expr.type.form IN {Symtab.char, Symtab.sint, Symtab.int, Symtab.lint}) THEN
        Config.Error(E.InvalidCaseType); expr := ASTH.NewIntConst(0);
      END;
      
      LOOP
        IF (Scanner.token = Scanner.ident)  (* things which can start an expression *)
	OR (Scanner.token = Scanner.number) 
	OR (Scanner.token = Scanner.plus)
	OR (Scanner.token = Scanner.minus)
	OR (Scanner.token = Scanner.lparen) THEN
          label := CaseLabelList(expr.type.form, n, casetab);
          Scanner.Match(Scanner.colon); StatSeq(stmt);
          caseTail := AST.BindSingleCase(caseTail, AST.NewSingleCaseNode(label, stmt));
          IF cases = NIL THEN cases := caseTail; END;
        END;
        IF Scanner.token = Scanner.bar THEN Scanner.Get(Scanner.token);
        ELSE EXIT;
        END;
      END;

      IF casetab # NIL THEN low := casetab[0].low; high := casetab[n - 1].high;
      ELSE low := 1; high := 0;
      END;

      IF Scanner.token = Scanner.else THEN Scanner.Get(Scanner.token); StatSeq(else)
      ELSE else := AST.NewHaltNode(ASTH.NewBoolConst(FALSE), ASTH.NewIntConst(Config.HaltCase));
      END;
      Scanner.Match(Scanner.end);
      RETURN AST.NewCaseNode(expr, AST.NewCaseStatNode(low, high, cases, else));
    END CaseStat;

    PROCEDURE  WhileStat() : AST.StmtList;
      VAR x : AST.Expr; s : AST.StmtList;
    BEGIN
      x := CheckBool(Expr.Expression()); Scanner.Match(Scanner.do); StatSeq(s); Scanner.Match(Scanner.end);
      RETURN ASTH.NewWhile(x, s);
    END WhileStat;

    PROCEDURE  RepeatStat() : AST.StmtList;
      VAR x : AST.Expr; s : AST.StmtList;
    BEGIN StatSeq(s); Scanner.Match(Scanner.until); x := CheckBool(Expr.Expression()); RETURN ASTH.NewRepeat(x, s);
    END RepeatStat;

    PROCEDURE  LoopStat() : AST.StmtList;
      VAR s : AST.StmtList;
    BEGIN INC(LoopLevel); StatSeq(s); Scanner.Match(Scanner.end); DEC(LoopLevel); RETURN AST.NewLoopNode(s);
    END LoopStat;

    PROCEDURE ForStat() : AST.StmtList;
      VAR ctrlV : Symtab.Symbol; control : AST.Design; lower, upper, step, expr : AST.Expr; body : AST.StmtList;
    BEGIN
      IF Scanner.token = Scanner.ident THEN
        Expr.qualident(ctrlV); control := ASTH.NewDesign(ctrlV); Scanner.Match(Scanner.becomes);
        lower := Expr.Expression(); Scanner.Match(Scanner.to); upper := Expr.Expression();
        IF Scanner.token = Scanner.by THEN
          Scanner.Get(Scanner.token); ConstExpression(step, expr);
          IF ~(step.type.form IN Symtab.IntSet) OR (step.val.i0 = 0) THEN Config.Error(E.IllegalValue); step := ASTH.NewIntConst(1); END;
        ELSE step := ASTH.NewIntConst(1);
        END;
        Scanner.Match(Scanner.do); StatSeq(body); Scanner.Match(Scanner.end); RETURN ASTH.NewFor(control, lower, upper, step.val.i0, body);
      ELSE Config.Error(E.IdentExpected); RETURN ASTH.NewNullStmt();
      END;
    END ForStat;

    PROCEDURE WithStat() : AST.StmtList;
      VAR
        cvar, typ : Symtab.Symbol;
        origType : Symtab.Type;
        else, stmt : AST.StmtList;
        withL, curWith, lastWith : AST.WithList;
        ctrl, testtype : AST.Design;
    BEGIN
      origType := NIL; withL := NIL;
      LOOP
        IF Scanner.token = Scanner.ident THEN
          Expr.qualident(cvar); ctrl := ASTH.NewDesign(cvar); Scanner.Match(Scanner.colon);
          IF Scanner.token = Scanner.ident THEN
            Expr.qualident(typ);
            testtype := ASTH.NewDesign(typ);
            origType := cvar.type; cvar.type := typ.type;
          ELSE Config.Error(E.IdentExpected);
          END;
        ELSE Config.Error(E.IdentExpected);
        END;
        Scanner.Match(Scanner.do); StatSeq(stmt);
        IF origType # NIL THEN cvar.type := origType; origType := NIL; END;
        
        curWith := ASTH.NewWithType(ctrl, testtype, stmt);
        IF withL = NIL THEN withL := curWith ELSE lastWith.next := curWith END;
        lastWith := curWith;

        IF Scanner.token = Scanner.bar THEN Scanner.Get(Scanner.token)
        ELSE EXIT;
        END;
      END;
      IF Scanner.token = Scanner.else THEN Scanner.Get(Scanner.token); StatSeq(else);
      ELSE else := AST.NewHaltNode(ASTH.NewBoolConst(FALSE), ASTH.NewIntConst(Config.HaltWith));
      END;
      Scanner.Match(Scanner.end); RETURN AST.NewWithNode(withL, else);
    END WithStat;

    PROCEDURE  ExitStat() : AST.StmtList;
    BEGIN IF LoopLevel = 0 THEN Config.Error(E.MisplacedExit); END; RETURN ASTH.NewExit();
    END ExitStat;

    PROCEDURE  ReturnStat() : AST.Return; (* this allows a type name to be returned: RETURN TypeName! error *)
      VAR ret : AST.Return; x : AST.Expr; sym : Symtab.Symbol; proc : Symtab.SymbolProc;
    BEGIN
      IF Scanner.token < Scanner.semicolon THEN x := Expr.Expression();
      ELSE x := NIL;
      END;
      IF Semantics.level > 0 THEN
        sym := Symtab.ScopeOwner(Symtab.topScope); ASSERT(sym # NIL);
        proc := sym(Symtab.SymbolProc);
        IF x # NIL THEN x := Semantics.AssignCompat(proc.type(Symtab.Procedure).result, x); ret := AST.NewReturnNode(proc, x);
        ELSE
          IF proc.type(Symtab.Procedure).result # Symtab.notyp THEN Config.Error(E.ResultTypeMismatch); END;
          ret := AST.NewReturnNode(proc, NIL);
        END;
      ELSE (* return from module *) ret := AST.NewReturnNode(NIL, NIL);
      END;
      RETURN ret;
    END ReturnStat;

  BEGIN
    lastStmt := ASTH.NewNullStmt(); headStmt := NIL;
    LOOP
      Scanner.Sync(Scanner.ident, 14);
      IF Scanner.token = Scanner.ident THEN
        Expr.qualident(id); lhs := ASTH.NewDesign(id); lhs := Expr.selector(lhs);
        IF (Scanner.token = Scanner.becomes) OR (Scanner.token = Scanner.eql) THEN curStmt := Assign(lhs);
        ELSIF (lhs.class = AST.Ndsgn) & (lhs.subcl = AST.Dstdproc) THEN curStmt := StdProc.StdProcCall(lhs, Expr.StdArgs());
        ELSE (* normal procedure or method call *)
          lhs := ASTH.SetupCall(lhs, fp, aparm);
          IF Scanner.token = Scanner.lparen THEN Scanner.Get(Scanner.token);
            aparm := Expr.ActualParameters(fp, aparm); Scanner.Match(Scanner.rparen);
          ELSIF (fp # NIL) & ~(fp.kind IN {Symtab.par, Symtab.varpar}) THEN Config.Error(E.TooFewAparm);
          END;
          curStmt := ASTH.NewProcCall(AST.NewFuncCallNode(lhs, aparm));
          IF Semantics.level > 0 THEN owner := Symtab.ScopeOwner(Symtab.topScope);
            IF owner # NIL THEN EXCL(owner.flags, Symtab.leaf); END;
          END;
        END;
      ELSE
        CASE Scanner.token OF
        |  Scanner.if: Scanner.Get(Scanner.token); curStmt := IfStat();
        | Scanner.case: Scanner.Get(Scanner.token); curStmt := CaseStat();
        | Scanner.while: Scanner.Get(Scanner.token); curStmt := WhileStat();
        | Scanner.repeat: Scanner.Get(Scanner.token); curStmt := RepeatStat();
        | Scanner.loop: Scanner.Get(Scanner.token); curStmt := LoopStat();
        | Scanner.for: Scanner.Get(Scanner.token); curStmt := ForStat();
        | Scanner.with: Scanner.Get(Scanner.token); curStmt := WithStat();
        | Scanner.exit: Scanner.Get(Scanner.token); curStmt := ExitStat();
        | Scanner.return: Scanner.Get(Scanner.token); curStmt := ReturnStat();
        ELSE EXIT;
        END;
      END;
      lastStmt := AST.BindStmtList(lastStmt, curStmt);
      IF headStmt = NIL THEN headStmt := lastStmt; END;
      CASE Scanner.token OF
      |  Scanner.semicolon: Scanner.Get(Scanner.token);
      | Scanner.ident, Scanner.case..Scanner.return: Config.Error(E.SemicolonExpected);
      ELSE EXIT;
      END;
    END;
    IF headStmt = NIL THEN stmt := lastStmt; ELSE stmt := headStmt; END;
  END StatSeq;

  PROCEDURE ProcDecl(VAR x : AST.Enter);
    VAR
      fwd : Symtab.Symbol;
      proc : Symtab.SymbolProc;
      name : Scanner.Name;
      mode, vis : SHORTINT;
      forward : BOOLEAN;
      sysflag : INTEGER;

    PROCEDURE GetCode;
      VAR ext: Symtab.ConstExt; n: INTEGER; c: LONGINT; cproc : Symtab.SymbolCodeProc;
    BEGIN
      cproc := proc(Symtab.SymbolCodeProc); ext := cproc.code; n := 0;
      LOOP
        IF Scanner.token = Scanner.number THEN c := Scanner.intval; INC(n);
          IF (c < 0) OR (c > 255) OR (n = Symtab.MaxCodeProcLen) THEN
            Config.Error(E.TooManyAparm); c := 1; n := 1;
          END ;
          Scanner.Get(Scanner.token); ext[n] := CHR(c)
        END ;

        CASE Scanner.token OF
        |  Scanner.comma: Scanner.Get(Scanner.token);
        |  Scanner.number: Config.Error(E.CommaExpected);
        ELSE ext[0] := CHR(n); EXIT;
        END;
      END ;
      INCL(cproc.flags, Symtab.body);
    END GetCode;

    PROCEDURE GetParams;
      VAR ptype : Symtab.Procedure; dummy : Symtab.SymbolScope;
    BEGIN
      proc.vis := vis; proc.kind := mode;
      ptype := proc.type(Symtab.Procedure); ptype.result := Symtab.notyp;
      proc.flags := proc.flags - Symtab.symSpecificFlags;
      IF Scanner.token = Scanner.lparen THEN Scanner.Get(Scanner.token); FormalParameters(ptype.parms, ptype.result);
      ELSE ptype.parms := Symtab.FirstScopeVar(Symtab.topScope); (* method procedure w/ no parameters -- 'self' gets set up *)
      END;
      IF fwd # NIL THEN
        Semantics.CheckParamMatch(proc.type(Symtab.Procedure).parms, fwd.type(Symtab.Procedure).parms, TRUE);
        IF proc.type(Symtab.Procedure).result # fwd.type(Symtab.Procedure).result THEN
          Config.Error(E.ResultMismatch);
        END;
        (* we have a forward procedure, drop newly created scope and use existing one *)
        proc := fwd(Symtab.SymbolProc); dummy := Symtab.CloseScope();
        Symtab.ReopenScope(fwd(Symtab.SymbolProc).scope, fwd);
      END;
    END GetParams;

    PROCEDURE Body;
      VAR lProc : AST.Enter; stmt: AST.StmtList; c: LONGINT; decl : AST.Declaration; 
    BEGIN
      Config.GetSourcePos(c); INCL(proc.flags, Symtab.body); Scanner.Match(Scanner.semicolon);
      DeclarationSequence(lProc, stmt, decl);
      x := AST.NewEnterNode(proc, lProc, stmt, decl, NIL, NIL); x.pos := c;
      IF Scanner.token = Scanner.ident THEN
        IF Scanner.name # proc.name^ THEN Config.Error(E.IdentMismatch); END;
        Scanner.Get(Scanner.token);
      ELSE Config.Error(E.IdentExpected);
      END;
    END Body;

    PROCEDURE TProcDecl;
      VAR
        self, oldSelf, baseProc, ovrrideParms, baseParms: Symtab.Symbol;
        objTyp, recTyp, baseSelfType : Symtab.Type;
        selfName: Scanner.Name; objMode: SHORTINT;

      PROCEDURE Receiver(VAR mode: SHORTINT; VAR self: Scanner.Name; VAR typ, rec : Symtab.Type);
        VAR obj: Symtab.Symbol; tf, rf : SHORTINT;

      BEGIN
        typ := Symtab.undftyp; rec := NIL;
        SetParmMode(mode); self := Scanner.name; Scanner.Match(Scanner.ident); Scanner.Match(Scanner.colon);
        IF Scanner.token = Scanner.ident THEN
          obj := Symtab.Find(Scanner.name); Scanner.Get(Scanner.token);
          IF obj = NIL THEN Config.Error(E.UndeclaredIdent); (* no record *)
          ELSIF obj.kind # Symtab.type THEN Config.Error(E.BadReceiver);
          ELSE
            typ := obj.type; rec := typ; tf := typ.form;
            IF tf = Symtab.pointer THEN rec := typ(Symtab.Pointer).to; END;
            rf := rec.form;

            IF ~((mode = Symtab.par) & (tf = Symtab.pointer) & (rf = Symtab.record) OR (mode = Symtab.varpar) & (tf = Symtab.record)) THEN
              Config.Error(E.ReceiverError); rec := NIL
            END;

            IF (rec # NIL) & (rec.mno # Semantics.level) THEN Config.Error(E.BadReceiver); rec := NIL END;
          END;
        ELSE Config.Error(E.IdentExpected);
        END;
        Scanner.Match(Scanner.rparen);
        IF rec = NIL THEN
          rec := Symtab.NewRecordType(); Symtab.OpenScopeRecord(Symtab.ScopeOwner(Symtab.topScope));
          rec(Symtab.Record).scope := Symtab.CloseScope();
        END;
      END Receiver;

    BEGIN
      Scanner.Get(Scanner.token); mode := Symtab.tproc;
      IF Semantics.level > 0 THEN Config.Error(E.MustBeGlobalProc) END ;
      Receiver(objMode, selfName, objTyp, recTyp);
      IF Scanner.token = Scanner.ident THEN
        name := Scanner.name; SetVis(vis);
        fwd := Symtab.FindField(name, recTyp(Symtab.Record));
        baseProc := Symtab.FindField(name, recTyp(Symtab.Record).ancestor);

        IF (baseProc # NIL) & (baseProc.kind # Symtab.tproc) THEN baseProc := NIL END ;
        IF fwd = baseProc THEN fwd := NIL END ;

        proc := Symtab.NewProcedureSym(); INCL(proc.flags, Symtab.leaf);
        IF (fwd # NIL) & (fwd.mnolev # Semantics.level) THEN fwd := NIL END ;
        IF (fwd # NIL) & (fwd.kind = Symtab.tproc) & ~(Symtab.body IN fwd.flags) THEN
          (* there exists a corresponding forward declaration *)
          IF fwd.vis # vis THEN Config.Error(E.ExportMismatch) END;
        ELSE
          IF fwd # NIL THEN Config.Error(E.MultipleDefinition); fwd := NIL END ;
          Symtab.ReopenScope(recTyp(Symtab.Record).scope, NIL); InsertSymbol(name, proc);
          recTyp(Symtab.Record).scope := Symtab.CloseScope();
        END ;

        INC(Semantics.level); Symtab.OpenScopeProcedure(Semantics.level, proc);
        self := Symtab.NewBasicSym(objMode); self.type := objTyp; InsertSymbol(selfName, self);
        GetParams;
        IF baseProc # NIL THEN (* override base procedure *)
          oldSelf := baseProc.type(Symtab.Procedure).parms; baseSelfType := oldSelf.type;
          IF (objMode # oldSelf.kind) OR ~Symtab.Extends(objTyp, baseSelfType) THEN Config.Error(E.ParmMismatch); END ;
          baseParms := Symtab.FirstParm(baseProc.type(Symtab.Procedure));
          ovrrideParms := Symtab.FirstParm(proc.type(Symtab.Procedure));
          Semantics.CheckParamMatch(Symtab.NextParm(ovrrideParms), Symtab.NextParm(baseParms), FALSE);
          IF proc.type(Symtab.Procedure).result # baseProc.type(Symtab.Procedure).result THEN Config.Error(E.ResultMismatch) END ;
          IF (baseProc.vis = Symtab.export) & (proc.vis = Symtab.internal) & (recTyp.sym # NIL) & (recTyp.sym.vis = Symtab.export) THEN Config.Error(E.ExportOverride) END ;
          INCL(proc.flags, Symtab.redef);
        END;
        proc.type(Symtab.Procedure).parms := Symtab.FirstScopeVar(Symtab.topScope);
        proc.type(Symtab.Procedure).sysflag := sysflag;
        IF ~forward THEN Body END ;
        DEC(Semantics.level);
        proc.scope := Symtab.CloseScope();
      ELSE Config.Error(E.IdentExpected);
      END;
    END TProcDecl;

  BEGIN
    proc := NIL; forward := FALSE; x := NIL; mode := Symtab.lproc; sysflag := 0;
    
    IF (Scanner.token # Scanner.ident) & (Scanner.token # Scanner.lparen) THEN (* tproc or lexical mark *)
      CASE Scanner.token OF
      |  Scanner.times: (* used as proc variable, no effect *)
      |  Scanner.arrow: forward := TRUE;
      |  Scanner.minus: mode := Symtab.cproc; (* code proc *)
      |  Scanner.plus: mode := Symtab.iproc; (* interrupt proc *) (* XXX -- obsolete? remove? do we really need this? 97.09.06 *)
      |  Scanner.lbrak: CheckSysFlag(sysflag);
      ELSE Config.Error(E.IdentExpected);
      END;
      IF (mode IN {Symtab.cproc, Symtab.iproc}) & ~Symtab.SYSimported THEN Config.Error(E.SystemNotImported); END;
      IF (Scanner.token <= MAX(SET)) & (Scanner.token IN {Scanner.times, Scanner.arrow, Scanner.minus, Scanner.plus}) THEN
        Scanner.Get(Scanner.token); (* CheckSysFlag positions at correct token *)
      END;
    END;

    IF Scanner.token = Scanner.lparen THEN TProcDecl;
    ELSIF Scanner.token = Scanner.ident THEN
      fwd := Symtab.Find(Scanner.name); name := Scanner.name; SetVis(vis);
      IF (vis IN {Symtab.export, Symtab.exportR}) & (mode = Symtab.lproc) THEN mode := Symtab.xproc; END;

      IF (fwd # NIL) & (fwd.mnolev # Semantics.level) THEN fwd := NIL END;
      IF (fwd # NIL) & (fwd.kind IN {Symtab.lproc, Symtab.xproc}) & ~(Symtab.body IN fwd.flags) THEN
        (* there exists a corresponding forward declaration; don't include in symtab *)
        proc := Symtab.NewProcedureSym(); INCL(proc.flags, Symtab.leaf);
        IF fwd.vis # vis THEN Config.Error(E.ExportMismatch) END;
      ELSE
        IF mode IN {Symtab.lproc, Symtab.xproc, Symtab.iproc} THEN proc := Symtab.NewProcedureSym();
        ELSE proc := Symtab.NewCodeProcSym();
        END;
        IF fwd # NIL THEN Config.Error(E.MultipleDefinition); fwd := NIL; END;
        InsertSymbol(name, proc);
      END;
      IF (mode # Symtab.lproc) & (Semantics.level > 0) THEN Config.Error(E.MustBeGlobalProc) (* incorrect mark *) END ;

      INC(Semantics.level); Symtab.OpenScopeProcedure(Semantics.level, proc);
      Symtab.LinkSymbol(proc, NIL); GetParams;

      proc.type(Symtab.Procedure).parms := Symtab.FirstScopeVar(Symtab.topScope);
      IF mode = Symtab.cproc THEN GetCode;
      ELSIF ~forward THEN Body;
      END;
      DEC(Semantics.level);
      proc.scope := Symtab.CloseScope(); proc.type(Symtab.Procedure).sysflag := sysflag;
    ELSE Config.Error(E.IdentExpected);
    END;
  END ProcDecl;

  (* post: init is a tree-list of variables that require initialization *)
  PROCEDURE DeclarationSequence(VAR nestedProcs : AST.Enter; VAR body : AST.StmtList; VAR decl : AST.Declaration);
    VAR
      firstSym, symbol : Symtab.Symbol;
      value, expr : AST.Expr;
      typ : Symtab.Type;
      proc: AST.Enter;
      symconst : Symtab.SymbolConst;
      i : INTEGER;
      nested : AST.StmtList;
      DeclList, DeclListTail : AST.Declaration;

    PROCEDURE NewDeclaration(sym : Symtab.Symbol; expr : AST.Expr);
      VAR n : AST.Declaration; dn : AST.Node;
    BEGIN n := AST.NewDeclarationNode(sym, expr, IsForward(sym.type));
      IF DeclList = NIL THEN DeclList := n; END;
      dn := AST.BindNodes(DeclListTail, n); DeclListTail := dn(AST.Declaration);
    END NewDeclaration;

  BEGIN DeclList := NIL; DeclListTail := NIL; InitForwardType;
    LOOP
      IF Scanner.token = Scanner.type THEN Scanner.Get(Scanner.token);
        WHILE Scanner.token = Scanner.ident DO
          symbol := Symtab.NewBasicSym(Symtab.type); InsertSymbol(Scanner.name, symbol);
          SetVis(symbol.vis);
          CASE Scanner.token OF
          |  Scanner.eql, Scanner.becomes, Scanner.colon:
            IF Scanner.token # Scanner.eql THEN Config.Error(E.EqlExpected); END;
            Scanner.Get(Scanner.token); symbol.type := TypeDecl(symbol.type);
          ELSE Config.Error(E.EqlExpected);
          END;

          NewDeclaration(symbol, NIL);
          IF symbol.type.sym = NIL THEN symbol.type.sym := symbol; END;
          IF symbol.type.form IN {Symtab.record, Symtab.array, Symtab.dynarr} THEN 
            FixupForwardType(symbol); 
          END;
          Scanner.Match(Scanner.semicolon);
        END;
      ELSIF Scanner.token = Scanner.const THEN Scanner.Get(Scanner.token);
        WHILE Scanner.token = Scanner.ident DO
          symconst := Symtab.NewConstSym(Symtab.undftyp); 
          InsertSymbol(Scanner.name, symconst); SetVis(symconst.vis);
          CASE Scanner.token OF
          |  Scanner.eql, Scanner.becomes, Scanner.colon:
            IF Scanner.token # Scanner.eql THEN Config.Error(E.EqlExpected) END;
            Scanner.Get(Scanner.token); ConstExpression(value, expr);
          ELSE Config.Error(E.EqlExpected); expr := ASTH.NewIntConst(1);
          END;
          NewDeclaration(symconst, expr); symconst.val := value.val; 
          symconst.type := value.type; symconst.val.type := value.type;
          Scanner.Match(Scanner.semicolon);
        END;
      ELSIF Scanner.token = Scanner.var THEN Scanner.Get(Scanner.token);
        WHILE Scanner.token = Scanner.ident DO
          firstSym := NIL;
          LOOP
            IF Scanner.token = Scanner.ident THEN symbol := Symtab.NewBasicSym(Symtab.var);
              InsertSymbol(Scanner.name, symbol); SetVis(symbol.vis);
              IF symbol.vis = Symtab.internal THEN INCL(symbol.flags, Symtab.leaf); END;
              IF firstSym = NIL THEN firstSym := symbol; END;
              NewDeclaration(symbol, NIL);
            ELSE Config.Error(E.IdentExpected);
            END;

            CASE Scanner.token OF
            |  Scanner.comma: Scanner.Get(Scanner.token);
            |  Scanner.ident: Config.Error(E.CommaExpected);
            ELSE EXIT;
            END;
          END;
          Scanner.Match(Scanner.colon); 
          DistributeType(firstSym, symbol, Type(Symtab.notyp), TRUE);
          INCL(symbol.type.flags, Symtab.pvused); Scanner.Match(Scanner.semicolon);
        END;
      ELSE EXIT; (* ~(token IN {var, const, type}) *)
      END;
    END;
    CheckForwardTypes;

    nestedProcs := NIL;
    WHILE Scanner.token = Scanner.procedure DO
      Scanner.Get(Scanner.token); ProcDecl(proc);
      IF proc # NIL THEN
        nested := AST.BindStmtList(proc, nestedProcs); nestedProcs := proc(AST.Enter);
      END;
      Scanner.Match(Scanner.semicolon);
    END;

    IF Scanner.token = Scanner.begin THEN Scanner.Get(Scanner.token); StatSeq(body);
    ELSE body := ASTH.NewNullStmt();
    END;
    decl := DeclList;
    Scanner.Match(Scanner.end);
  END DeclarationSequence;

  PROCEDURE Module*(VAR tree : AST.Node);
    VAR
      localproc : AST.Enter;
      body : AST.StmtList;
      enter : AST.Enter;
      modname, name, alias : Scanner.Name;
      done : BOOLEAN;
      import : AST.Import;
      impSym : Symtab.Symbol;
      decl : AST.Declaration;
      m : Symtab.SymbolProc; (* module procedure *)

      PROCEDURE MakeModuleSymbol();
      BEGIN
        m := Symtab.NewProcedureSym(); 
	m.kind := Symtab.xproc; m.vis := Symtab.export; INCL(m.flags, Symtab.modinit);
        m.scope := Symtab.topScope; InsertSymbol(modname, m);
        Symtab.SetModuleSymbol(Symtab.topScope(Symtab.SymbolModuleScope), m);
      END MakeModuleSymbol;

  BEGIN
    Scanner.Get(Scanner.token);
    IF Scanner.token = Scanner.module THEN
      Scanner.Get(Scanner.token);
      IF Scanner.token = Scanner.ident THEN
        COPY(Scanner.name, modname); Symtab.SetModuleName(modname);
        Scanner.Get(Scanner.token); Scanner.Match(Scanner.semicolon);
        IF Scanner.token = Scanner.import THEN Scanner.Get(Scanner.token);
          LOOP
            IF Scanner.token = Scanner.ident THEN
              COPY(Scanner.name, alias); COPY(alias, name); Scanner.Get(Scanner.token);
              IF Scanner.token = Scanner.becomes THEN
                Scanner.Get(Scanner.token);
                IF Scanner.token = Scanner.ident THEN COPY(Scanner.name, name); Scanner.Get(Scanner.token);
                ELSE Config.Error(E.IdentExpected);
                END;
              END;
              IE.Import(alias, name, done);
              IF ~done THEN Config.Error(E.ImportFailed);
              ELSE
                impSym :=  Symtab.Find(alias);
                IF impSym.name^ # "SYSTEM" THEN
                  (* init procedure from imported module needs to be used instead of the scope symbol
                    so that CGH.Enter can handle fixups to externals properly *)
                  impSym := Symtab.FindImport(impSym(Symtab.SymbolProc), name); (* aliased import init codes still have original name *)
                  import := AST.NewImportNode(impSym);
                ELSE import := AST.NewImportNode(impSym); INCL(import.flags, AST.noinit); (* SYSTEM has no init code *)
                END;
                import.next := ImportList; ImportList := import;
                IF ImportListTail = NIL THEN ImportListTail := import; END;
              END;
            ELSE Config.Error(E.IdentExpected);
            END;
            IF Scanner.token = Scanner.comma THEN Scanner.Get(Scanner.token);
            ELSIF Scanner.token = Scanner.ident THEN Config.Error(E.CommaExpected);
            ELSE EXIT;
            END;
          END;
          Scanner.Match(Scanner.semicolon);
        END;
      ELSE Config.Error(E.IdentExpected);
      END;

      body := NIL;
      IF ~Config.err THEN
        MakeModuleSymbol();
        DeclarationSequence(localproc, body, decl);
	
        
	(* XXX 
	  tree traversal should set topScope to the scope 
	  which is being traversed and this should be called
	   only when a real FP varaible is declared (don't forget global records!)
      	*)
	
	
        Symtab.MakeTempFPU;
        ASSERT(m # NIL); tree := AST.NewEnterNode(m, localproc, body, decl, NIL, ImportList);
        INCL(tree.flags, AST.main);

        IF Scanner.token = Scanner.ident THEN
          IF Scanner.name # modname THEN Config.Error(E.IdentMismatch); END;
          Scanner.Get(Scanner.token);
        ELSE Config.Error(E.IdentExpected);
        END;
        IF Scanner.token # Scanner.period THEN Config.Error(E.PeriodExpected) END;
      END;
    ELSE Config.Error(E.ModuleExpected);
    END;
  END Module;

  PROCEDURE NILGlobalPointers;
  BEGIN ImportList := NIL; ImportListTail := NIL; FwdPtr := NIL;
  END NILGlobalPointers;
  
  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN LoopLevel := 0; NILGlobalPointers; RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;
  
BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
END O3Parser.

