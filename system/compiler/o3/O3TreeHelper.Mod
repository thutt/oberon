MODULE O3TreeHelper;
  IMPORT 
    Config:=O3Config, 
    AST :=O3TreeNode, 
    Symtab:=O3Symtab,
    Scanner:=O3Scanner, 
    E:=O3Errors;

  PROCEDURE err(n : INTEGER);
  BEGIN Config.Error(n);
  END err;

  PROCEDURE NewConvert*(from : AST.Expr; to : Symtab.Type) : AST.Expr;
    VAR x : AST.Expr;
  BEGIN x := AST.NewMExprNode(AST.Econvert, from); x.type := to; RETURN x;
  END NewConvert;

  (**** Constants ****)
  PROCEDURE NewNil*() : AST.Expr;
    VAR n : AST.Expr;
  BEGIN n := AST.NewConstExprNode(Symtab.niltyp); n.val.i0 := Config.NilValue; RETURN n;
  END NewNil;

  PROCEDURE NewBoolConst*(b : BOOLEAN) : AST.Expr;
    VAR n : AST.Expr;
  BEGIN n := AST.NewConstExprNode(Symtab.booltyp); n.val.bool := b; RETURN n;
  END NewBoolConst;

  (* put a function into symtab for getting the range... *)
  PROCEDURE ConstSetIntType*(node : AST.Expr);
  BEGIN node.type := Symtab.IntTypeOf(node.val.i0); node.val.type := node.type;
  END ConstSetIntType;

  PROCEDURE NewIntConst*(i : LONGINT) : AST.Expr;
    VAR const : AST.Expr;
  BEGIN const := AST.NewConstExprNode(Symtab.IntTypeOf(i)); const.val.i0 := i; RETURN const;
  END NewIntConst;

  PROCEDURE NewCharConst*(ch : CHAR) : AST.Expr;
    VAR const : AST.Expr;
  BEGIN const := AST.NewConstExprNode(Symtab.undftyp); const.val.i0 := ORD(ch); const.type := Symtab.chartyp; RETURN const;
  END NewCharConst;

  PROCEDURE NewSetConst*(s : SET) : AST.Expr;
    VAR const : AST.Expr;
  BEGIN const := AST.NewConstExprNode(Symtab.undftyp); const.val.set := s; const.type := Symtab.settyp; RETURN const;
  END NewSetConst;

  (* create a Dconst node *)
  PROCEDURE NewConstNode(sym : Symtab.Symbol; type : Symtab.Type) : AST.Design;
    VAR x : AST.Design;
  BEGIN sym.type := type; x := AST.NewDesignNode(AST.Dconst, sym); INCL(x.flags, AST.constant); RETURN x;
  END NewConstNode;

  PROCEDURE NewRealConst*(r : LONGREAL; type : Symtab.Type) : AST.Expr;
    VAR x : AST.Expr;
  BEGIN x := AST.NewConstExprNode(type); x.val.real := r; RETURN x;
  END NewRealConst;

  PROCEDURE NewStringConst*(s : Scanner.String; len : LONGINT) : AST.Expr;
    VAR x : AST.Expr;
  BEGIN 
    (* 
      String constants appearing in a CONST section will be created with
      this mechanism.  String constants appearing in expressions will be created
      as a compiler-generated constant symbol.  This makes it easier for the compiler
      to ensure that all (constant) literals are allocated memory without requiring
      a sophisticated method for managing used literals -- it simply tags along
      with address assignment.  This could also be improved by allowing two constants
      (CONST a = 'gungla'; b = a;) which are equivalent to share the same string
      data, but that violates the tenet that there should be one primary way of 
      doing any operation in the compiler and special tricks should not be 
      employed
    *)
    x := AST.NewConstExprNode(Symtab.stringtyp);
    x.val.ext := Symtab.NewConstExt(); x.val.i0 := len; COPY(s, x.val.ext^);
    RETURN x;
  END NewStringConst;

  (* turn off the leaf flag, if needed; address has been used *)
  PROCEDURE CheckLeaf*(x : AST.Expr; dynArrToo: BOOLEAN);
    VAR sym : Symtab.Symbol;
  BEGIN (* this code is obsolete and needs to be rewritten 
    IF x.class = AST.Ndsgn THEN
      (* only need to check atomic variables; arrays and record access do not count *)
      IF x.subcl = AST.Dderef THEN x := x(AST.Deref).base; END;
      IF x.subcl IN {AST.Diguard, AST.Deguard} THEN x := x(AST.Guard).design; END;
      sym := x(AST.Design).sym;
      IF (sym # NIL) & (dynArrToo OR (sym.type.form # Symtab.dynarr)) THEN
        EXCL(sym.flags, Symtab.leaf);
      END;
    END; *)
  END CheckLeaf;

  PROCEDURE NewMethod*(x : AST.Design; sym : Symtab.Symbol) : AST.Field;
    VAR n : AST.Field;
  BEGIN
    n := AST.NewFieldNode(x, sym); n.subcl := AST.Dmethod;
    n.type := sym.type;
    RETURN n;
  END NewMethod;

  (* deref pointers; rvalues only *)
  PROCEDURE NewDeref*(base : AST.Design) : AST.Deref;
    VAR type : Symtab.Type; sym, tosym : Symtab.Symbol;
  BEGIN type := base.type;
    IF AST.RValue(base) THEN
      IF type.form = Symtab.pointer THEN
        sym := type.sym; type := type(Symtab.Pointer).to; tosym := type.sym;
        (* if pointer not anonymous and pointed-to not anonymous, then public fingerprint required *)
        IF (sym # NIL) & (sym.name^ # "") & (tosym # NIL) & (tosym.name^ # "") THEN INCL(type.flags, Symtab.pbused); END;
      ELSE err(E.PointerRequired);
      END;
    ELSE  err(E.RvalueRequired);
    END;
    RETURN AST.NewDerefNode(base, type);
  END NewDeref;

  PROCEDURE NewIndex*(base : AST.Design; index : AST.Expr) : AST.Index;
    VAR type : Symtab.Type; i : LONGINT;
  BEGIN type := base.type;
    IF ~AST.RValue(base) THEN err(E.RvalueRequired);
    ELSIF ~(base.type.form IN {Symtab.dynarr, Symtab.openarr, Symtab.array}) THEN err(E.NotAnArray);
    ELSIF ~(index.type.form IN Symtab.IntSet) THEN err(E.NotInteger);
    ELSE type := type(Symtab.Array).of;
      IF (index.class = AST.Econst) & (base.type.form = Symtab.array) THEN
        i := index.val.i0;
        IF (i < 0) OR (i >= base.type(Symtab.Array).n) THEN err(E.IllegalIndexValue); END;
      END;
    END;
    RETURN AST.NewIndexNode(base, 0, 0, index, type);
  END NewIndex;

  (**** Designators ****)
  PROCEDURE NewDesign*(s : Symtab.Symbol) : AST.Design;
    VAR x : AST.Design;
  BEGIN
    CASE s.kind OF
    |  Symtab.anon, Symtab.var, Symtab.darrdesc, Symtab.arrdesc, Symtab.recdesc: x := AST.NewDesignNode(AST.Dvar, s);
    |  Symtab.par: x := AST.NewDesignNode(AST.Dpar, s);
    |  Symtab.varpar: x := AST.NewDesignNode(AST.Dvarpar, s);
    |  Symtab.type: x := AST.NewDesignNode(AST.Dtype, s);
    |  Symtab.stdproc: x := AST.NewDesignNode(AST.Dstdproc, s);
    |  Symtab.fwdproc, Symtab.lproc, Symtab.xproc, Symtab.cproc, Symtab.iproc: x := AST.NewDesignNode(AST.Dproc, s);
    |  Symtab.const: x := NewConstNode(s, s.type);
    ELSE err(E.IllegalUse); s := Symtab.NewTempVar(s.type); x := AST.NewDesignNode(AST.Danon, s);
    END;
    RETURN x;
  END NewDesign;

  PROCEDURE NewGuard*(design : AST.Design; guard : Symtab.Symbol) : AST.Design;
    VAR df, gf : SHORTINT; td : Symtab.Type;
  BEGIN df := design.type.form; gf := guard.type.form;
    IF AST.RValue(design) THEN
      IF guard.kind = Symtab.type THEN
        IF df = Symtab.record THEN
          IF (gf # Symtab.record) OR (design.subcl # AST.Dvarpar) THEN err(E.BadGuardTest); END;
        ELSIF df = Symtab.pointer THEN
          IF gf = Symtab.pointer THEN
            IF ~Symtab.Extends(guard.type, design.type) THEN err(E.NotAnExtension) END;
          ELSE err(E.PointerRequired)
          END;
        ELSE err(E.BadGuardTest);
        END;
      ELSE err(E.NotAType);
      END;
    ELSE err(E.RvalueRequired);
    END;
    IF guard.type = design.type THEN RETURN design; (* delete runtime guard, not needed *)
    ELSE
      IF df = Symtab.record THEN td := guard.type;
      ELSIF guard.type.form = Symtab.pointer THEN td := guard.type(Symtab.Pointer).to;
      ELSE RETURN design; (* error should have already been reported *)
      END;
      RETURN AST.NewGuardNode(AST.Deguard, design, guard);
    END;
  END NewGuard;

  (**** Statements ****)

  PROCEDURE NewNullStmt*() : AST.StmtList;
    VAR s : AST.StmtList;
  BEGIN  s := AST.NewStmtListNode(AST.Snull);  RETURN s;
  END NewNullStmt;

  PROCEDURE NewAssign*(l : AST.Design; r : AST.Expr; type : Symtab.Type) : AST.Assign;
    VAR n : AST.Design;
  BEGIN
    (* record types get implicit type guard *)
    IF l.type.form = Symtab.record THEN
      IF (l.subcl IN {AST.Diguard, AST.Deguard}) THEN n := l(AST.Guard).design
      ELSE n := l
      END;

      (* delete meaningless eguard: p(t)^ := rec since we insert one anyway *)
      IF (n.subcl = AST.Dderef) & (n(AST.Deref).base.subcl IN {AST.Diguard, AST.Deguard}) THEN
        n(AST.Deref).base := n(AST.Deref).base(AST.Guard).design;
      END;

      IF l.type.sym # NIL THEN
        (* add implicit type guard?; named record assign *)
        IF n.subcl = AST.Dderef THEN
          n(AST.Deref).base := AST.NewGuardNode(AST.Diguard, n(AST.Deref).base, l.type.sym);
        ELSIF n.subcl = AST.Dvarpar THEN n := AST.NewGuardNode(AST.Diguard, n, l.type.sym);
        END;
      END;
      l := n;
    ELSIF l.type.form = Symtab.procedure THEN
      (* Assignment to a procedure variable.  The rhs can either be
       * another procedure variable or a global procedure.  If the rhs is
       * a global procedure, insert a 'address-of' node.  If the rhs is a 
       * procedure variable, no further action is necessary.  There is no need
       * to ensure that it is a global procedure since the parser handles that
       * semantic.
       *)
      IF (r.class = AST.Ndsgn) & (r.subcl = AST.Dproc) THEN
        r := AST.NewAdrNode(type, r);
      END;
    END;
    RETURN AST.NewAssignNode(l, r);
  END NewAssign;

  PROCEDURE NewWhile*(cond : AST.Expr; body : AST.StmtList) : AST.WhileRepeat;
  BEGIN RETURN AST.NewWhileRepeatNode(AST.Swhile, cond, body);
  END NewWhile;

  PROCEDURE NewRepeat*(cond : AST.Expr; body : AST.StmtList) : AST.WhileRepeat;
  BEGIN RETURN AST.NewWhileRepeatNode(AST.Srepeat, cond, body);
  END NewRepeat;

  PROCEDURE NewWithType*(control, testtype : AST.Design; stmt : AST.StmtList) : AST.WithList;
    VAR x : AST.WithList;
  BEGIN
    x := AST.NewWithListNode(control, testtype, stmt);
    IF control.subcl IN {AST.Dvar, AST.Dpar, AST.Dvarpar} THEN
      IF testtype.sym.kind # Symtab.type THEN err(E.NotAType);
      ELSIF ~Symtab.Extends(testtype.type, control.type) THEN err(E.NotAnExtension);
      END;
    ELSE err(E.NotAVariable);
    END;
    RETURN x;
  END NewWithType;

  PROCEDURE NewFor*(control : AST.Design; lower, upper : AST.Expr; step : LONGINT; body : AST.StmtList) : AST.For;
    VAR x : AST.For;
  BEGIN
    x := AST.NewForNode(control, lower, upper, step, body);
    IF ~(control.subcl IN {AST.Dvar, AST.Dpar, AST.Dvarpar}) THEN err(E.NotAForVariable); END;
    IF ~(control.type.form IN Symtab.IntSet) THEN err(E.IntegerTypeRequired) END;
    IF ~(lower.type.form IN Symtab.IntSet) OR (lower.type.form > control.type.form) THEN
      err(E.IncompatibleAssignment);
    END;
    IF ~(upper.type.form IN Symtab.IntSet) OR (upper.type.form > control.type.form) THEN
      err(E.IncompatibleAssignment);
    END;
    RETURN x;
  END NewFor;

  PROCEDURE NewExit*() : AST.StmtList;
    VAR x : AST.StmtList;
  BEGIN  x := AST.NewStmtListNode(AST.Sexit); RETURN x;
  END NewExit;

  (**** Expressions ****)

  PROCEDURE NewIsTest*(var : AST.Expr; guard : AST.Design) : AST.IsTest;
    VAR vf, gf : SHORTINT; gsym : Symtab.Symbol;
  BEGIN
    IF var.class # AST.Ndsgn THEN 
      gsym := Symtab.NewTempVar(Symtab.undftyp); var := AST.NewDesignNode(AST.Danon, gsym); 
    END;
    vf := var.type.form; gf := guard.type.form;
    (* var must be a pointer to a record or a varpar; var must be a base of type *)
    IF guard.subcl # AST.Dtype THEN err(E.NotAType);
    ELSIF ~AST.LValue(var) THEN err(E.NotAVariable);
    ELSIF (vf = Symtab.record) THEN
      IF (var.subcl # AST.Dvarpar) OR (gf # Symtab.record) THEN err(E.BadGuardTest); END;
    ELSIF (vf # Symtab.pointer) OR (gf # Symtab.pointer) THEN err(E.GuardNeedsPointer);
    ELSIF ~Symtab.Extends(guard.type, var.type) THEN err(E.NotAnExtension);
    END;
    RETURN AST.NewIsTestNode(var(AST.Design), guard);
  END NewIsTest;

  PROCEDURE NewInTest*(lhs, rhs : AST.Expr) : AST.Expr;
    VAR x : AST.Expr; i : LONGINT; lValid, rValid : BOOLEAN;
  BEGIN
    x := AST.NewDExprNode(AST.Ein, lhs, rhs, Symtab.booltyp);
    lValid := AST.RValue(lhs) & (lhs.type.form IN Symtab.IntSet);
    rValid := AST.RValue(rhs) & (rhs.type = Symtab.settyp);
    IF ~lValid OR ~rValid THEN err(E.InvalidInOp); END;
    RETURN x;
  END NewInTest;

  PROCEDURE NewSetRange*(lo, hi : AST.Expr) : AST.Expr;
    VAR n : AST.Expr;
  BEGIN
    IF ~AST.RValue(lo) THEN err(E.RvalueRequired); END;
    IF ~(lo.type.form IN Symtab.IntSet) THEN err(E.SetElementErr);
    END;

    IF ~AST.RValue(hi) THEN err(E.RvalueRequired); END;
    IF ~(hi.type.form IN Symtab.IntSet) THEN err(E.SetElementErr);
    END;

    n := AST.NewDExprNode(AST.Eupto, lo, hi, Symtab.settyp);
    RETURN n;
  END NewSetRange;

  PROCEDURE NewSetElem*(elem : AST.Expr) : AST.Expr;
    VAR x : AST.Expr; dummy : LONGINT; s : SET;
  BEGIN x := NewConvert(elem, Symtab.settyp);
    IF ~AST.RValue(elem) THEN err(E.RvalueRequired);
    ELSIF ~(elem.type.form IN Symtab.IntSet) THEN err(E.SetElementErr);
    END;
    RETURN x;
  END NewSetElem;

  PROCEDURE NewEmptySet*() : AST.Expr;
    VAR x : AST.Expr;
  BEGIN x := AST.NewConstExprNode(Symtab.settyp); x.val.set := {}; RETURN x;
  END NewEmptySet;

  PROCEDURE NewMonoExpr*(subcl : AST.NODESUBCLASS; op : AST.Expr) : AST.MExpr;
    VAR x : AST.MExpr;
  BEGIN
    x := AST.NewMExprNode(subcl, op);
    IF ~AST.RValue(op) THEN err(E.RvalueRequired); END;

    CASE subcl OF
    | AST.Econvert: HALT(128);
    |  AST.Enot: IF op.type # Symtab.booltyp THEN err(E.UnaryNot); END;
    |  AST.Euminus: IF ~(op.type.form IN Symtab.NumSet) THEN err(E.BadMinusOperand); END;
    |  AST.Euplus: IF ~(op.type.form IN Symtab.NumSet) THEN err(E.BadPlusOperand); END;
    END;
    RETURN x;
  END NewMonoExpr;

  (*
    x <=> tree which represents the procedure to call
    fpar is returned as the first formal parameter (self parm is not skipped)
  *)
  PROCEDURE SetupCall*(x : AST.Design; VAR fpar : Symtab.Symbol; VAR args : AST.Arg) : AST.Design;
    VAR selfTyp : Symtab.Type; rec : Symtab.Symbol; recv : AST.Design; self : Symtab.Symbol;
  BEGIN
    IF x.subcl = AST.Dmethod THEN (* method or super *)
      self := Symtab.FirstParm(x.sym.type(Symtab.Procedure)); selfTyp := self.type; recv := x(AST.Field).base;
      IF recv.subcl = AST.Dderef THEN
        IF selfTyp.form = Symtab.pointer THEN selfTyp := recv.type; recv := recv(AST.Deref).base; (* bound to pointer, drop deref *) END;
      END;
      args :=  AST.NewArgNode(recv); fpar := Symtab.NextParm(self); (* self is always the first parm *)
      ASSERT(selfTyp.form = Symtab.record);
      x(AST.Field).base := NewDesign(Symtab.GetTD(selfTyp.sym, selfTyp.sym.type));
    ELSE (* regular procedure call *)
      args := NIL;
      IF (x.sym # NIL) & (x.sym.kind IN {Symtab.fwdproc, Symtab.lproc, Symtab.xproc, Symtab.cproc, Symtab.iproc}) THEN
        fpar := x.sym.type(Symtab.Procedure).parms; x.type := x.sym.type; (* x.sym.type(Symtab.Procedure).result; this node synthesizes the procedure, not the procedure result *)
      ELSIF (x.subcl # AST.Dtype) & (x.type.form = Symtab.procedure) THEN
        fpar := x.type(Symtab.Procedure).parms; (*x.type := x.type(Symtab.Procedure).result;*)
      ELSE err(E.NotAProcedure); fpar := NIL;
      END;
    END;
    RETURN x;
  END SetupCall;

  PROCEDURE NewProcCall*(call : AST.FuncCall) : AST.ProcCall;
  BEGIN ASSERT(call.type.form # Symtab.procedure);
    IF call.type # Symtab.notyp THEN err(E.FuncAsProc); END;
    RETURN AST.NewProcCallNode(call);
  END NewProcCall;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleBegin;
  
  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleEnd;

BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
END O3TreeHelper.
