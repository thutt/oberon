MODULE SKLTB;
IMPORT 
  OPM:=SKLMD, 
  T:=SKLT, 
  ST:=SKLST, 
  OPS:=SKLOS,
  EL:=SKLERR;

  PROCEDURE err(n : INTEGER);
  BEGIN OPM.err(n);
  END err;

  PROCEDURE NewConvert*(from : T.Expr; to : ST.Type) : T.Expr;
    VAR x : T.Expr;
  BEGIN x := T.NewMExprNode(T.Econvert, from); x.type := to; RETURN x;
  END NewConvert;

  (**** Constants ****)
  PROCEDURE NewNil*() : T.Expr;
    VAR n : T.Expr;
  BEGIN n := T.NewConstExprNode(ST.niltyp); n.val.i0 := OPM.NilVal; RETURN n;
  END NewNil;

  PROCEDURE NewBoolConst*(b : BOOLEAN) : T.Expr;
    VAR n : T.Expr;
  BEGIN
    n := T.NewConstExprNode(ST.booltyp);
    IF b THEN n.val.i0 := OPM.TrueVal ELSE n.val.i0 := OPM.FalseVal END;
    RETURN n;
  END NewBoolConst;

  PROCEDURE CheckSetConst(elem : T.Expr; VAR v : LONGINT);
  BEGIN
    IF (T.constant IN elem.flags) THEN v := elem.val.i0;
      IF (v < 0) OR (v > OPM.MaxSet) THEN err(EL.IllegalValue); v := 0; END;
    END;
  END CheckSetConst;

  (* put a function into symtab for getting the range... *)
  PROCEDURE ConstSetIntType*(node : T.Expr);
  BEGIN node.type := ST.IntTypeOf(node.val.i0);
  END ConstSetIntType;

  PROCEDURE NewIntConst*(i : LONGINT) : T.Expr;
    VAR const : T.Expr;
  BEGIN const := T.NewConstExprNode(ST.undftyp); const.val.i0 := i; ConstSetIntType(const); RETURN const;
  END NewIntConst;

  (* create a Dconst node *)
  PROCEDURE NewConstNode(sym : ST.Symbol; type : ST.Type) : T.Expr;
    VAR const : T.Design;  x : T.Design;
  BEGIN sym.type := type; x := T.NewDesignNode(T.Dconst, sym); INCL(x.flags, T.constant); RETURN x;
  END NewConstNode;

  PROCEDURE NewRealConst*(r : LONGREAL; type : ST.Type) : T.Expr;
    VAR x : T.Expr;
  BEGIN x := T.NewConstExprNode(type); x.val.real := r; RETURN x;
  END NewRealConst;

  PROCEDURE NewString*(s : OPS.String; len : LONGINT) : T.Expr;
    VAR x : T.Expr;
  BEGIN x := T.NewConstExprNode(ST.stringtyp);
    x.val.ext := ST.NewConstExt(); x.val.i0 := len; COPY(s, x.val.ext^);
    RETURN x;
  END NewString;

  (* turn off the leaf flag, if needed; address has been used *)
  PROCEDURE CheckLeaf*(x : T.Expr; dynArrToo: BOOLEAN);
    VAR sym : ST.Symbol;
  BEGIN
    IF x.class = T.Ndsgn THEN
      (* only need to check atomic variables; arrays and record access do not count *)
      IF x.subcl = T.Dderef THEN x := x(T.Deref).base; END;
      IF x.subcl IN {T.Diguard, T.Deguard} THEN x := x(T.Guard).design; END;
      sym := x(T.Design).sym;
      IF (sym # NIL) & (dynArrToo OR (sym.type.form # ST.dynarr)) THEN
        EXCL(sym.flags, ST.leaf);
      END;
    END;
  END CheckLeaf;

  PROCEDURE NewMethod*(x : T.Design; sym : ST.Symbol) : T.Field;
    VAR n : T.Field;
  BEGIN
    n := T.NewFieldNode(x, 0, sym);
    n.subcl := T.Dmethod;
    n.type := sym.type(ST.Procedure).result;
    RETURN n;
  END NewMethod;

  (* deref pointers; rvalues only *)
  PROCEDURE NewDeref*(base : T.Design) : T.Deref;
    VAR type : ST.Type; sym, tosym : ST.Symbol;
  BEGIN type := base.type;
    IF T.RValue(base) THEN
      IF type.form = ST.pointer THEN
        sym := type.sym; type := type(ST.Pointer).to; tosym := type.sym;
        (* if pointer not anonymous and pointed-to not anonymous, then public fingerprint required *)
        IF (sym # NIL) & (sym.name^ # "") & (tosym # NIL) & (tosym.name^ # "") THEN INCL(type.flags, ST.pbused); END;
      ELSE err(EL.PointerRequired);
      END;
    ELSE  err(EL.RvalueRequired);
    END;
    RETURN T.NewDerefNode(base, type);
  END NewDeref;

  PROCEDURE NewIndex*(base : T.Design; index : T.Expr) : T.Index;
    VAR type : ST.Type; i : LONGINT;
  BEGIN type := base.type;
    IF ~T.RValue(base) THEN err(EL.RvalueRequired);
    ELSIF ~(base.type.form IN {ST.dynarr, ST.array}) THEN err(EL.NotAnArray);
    ELSIF ~(index.type.form IN ST.IntSet) THEN err(EL.NotInteger);
    ELSE type := type(ST.Array).of;
      IF (index.class = T.Econst) & (base.type.form = ST.array) THEN
        i := index.val.i0;
        IF (i < 0) OR (i >= base.type(ST.Array).n) THEN err(EL.IllegalIndexValue); END;
      END;
    END;
    RETURN T.NewIndexNode(base, 0, 0, index, type);
  END NewIndex;

  (**** Designators ****)
  PROCEDURE NewDesign*(s : ST.Symbol) : T.Design;
    VAR mode : T.NODESUBCLASS; x : T.Design;
  BEGIN
    CASE s.kind OF
    |  ST.anon, ST.var, ST.darrdesc, ST.arrdesc, ST.recdesc: x := T.NewDesignNode(T.Dvar, s);
    |  ST.par: x := T.NewDesignNode(T.Dpar, s);
    |  ST.varpar: x := T.NewDesignNode(T.Dvarpar, s);
    |  ST.type: x := T.NewDesignNode(T.Dtype, s);
    |  ST.stdproc: x := T.NewDesignNode(T.Dstdproc, s);
    |  ST.fwdproc, ST.lproc, ST.xproc, ST.cproc, ST.iproc: x := T.NewDesignNode(T.Dproc, s);
    |  ST.const:
      IF s.type = ST.stringtyp THEN x := T.NewDesignNode(T.Dconst, s);
        INCL(x.flags, T.constant); x.val := ST.NewConst(ST.stringtyp); x.val^ := x(T.Design).sym(ST.SymbolConst).val^;
      ELSE x := T.NewConstExprNode(s.type); x.val^ := s(ST.SymbolConst).val^; mode := T.Econst;
      END;
    ELSE err(EL.IllegalUse); mode := T.Merror;
    END;
    RETURN x;
  END NewDesign;

  PROCEDURE NewGuard*(design : T.Design; guard : ST.Symbol) : T.Design;
    VAR df, gf : SHORTINT; td : ST.Type;
  BEGIN df := design.type.form; gf := guard.type.form;
    IF T.RValue(design) THEN
      IF guard.kind = ST.type THEN
        IF df = ST.record THEN
          IF (gf # ST.record) OR (design.subcl # T.Dvarpar) THEN err(EL.BadGuardTest); END;
        ELSIF df = ST.pointer THEN
          IF gf = ST.pointer THEN
            IF ~ST.Extends(guard.type, design.type) THEN err(EL.NotAnExtension) END;
          ELSE err(EL.PointerRequired)
          END;
        ELSE err(EL.BadGuardTest);
        END;
      ELSE err(EL.NotAType);
      END;
    ELSE err(EL.RvalueRequired);
    END;
    IF guard.type = design.type THEN RETURN design; (* delete runtime guard, not needed *)
    ELSE
      IF df = ST.record THEN td := guard.type;
      ELSIF guard.type.form = ST.pointer THEN td := guard.type(ST.Pointer).to;
      ELSE RETURN design; (* error should have already been reported *)
      END;
      RETURN T.NewGuardNode(T.Deguard, design, guard);
    END;
  END NewGuard;

  (**** Statements ****)

  PROCEDURE NewNullStmt*() : T.StmtList;
    VAR s : T.StmtList;
  BEGIN  s := T.NewStmtListNode(T.Snull);  RETURN s;
  END NewNullStmt;

  PROCEDURE NewAssign*(l : T.Design; r : T.Expr; type : ST.Type) : T.Assign;
    VAR n : T.Design;
  BEGIN
    (* record types get implicit type guard *)
    IF l.type.form = ST.record THEN
      IF (l.subcl IN {T.Diguard, T.Deguard}) THEN n := l(T.Guard).design
      ELSE n := l
      END;

      (* delete meaningless eguard: p(t)^ := rec since we insert one anyway *)
      IF (n.subcl = T.Dderef) & (n(T.Deref).base.subcl IN {T.Diguard, T.Deguard}) THEN
        n(T.Deref).base := n(T.Deref).base(T.Guard).design;
      END;

      IF (l.type.sym # NIL) & (n.subcl IN {T.Dderef, T.Dvarpar}) THEN
        (* add implicit type guard; named record assign *)
          n := T.NewGuardNode(T.Diguard, n, l.type.sym);
      END;
      l := n;
    ELSIF (l.type.form = ST.array) & (l.type(ST.Array).of = ST.chartyp) &
          (r.type.form = ST.string) & (r(T.Design).sym(ST.SymbolConst).val.i0 = 1) THEN (* replace string-"" assignment w/ 0X *)
      r := T.NewConstExprNode(ST.chartyp); r.val.i0 := 0; l := NewIndex(l, NewIntConst(0));
    END;
    RETURN T.NewAssignNode(l, r);
  END NewAssign;

  PROCEDURE NewWhile*(cond : T.Expr; body : T.StmtList) : T.WhileRepeat;
  BEGIN RETURN T.NewWhileRepeatNode(T.Swhile, cond, body);
  END NewWhile;

  PROCEDURE NewRepeat*(cond : T.Expr; body : T.StmtList) : T.WhileRepeat;
  BEGIN RETURN T.NewWhileRepeatNode(T.Srepeat, cond, body);
  END NewRepeat;

  PROCEDURE NewWithType*(control, testtype : T.Design; stmt : T.StmtList) : T.WithList;
    VAR x : T.WithList;
  BEGIN
    x := T.NewWithListNode(control, testtype, stmt);
    IF control.subcl IN {T.Dvar, T.Dpar, T.Dvarpar} THEN
      IF testtype.sym.kind # ST.type THEN err(EL.NotAType);
      ELSIF ~ST.Extends(testtype.type, control.type) THEN err(EL.NotAnExtension);
      END;
    ELSE err(EL.NotAVariable);
    END;
    RETURN x;
  END NewWithType;

  PROCEDURE NewFor*(control : T.Design; lower, upper : T.Expr; step : LONGINT; body : T.StmtList) : T.For;
    VAR x : T.For;
  BEGIN
    x := T.NewForNode(control, lower, upper, step, body);
    IF ~(control.subcl IN {T.Dvar, T.Dpar, T.Dvarpar}) THEN err(EL.NotAForVariable); END;
    IF ~(control.type.form IN ST.IntSet) THEN err(EL.IntegerTypeRequired) END;
    IF ~(lower.type.form IN ST.IntSet) OR (lower.type.form > control.type.form) THEN
      err(EL.IncompatibleAssignment);
    END;
    IF ~(upper.type.form IN ST.IntSet) OR (upper.type.form > control.type.form) THEN
      err(EL.IncompatibleAssignment);
    END;
    RETURN x;
  END NewFor;

  PROCEDURE NewExit*() : T.StmtList;
    VAR x : T.StmtList;
  BEGIN  x := T.NewStmtListNode(T.Sexit); RETURN x;
  END NewExit;

  (**** Expressions ****)

  PROCEDURE NewIsTest*(var : T.Expr; guard : T.Design) : T.IsTest;
    VAR vf, gf : SHORTINT; gsym : ST.Symbol;
  BEGIN
    IF var.class # T.Ndsgn THEN var := T.NewDesignNode(T.Merror, NIL); END;
    vf := var.type.form; gf := guard.type.form;
    (* var must be a pointer to a record or a varpar; var must be a base of type *)
    IF guard.subcl # T.Dtype THEN err(EL.NotAType);
    ELSIF ~T.LValue(var) THEN err(EL.NotAVariable);
    ELSIF (vf = ST.record) THEN
      IF (var.subcl # T.Dvarpar) OR (gf # ST.record) THEN err(EL.BadGuardTest); END;
    ELSIF (var.subcl # T.Merror) & ((vf # ST.pointer) OR (gf # ST.pointer)) THEN
      err(EL.GuardNeedsPointer);
    ELSIF ~ST.Extends(guard.type, var.type) THEN err(EL.NotAnExtension);
    END;
    RETURN T.NewIsTestNode(var(T.Design), guard);
  END NewIsTest;

  PROCEDURE NewInTest*(lhs, rhs : T.Expr) : T.Expr;
    VAR x : T.Expr; i : LONGINT; lValid, rValid : BOOLEAN;
  BEGIN
    x := T.NewDExprNode(T.Ein, lhs, rhs, ST.booltyp);
    lValid := T.RValue(lhs) & (lhs.type.form IN ST.IntSet);
    rValid := T.RValue(rhs) & (rhs.type = ST.settyp);
    IF ~lValid OR ~rValid THEN err(EL.InvalidInOp);
    ELSIF T.constant IN lhs.flags THEN
      i := lhs.val.i0;
      IF (i < 0) OR (i > OPM.MaxSet) THEN err(EL.IllegalConstValue);
      ELSIF T.constant IN rhs.flags THEN x := NewBoolConst(i IN rhs.val.set);
      END;
    END;
    RETURN x;
  END NewInTest;

  PROCEDURE NewSetRange*(lo, hi : T.Expr) : T.Expr;
    VAR n : T.Expr; l, h : LONGINT;
  BEGIN l := 0; h := 0;
    IF ~T.RValue(lo) THEN err(EL.RvalueRequired); END;
    IF ~(lo.type.form IN ST.IntSet) THEN err(EL.SetElementErr);
    ELSE CheckSetConst(lo, l);
    END;

    IF ~T.RValue(hi) THEN err(EL.RvalueRequired); END;
    IF ~(hi.type.form IN ST.IntSet) THEN err(EL.SetElementErr);
    ELSE CheckSetConst(hi, h);
    END;

    IF l > h THEN err(EL.SetRangeErr); END;

    IF (T.constant IN lo.flags) & (T.constant IN hi.flags) THEN
      n := T.NewConstExprNode(ST.settyp); n.val.set := {l..h};
    ELSE
      n := T.NewDExprNode(T.Eupto, lo, hi, ST.settyp);
    END;
    RETURN n;
  END NewSetRange;

  PROCEDURE NewSetElem*(elem : T.Expr) : T.Expr;
    VAR
      x : T.Expr;
      dummy : LONGINT;
      s : SET;
  BEGIN
    IF ~(T.constant IN elem.flags) THEN
      x := NewConvert(elem, ST.settyp);
    ELSE
      x := T.NewConstExprNode(ST.settyp);
      s := {elem.val.i0};
      x.val.set := s;
    END;
    IF ~T.RValue(elem) THEN
      err(EL.RvalueRequired);
    ELSIF ~(elem.type.form IN ST.IntSet) THEN
      err(EL.SetElementErr);
    ELSE
      CheckSetConst(elem, dummy);
    END;
    RETURN x;
  END NewSetElem;

  PROCEDURE NewEmptySet*() : T.Expr;
    VAR x : T.Expr;
  BEGIN x := T.NewConstExprNode(ST.settyp); x.val.set := {}; RETURN x;
  END NewEmptySet;

  PROCEDURE NewMonoExpr*(subcl : T.NODESUBCLASS; op : T.Expr) : T.MExpr;
    VAR x : T.MExpr;
  BEGIN
    x := T.NewMExprNode(subcl, op);
    IF ~T.RValue(op) THEN err(EL.RvalueRequired); END;

    CASE subcl OF
    | T.Econvert: HALT(128);
    |  T.Enot: IF op.type # ST.booltyp THEN err(EL.UnaryNot); END;
    |  T.Euminus: IF ~(op.type.form IN ST.NumSet) THEN err(EL.BadMinusOperand); END;
    |  T.Euplus: IF ~(op.type.form IN ST.NumSet) THEN err(EL.BadPlusOperand); END;
    END;
    RETURN x;
  END NewMonoExpr;

  (*
    x <=> tree which represents the procedure to call
    fpar is returned as the first formal parameter (self parm is not skipped)
  *)
  PROCEDURE SetupCall*(x : T.Design; VAR fpar : ST.Symbol; VAR args : T.Arg) : T.Design;
    VAR
      selfTyp : ST.Type;
      rec : ST.Symbol;
      recv : T.Design;
      self : ST.Symbol;
  BEGIN
    IF x.subcl = T.Dmethod THEN (* method or super *)
      self := ST.FirstParm(x.sym.type(ST.Procedure));
      x.type := x.sym.type;
      selfTyp := self.type;
      recv := x(T.Field).base;
      IF recv.subcl = T.Dderef THEN
        IF selfTyp.form = ST.pointer THEN
          selfTyp := recv.type;
          recv := recv(T.Deref).base; (* bound to pointer, drop deref *)
        END;
      END;

      args := T.NewArgNode(recv);
      fpar := ST.NextParm(self); (* self is always the first parm *)
      ASSERT(selfTyp.form = ST.record);
      x(T.Field).base := NewDesign(ST.GetTD(selfTyp.sym.type));
    ELSE (* regular procedure call *)
      args := NIL;
      IF (x.sym # NIL) & (x.sym.kind IN {ST.fwdproc, ST.lproc, ST.xproc, ST.cproc, ST.iproc}) THEN
        fpar := x.sym.type(ST.Procedure).parms;
        x.type := x.sym.type; (* This node synthesizes the procedure, not the result. *)
      ELSIF (x.subcl # T.Dtype) & (x.type.form = ST.procedure) THEN
        fpar := x.type(ST.Procedure).parms;
      ELSE
        err(EL.NotAProcedure);
        fpar := NIL;
      END;
    END;
    RETURN x;
  END SetupCall;

  PROCEDURE NewProcCall*(call : T.FuncCall) : T.ProcCall;
  BEGIN ASSERT(call.type.form # ST.procedure);
    IF call.type # ST.notyp THEN err(EL.FuncAsProc); END;
    RETURN T.NewProcCallNode(call);
  END NewProcCall;

  PROCEDURE ConstConvert(n : T.Expr; to : ST.Type) : T.Expr;
    VAR from : ST.Type;
  BEGIN
    from := n.type; n.type := to;
    CASE to.form OF
    | ST.char: (* from: string literal, sint, int *)
      CASE from.form OF
      |  ST.string:
         IF n.val.i0 = 1 THEN
           n.val.i0 := ORD(n.val.ext[0]);
           n.val.ext := NIL;
           n.type := to;
         ELSE
           err(EL.StringDoesNotFit);
        END;

      |  ST.sint, ST.int:
         IF (n.val.i0 < 0) OR (n.val.i0 > 0FFH) THEN
           err(EL.IllegalValue);
         END;
      END;

    | ST.sint:  (* from: INTEGER *)
      IF (n.val.i0 < OPM.MinSInt) OR (n.val.i0 > OPM.MaxSInt) THEN
        err(EL.NumberTooLarge);
      END;

    | ST.int: (* from: CHAR, SHORTINT, LONGINT *)
      IF (n.val.i0 < OPM.MinInt) OR (n.val.i0 > OPM.MaxInt) THEN
        err(EL.NumberTooLarge);
      END;

    |  ST.lint:  (* from: SHORTINT, INTEGER, REAL, LONGREAL *)
       IF from.form IN ST.RealSet THEN
         n.val.i0 := ENTIER(n.val.real);
         IF (n.val.real < OPM.MinLInt) OR (n.val.real > OPM.MaxLInt) THEN
           err(EL.NumberTooLarge);
         END;
      END;

    |  ST.real: (* from: CHAR, SHORTINT, INTEGER, LONGINT *)
       n.val.real := n.val.i0;

    |  ST.lreal: (* from: CHAR, SHORTINT, INTEGER, LONGINT, REAL *)
       IF ~(from.form IN ST.RealSet) THEN
         n.val.real := n.val.i0;
       END;
    END;
    RETURN n;
  END ConstConvert;

  PROCEDURE Convert*(n : T.Expr; to : ST.Type) : T.Expr;
  BEGIN
    IF T.constant IN n.flags THEN RETURN ConstConvert(n, to);
    ELSE RETURN NewConvert(n, to);
    END;
  END Convert;

  PROCEDURE ModuleBegin*;
  END ModuleBegin;
  
  PROCEDURE ModuleEnd*;
  END ModuleEnd;
  
END SKLTB.
