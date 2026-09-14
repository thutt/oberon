MODULE O3Expression;
  IMPORT
    Config := O3Config,
    Symtab := O3Symtab,
    AST := O3TreeNode,
    ASTH := O3TreeHelper,
    Scanner := O3Scanner,
    Semantics := O3Semantics,
    StdProc := O3StdProc,
    E := O3Errors;

  VAR
    relTab : POINTER TO ARRAY OF AST.NODESUBCLASS;
    opTab : POINTER TO ARRAY OF AST.NODESUBCLASS;
    unopTab : POINTER TO ARRAY OF AST.NODESUBCLASS;
    PowerOf2 : LONGINT;

  PROCEDURE ^ Expression*() : AST.Expr;

  PROCEDURE qualident*(VAR symb : Symtab.Symbol);  (* [{module} '.'] <ident> *)
    VAR id : Symtab.Symbol; tok : SHORTINT;
  BEGIN id := Symtab.Find(Scanner.name); Scanner.Get(tok);
    IF (tok = Scanner.period) & (id # NIL) & Symtab.IsModule(id) THEN
      Scanner.Get(tok);
      IF tok = Scanner.ident THEN id := Symtab.FindImport(id(Symtab.SymbolProc), Scanner.name); Scanner.Get(tok);
      ELSE Config.Error(E.IdentExpected); id := NIL;
      END;
    END;

    IF id = NIL THEN Config.Error(E.UndeclaredIdent);  id := Symtab.NewBasicSym(Symtab.anon); id.type := Symtab.undftyp;
    ELSIF (id.kind IN {Symtab.var, Symtab.par, Symtab.varpar}) & (id.mnolev # Semantics.level) THEN EXCL(id.flags, Symtab.leaf);
    END;
    symb := id;
  END qualident;

  PROCEDURE StdArgs*() : AST.Arg;
    VAR arg, argList : AST.Arg;
  BEGIN (* Scanner.token = Scanner.lparen *)
    argList := NIL;
    IF Scanner.token = Scanner.lparen THEN
      Scanner.Get(Scanner.token);
      IF Scanner.token # Scanner.rparen THEN
        LOOP
          arg := AST.NewArgNode(Expression()); argList := AST.BindArg(argList, arg);
          IF Scanner.token = Scanner.comma THEN Scanner.Get(Scanner.token);
          ELSIF (Scanner.lparen <= Scanner.token) & (Scanner.token <= Scanner.ident) THEN Config.Error(E.CommaExpected);
          ELSE EXIT;
          END;
        END;
        Scanner.Match(Scanner.rparen); AST.ReverseArgList(argList);
      ELSE Scanner.Get(Scanner.token);
      END;
    ELSE Config.Error(E.LparenExpected);
    END;
    (* note: argList can be NIL *)
    RETURN argList;
  END StdArgs;

  (* can insert conversion nodes into l or r *)
  PROCEDURE DOp(op : AST.NODESUBCLASS; l, r : AST.Expr) : AST.Expr;
    CONST
      EqualitySet = {Symtab.bool, Symtab.byte, Symtab.char,
                     Symtab.sint, Symtab.int, Symtab.lint,
                     Symtab.real, Symtab.lreal,
                     Symtab.set, Symtab.nil, Symtab.pointer, Symtab.procedure};
      RelationalSet = {Symtab.byte, Symtab.char,
                       Symtab.sint, Symtab.int, Symtab.lint,
                       Symtab.real, Symtab.lreal};

    VAR lF, rF : SHORTINT; type, lt, rt : Symtab.Type; t0 : AST.Expr;
        str : Scanner.String;

    PROCEDURE strings(): BOOLEAN; (* TRUE => both operands are strings *)
      VAR lCharArr, rCharArr: BOOLEAN;
    BEGIN
      lCharArr := (l.type.form IN Symtab.ArraySet)
                & (l.type(Symtab.Array).of.form = Symtab.char)
                OR (lF = Symtab.string);
      rCharArr := (r.type.form IN Symtab.ArraySet)
                & (r.type(Symtab.Array).of.form = Symtab.char)
                OR (rF = Symtab.string);
      RETURN lCharArr & rCharArr;
    END strings;

  BEGIN
    lF := l.type.form; rF := r.type.form;
    IF (lF = Symtab.undef) OR (rF = Symtab.undef) THEN RETURN l; (* semantic error *)
    ELSE
      IF lF # rF THEN
        CASE lF OF
        |  Symtab.char:
          (* convert a single character into a static length character array *)
          IF (AST.constant IN l.flags)
           & (rF IN {Symtab.array, Symtab.openarr, Symtab.dynarr, Symtab.string}) THEN
            str[0] := CHR(l.val.i0); str[1] := 0X;
            l := ASTH.NewDesign(Symtab.MakeStringConst(str, 1));
          ELSE
            Config.Error(E.DyadicOperator);
          END;

        |  Symtab.sint:
           IF rF IN Symtab.NumSet THEN
             l := ASTH.NewConvert(l, r.type);
           ELSE
             Config.Error(E.DyadicOperator);
          END;

        |  Symtab.int:
           IF rF = Symtab.sint THEN
             r := ASTH.NewConvert(r, l.type)
           ELSIF rF IN Symtab.NumSet THEN
             l := ASTH.NewConvert(l, r.type)
           ELSE Config.Error(E.DyadicOperator);
           END;

        |  Symtab.lint:
           IF rF IN Symtab.IntSet THEN
             r := ASTH.NewConvert(r, l.type)
           ELSIF rF IN Symtab.RealSet THEN
             l := ASTH.NewConvert(l, r.type)
           END;

        |  Symtab.real:
           IF rF IN Symtab.IntSet THEN
             r := ASTH.NewConvert(r, l.type);
           ELSIF rF IN Symtab.RealSet THEN
             l := ASTH.NewConvert(l, r.type);
           ELSE
             Config.Error(E.DyadicOperator);
           END;

        |  Symtab.lreal:
           IF rF IN Symtab.NumSet THEN
             r := ASTH.NewConvert(r, l.type);
           ELSE
             Config.Error(E.DyadicOperator);
           END;

        |  Symtab.nil:
           IF ~(rF IN {Symtab.procedure, Symtab.pointer}) THEN
             Config.Error(E.DyadicOperator)
           END;

        |  Symtab.procedure:
           IF rF # Symtab.nil THEN
             Config.Error(E.DyadicOperator)
           END;

        |  Symtab.pointer:
           IF ~Semantics.ExprCompatPointer(l.type, r.type) THEN
             Config.Error(E.DyadicOperator)
           END;

        |  Symtab.array, Symtab.openarr, Symtab.dynarr, Symtab.string:
           IF (AST.constant IN r.flags) & (rF = Symtab.char) THEN
             str[0] := CHR(r.val.i0);
             str[1] := 0X;
             r := ASTH.NewDesign(Symtab.MakeStringConst(str, 1));
           ELSIF rF IN {Symtab.array, Symtab.openarr,
                        Symtab.dynarr, Symtab.string} THEN (* nop *)
           ELSE
             Config.Error(E.DyadicOperator);
           END;
        ELSE Config.Error(E.DyadicOperator);
        END;
      END; (* l.type is compatible with r.type *)

      type := l.type; lF := type.form; rF := r.type.form;

      CASE op OF
      |  AST.Eplus:
         IF ~(lF IN {Symtab.sint, Symtab.int, Symtab.lint,
                     Symtab.real, Symtab.lreal, Symtab.set}) THEN
           Config.Error(E.BadPlusOperand);
         END;

      |  AST.Eminus:
         IF ~(lF IN {Symtab.sint, Symtab.int, Symtab.lint,
                     Symtab.real, Symtab.lreal, Symtab.set}) THEN
           Config.Error(E.BadMinusOperand);
         END;

      |  AST.Etimes:
         IF ~(lF IN {Symtab.sint, Symtab.int, Symtab.lint,
                     Symtab.real, Symtab.lreal, Symtab.set}) THEN
           Config.Error(E.BadTimesOperand);
         END;

      |  AST.Eslash:
         IF lF IN Symtab.IntSet THEN
           type := Symtab.realtyp;
           l := ASTH.NewConvert(l, type);
           r := ASTH.NewConvert(r, type);
         ELSIF lF IN Symtab.RealSet THEN (* ok *)
         ELSIF ~(lF IN {Symtab.set, Symtab.undef}) THEN
           Config.Error(E.BadSlashOperand);
         END;

      |  AST.Emod:
         IF ~(lF IN Symtab.IntSet) THEN
           Config.Error(E.BadModOperand);
         END;

      |  AST.Ediv:
         IF ~(lF IN Symtab.IntSet) THEN
           Config.Error(E.BadDivOperand);
         END;

      |  AST.Eand:
         type := Symtab.booltyp;
         IF lF # Symtab.bool THEN
           Config.Error(E.BadAndOperand);
         END;

      |  AST.Eor:
         type := Symtab.booltyp;
         IF lF # Symtab.bool THEN
           Config.Error(E.BadOrOperand);
         END;

      |  AST.Eeql, AST.Eneq:
        type := Symtab.booltyp;
        IF ~(lF IN EqualitySet) & ~strings() THEN
          Config.Error(E.BadEqualityTest);
        END;

      | AST.Elss, AST.Eleq, AST.Egtr, AST.Egeq:
        type := Symtab.booltyp;
        IF ~(lF IN RelationalSet) & ~strings() THEN
          Config.Error(E.BadRelationalTest);
        END;
      END;
      RETURN AST.NewDExprNode(op, l, r, type);
    END;
  END DOp;

  PROCEDURE MOp*(op : AST.NODESUBCLASS; x : AST.Expr) : AST.Expr;
    VAR f : SHORTINT;
  BEGIN f := x.type.form;
    IF f IN Symtab.IntSet + Symtab.RealSet + {Symtab.bool, Symtab.set} THEN RETURN
      AST.NewMExprNode(op, x);
    ELSE
      CASE op OF
      |  AST.Enot: Config.Error(E.UnaryNot);
      |  AST.Euminus: Config.Error(E.BadMinusOperand);
      |  AST.Euplus: Config.Error(E.BadPlusOperand);
      | AST.Econvert: (* nop *)
      END;
      RETURN x;
    END;
  END MOp;

  PROCEDURE selector*(x: AST.Design) : AST.Design;
    VAR obj : Symtab.Symbol; name: Scanner.Name; e : AST.Expr;

    PROCEDURE RecordRef(x : AST.Design; fldName : Scanner.Name) : AST.Design;
      VAR
        scope : Symtab.SymbolScope;
        owner, proc, obj, field : Symtab.Symbol;
        typ: Symtab.Type;
        rec : AST.Design;

    BEGIN
      IF x.type.form = Symtab.record THEN
        obj := Symtab.FindField(fldName, x.type(Symtab.Record));
        IF obj # NIL THEN
          IF obj.kind = Symtab.tproc THEN x := ASTH.NewMethod(x, obj);
            IF Scanner.token = Scanner.arrow THEN  (* super call *) Scanner.Get(Scanner.token);
              field := obj; rec := x(AST.Field).base; (* deref or design node *)
              IF (rec.class = AST.Ndsgn) & (rec.subcl = AST.Dderef) THEN rec := rec(AST.Deref).base; END;
              (* rec = record variable *)

              scope := Symtab.topScope;  (* method making supercall *)
              (*
                find tproc which owns the scope containing the super call (ie: nested procs in a tproc)
                or it will find that a super call is not valid in the current context
              *)
              LOOP
                owner := Symtab.ScopeOwner(scope);
                IF (owner = NIL) OR (owner.kind = Symtab.tproc) THEN EXIT; END;
                scope := Symtab.PreviousScope(scope);
              END;

              (* first parm # Self => supercall invalid (y <=> record (Self)) *)
              IF (owner = NIL) OR (owner.type(Symtab.Procedure).parms # rec.sym) THEN Config.Error(E.InvalidSupercall); END;
              typ := rec.sym.type;
              IF typ.form = Symtab.pointer THEN typ := typ(Symtab.Pointer).to; END;
              proc := Symtab.FindField(field.name^, typ(Symtab.Record).ancestor);

              IF proc # NIL THEN INCL(x.flags, AST.super)
              ELSE Config.Error(E.BaseMethodNotFound);
              END;
            END;
            IF (obj.type(Symtab.Procedure).result # Symtab.notyp) & (Scanner.token # Scanner.lparen) THEN
              Config.Error(E.LparenExpected); (* function method? *)
            END;
          ELSE x := AST.NewFieldNode(x, obj);
          END;
        ELSE Config.Error(E.UndefinedField);
        END;
      ELSE Config.Error(E.NotARecordType);
      END;
      RETURN x;
    END RecordRef;

  BEGIN
    LOOP
      CASE Scanner.token OF
      |  Scanner.arrow: Scanner.Get(Scanner.token); x := ASTH.NewDeref(x);
      |  Scanner.lbrak: (* array access *)
        Scanner.Get(Scanner.token);
        LOOP
          IF x.type.form = Symtab.pointer THEN x := ASTH.NewDeref(x) END;
          e := Expression();
          IF e.type = Symtab.undftyp THEN e.type := Symtab.linttyp; END;
          x := ASTH.NewIndex(x, e);
          IF Scanner.token = Scanner.comma THEN Scanner.Get(Scanner.token)
          ELSE EXIT
          END;
        END ;
        Scanner.Match(Scanner.rbrak);
      |  Scanner.period: (* record access *)
        Scanner.Get(Scanner.token);
        IF Scanner.token = Scanner.ident THEN
          name := Scanner.name; Scanner.Get(Scanner.token);
          IF x.type.form = Symtab.pointer THEN x := ASTH.NewDeref(x); END;
          x := RecordRef(x, name);
        ELSE Config.Error(E.IdentExpected);
        END;
      |  Scanner.lbrace: (* type guard *)
        Scanner.Get(Scanner.token);
        IF Scanner.token = Scanner.ident THEN qualident(obj); x := ASTH.NewGuard(x, obj);
        ELSE Config.Error(E.IdentExpected);
        END ;
        Scanner.Match(Scanner.rbrace)
      |  Scanner.lparen: (* possible type guard or beginning of procedure call *)
        IF (x.class = AST.Ndsgn) & ~(x.subcl IN {AST.Dproc, AST.Dmethod, AST.Dstdproc}) &
          ~((x.subcl IN {AST.Dvar, AST.Dpar, AST.Dvarpar, AST.Dfield, AST.Dindex}) & (x.type.form = Symtab.procedure)) THEN
          Scanner.Get(Scanner.token);
          IF Scanner.token = Scanner.ident THEN qualident(obj); x := ASTH.NewGuard(x, obj); Config.Warn(E.OldStyleTypeGuard);
          ELSE Config.Error(E.IdentExpected);
          END ;
          Scanner.Match(Scanner.rparen)
        ELSE EXIT; (* it is a procedure call *)
        END;
      ELSE EXIT;
      END;
    END;
    RETURN x;
  END selector;

  PROCEDURE ActualParameters*(fpar: Symtab.Symbol; parms : AST.Arg) : AST.Arg;
    VAR aparlist, apar : AST.Arg; par : AST.Expr;

    PROCEDURE CheckParam(VAR ap: AST.Expr; fp: Symtab.Symbol);
      VAR str : Symtab.SymbolConst;

      (* check that dynamic array element types match *)
      PROCEDURE DynArrParCheck(ftyp : Symtab.Array; atyp: Symtab.Type; fvarpar: BOOLEAN);
        VAR f: INTEGER;
      BEGIN (* ftyp.form = Symtab.openarr *)
        f := atyp.form;
        IF fvarpar & (ftyp.of = Symtab.bytetyp) THEN (* ok *)
        ELSIF f IN {Symtab.array, Symtab.openarr, Symtab.dynarr} THEN
          IF ftyp.of.form = Symtab.openarr THEN DynArrParCheck(ftyp.of(Symtab.Array), atyp(Symtab.Array).of, fvarpar);
          ELSIF ftyp.of # atyp(Symtab.Array).of THEN Config.Error(E.OpenArrayMismatch);
          END;
        ELSE Config.Error(E.NotSuitableOpenArray);
        END;
      END DynArrParCheck;

      PROCEDURE MakeString(ap : AST.Expr) : Symtab.SymbolConst;
        VAR s : Scanner.String; c : Symtab.SymbolConst;
      BEGIN s[0] := CHR(ap.val.i0); s[1] := 0X;
        c := Symtab.MakeStringConst(s, 2); RETURN c;
      END MakeString;

    BEGIN
      IF fp.type.form # Symtab.undef THEN
        IF fp.kind = Symtab.varpar THEN
          IF (ap.class # AST.Ndsgn) OR ~(ap.subcl IN AST.LValueSet) THEN
            Config.Error(E.NotAVariable)
          ELSE ASTH.CheckLeaf(ap, FALSE);
          END;
          IF AST.readonly IN ap.flags THEN Config.Error(E.ReadOnlyVariable) END;

          IF fp.type.form = Symtab.openarr THEN
            DynArrParCheck(fp.type(Symtab.Array), ap.type, TRUE);
          ELSIF (fp.type.form = Symtab.record) & (ap.type.form = Symtab.record) THEN
            IF ~Symtab.Extends(ap.type, fp.type) THEN Config.Error(E.IncompatibleAssignment); END;
          ELSIF (fp.type = Symtab.sysptrtyp) & (ap.type.form = Symtab.pointer) THEN (* ok *)
          ELSIF (ap.type # fp.type) & ~((fp.type.form = Symtab.byte) &
                (ap.type.form IN {Symtab.char, Symtab.sint})) THEN
            Config.Error(E.VarParmMismatch)
          END;
        ELSIF fp.type.form = Symtab.openarr THEN
          IF (AST.constant IN ap.flags) & (ap.type.form = Symtab.char) THEN
            ap := ASTH.NewDesign(MakeString(ap));
          END;

          IF (ap.type.form = Symtab.string) & (fp.type(Symtab.Array).of.form = Symtab.char) THEN
            (* ok *)
          ELSIF (ap.class # AST.Ndsgn) OR ~(ap.subcl IN AST.LValueSet) THEN
            Config.Error(E.IllegalOpenArrayParm)
          ELSE DynArrParCheck(fp.type(Symtab.Array), ap.type, FALSE);
          END
        ELSE ap := Semantics.AssignCompat(fp.type, ap);
        END;
      END
    END CheckParam;

  BEGIN
    aparlist := parms;
    IF Scanner.token # Scanner.rparen THEN
      LOOP par := Expression();
        IF (fpar # NIL) & (fpar.kind IN {Symtab.par, Symtab.varpar}) THEN
          CheckParam(par, fpar); apar := AST.NewArgNode(par);
          aparlist := AST.BindArg(aparlist, apar); fpar := Symtab.NextParm(fpar);
        ELSE Config.Error(E.TooManyAparm);
        END;
        IF Scanner.token = Scanner.comma THEN Scanner.Get(Scanner.token);
        ELSIF (Scanner.token >= Scanner.lparen) & (Scanner.token <= Scanner.ident) THEN
          Config.Error(E.CommaExpected)
        ELSE EXIT;
        END;
      END;
      AST.ReverseArgList(aparlist);
    END;
    IF (fpar # NIL) & (fpar.kind IN {Symtab.par, Symtab.varpar}) THEN
      Config.Error(E.TooFewAparm);
    END;
    RETURN aparlist;
  END ActualParameters;

  PROCEDURE Expression*() : AST.Expr;
    VAR lhs : AST.Expr; typename : Symtab.Symbol; op : AST.NODECLASS;

    PROCEDURE SimpleExpression() : AST.Expr;
      VAR op : AST.NODECLASS; n : AST.Expr;

      PROCEDURE Term() : AST.Expr;
        VAR op : AST.NODECLASS; n, m : AST.Expr;

        PROCEDURE Factor() : AST.Expr;
          VAR ident, fpar : Symtab.Symbol; x : AST.Expr; apar : AST.Arg; owner : Symtab.Symbol;

          PROCEDURE Set() : AST.Expr;
            VAR l, r : AST.Expr;

            PROCEDURE Element() : AST.Expr;
              VAR lo, hi : AST.Expr;
            BEGIN
              lo := Expression();
              IF Scanner.token = Scanner.upto THEN
                Scanner.Get(Scanner.token); hi := Expression();
                RETURN ASTH.NewSetRange(lo, hi);
              ELSE RETURN ASTH.NewSetElem(lo);
              END;
            END Element;

          BEGIN
            Scanner.Get(Scanner.token);
            IF Scanner.token # Scanner.rbrace THEN
              l := Element();
              LOOP
                IF Scanner.token = Scanner.comma THEN Scanner.Get(Scanner.token);
                ELSIF (Scanner.token >= Scanner.lparen) & (Scanner.token <= Scanner.ident) THEN Config.Error(E.CommaExpected)
                ELSE EXIT;
                END;
                r := Element(); l := AST.NewDExprNode(AST.Eplus, l, r, Symtab.settyp);
              END;
            ELSE l := ASTH.NewEmptySet();
            END;
            Scanner.Match(Scanner.rbrace);
            RETURN l;
          END Set;

        BEGIN
          Scanner.Sync(Scanner.lparen, E.BadFactorStart);

          CASE Scanner.token OF
          |  Scanner.ident:
            qualident(ident); x := selector(ASTH.NewDesign(ident));
            IF x.subcl = AST.Dstdproc THEN x := StdProc.StdFuncCall(x(AST.Design), StdArgs());
            ELSIF Scanner.token = Scanner.lparen THEN (* regular or super call *)
              Scanner.Get(Scanner.token);
              x := ASTH.SetupCall(x(AST.Design), fpar, apar);
              apar := ActualParameters(fpar, apar); Scanner.Match(Scanner.rparen);
              x := AST.NewFuncCallNode(x(AST.Design), apar);
              IF Semantics.level > 0 THEN owner := Symtab.ScopeOwner(Symtab.topScope); EXCL(owner.flags, Symtab.leaf); END;
            END;
          |  Scanner.number:
            CASE Scanner.numtyp OF
            |  Scanner.char: x := ASTH.NewIntConst(Scanner.intval); x.type := Symtab.chartyp;
            |  Scanner.integer: x := ASTH.NewIntConst(Scanner.intval);
            | Scanner.real: x := ASTH.NewRealConst(Scanner.realval, Symtab.realtyp);
            |  Scanner.longreal: x := ASTH.NewRealConst(Scanner.lrlval, Symtab.lrltyp);
            END;
            Scanner.Get(Scanner.token);

          | Scanner.string:
            Scanner.Get(Scanner.token);
            x := ASTH.NewDesign(Symtab.MakeStringConst(Scanner.str, Scanner.intval));

          | Scanner.nil: Scanner.Get(Scanner.token); x := ASTH.NewNil();
          | Scanner.lparen: Scanner.Get(Scanner.token); x := Expression(); Scanner.Match(Scanner.rparen);
          | Scanner.lbrak: Scanner.Get(Scanner.token); Config.Error(E.LparenExpected); x := Expression(); Scanner.Match(Scanner.rparen);
          | Scanner.lbrace: x := Set();
          | Scanner.not: Scanner.Get(Scanner.token); x := ASTH.NewMonoExpr(AST.Enot, Factor());
          ELSE Scanner.Get(Scanner.token); x := ASTH.NewIntConst(0); Config.Error(E.BadFactorStart);
          END;
          RETURN x;
        END Factor;

      BEGIN
        n := Factor();
        WHILE (Scanner.token <= MAX(SET)) & (Scanner.token IN {Scanner.times, Scanner.slash, Scanner.div, Scanner.mod, Scanner.and}) DO
          op := opTab[Scanner.token - Scanner.times]; Scanner.Get(Scanner.token); m := Factor(); n := DOp(op, n, m);
        END;
        RETURN n;
      END Term;

    BEGIN
      IF (Scanner.token <= MAX(SET)) & (Scanner.token IN {Scanner.minus, Scanner.plus}) THEN
        op := unopTab[Scanner.token - Scanner.plus]; Scanner.Get(Scanner.token); n := Term(); n := MOp(op, n);
      ELSE n := Term();
      END;

      WHILE (Scanner.token <= MAX(SET)) & (Scanner.token IN {Scanner.plus, Scanner.minus, Scanner.or}) DO
        op := opTab[Scanner.token - Scanner.times]; Scanner.Get(Scanner.token); n := DOp(op, n, Term());
      END;
      RETURN n;
    END SimpleExpression;

  BEGIN
    lhs := SimpleExpression();
    CASE Scanner.token OF
    |  Scanner.eql, Scanner.neq, Scanner.lss, Scanner.leq, Scanner.gtr, Scanner.geq:
      op := relTab[Scanner.token - Scanner.eql]; Scanner.Get(Scanner.token); lhs := DOp(op, lhs, SimpleExpression());
    |  Scanner.in:
      Scanner.Get(Scanner.token); lhs := ASTH.NewInTest(lhs, SimpleExpression());
    | Scanner.is:
      Scanner.Get(Scanner.token);
      IF Scanner.token = Scanner.ident THEN qualident(typename);
      lhs := ASTH.NewIsTest(lhs, ASTH.NewDesign(typename));
      ELSE Config.Error(E.IdentExpected);
      END;
    ELSE (* nop *)
    END;
    RETURN lhs;
  END Expression;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleEnd;

  PROCEDURE Init;
  BEGIN
    (* relational operators *)
    NEW(relTab, Scanner.geq - Scanner.eql + 1);
    relTab[Scanner.eql - Scanner.eql] := AST.Eeql; relTab[Scanner.neq - Scanner.eql] := AST.Eneq;
    relTab[Scanner.lss - Scanner.eql] := AST.Elss; relTab[Scanner.leq - Scanner.eql] := AST.Eleq;
    relTab[Scanner.gtr - Scanner.eql] := AST.Egtr; relTab[Scanner.geq - Scanner.eql] := AST.Egeq;

    (* operators *)
    NEW(opTab, Scanner.or - Scanner.times + 1);
    opTab[Scanner.times - Scanner.times] := AST.Etimes;  opTab[Scanner.slash - Scanner.times] := AST.Eslash;
    opTab[Scanner.div   - Scanner.times] := AST.Ediv;    opTab[Scanner.mod   - Scanner.times] := AST.Emod;
    opTab[Scanner.plus  - Scanner.times] := AST.Eplus;  opTab[Scanner.minus - Scanner.times] := AST.Eminus;
    opTab[Scanner.and   - Scanner.times] := AST.Eand;    opTab[Scanner.or    - Scanner.times] := AST.Eor;

    (* unary operators *)
    NEW(unopTab, Scanner.minus - Scanner.plus + 1);
    unopTab[Scanner.plus - Scanner.plus] := AST.Euplus;  unopTab[Scanner.minus - Scanner.plus] := AST.Euminus;

    Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;

BEGIN Init;
END O3Expression.
