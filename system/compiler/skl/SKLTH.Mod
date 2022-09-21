MODULE SKLTH; (* Tree Hints (for loading registers & register interference) for 80x86 *)
IMPORT
  CGL:=SKLCGL,
  T:=SKLT,
  TB:=SKLTB,
  ST:=SKLST,
  OPM:=SKLMD;

  CONST
    SameDesignSet* = {T.Eplus, T.Eminus, T.Emsk, T.Eash, T.Elsh, T.Erot};

  TYPE
    HintsStdProcProc = PROCEDURE (args : T.Arg; VAR left, right : T.HintInfo; VAR result : SET);

  VAR
    HintsStdProc : ARRAY ST.SPlast - ST.SPbegin OF HintsStdProcProc;

  PROCEDURE StdPutReg(n : T.Arg; VAR left, right : T.HintInfo; VAR result : SET);
    VAR r : T.Arg; le : T.Expr;
  BEGIN
    r := n.next(T.Arg);
    le := n.arg;
    ASSERT((le.class = T.Nexpr) & (le.subcl = T.Econst));
  END StdPutReg;

  PROCEDURE StdGetReg(n : T.Arg; VAR left, right : T.HintInfo; VAR result : SET);
    VAR r : T.Arg; le : T.Expr;
  BEGIN
    r := n.next(T.Arg);
    le := n.arg;
    ASSERT((le.class = T.Nexpr) & (le.subcl = T.Econst));
  END StdGetReg;

  PROCEDURE StdMove(n : T.Arg; VAR left, right : T.HintInfo; VAR result : SET);
    VAR src, dst, len : T.Arg;
  BEGIN
    result := {};
    src := n;
    dst := src.next(T.Arg);
    len := dst.next(T.Arg);
    src.arg := T.NewLoadNode(src.arg, {1});
    dst.arg := T.NewLoadNode(dst.arg, {2});
    len.arg := T.NewLoadNode(len.arg, {3});
  END StdMove;

  PROCEDURE StdCopy(n : T.Arg; VAR left, right : T.HintInfo; VAR result : SET);
    VAR src, dst : T.Arg;
  BEGIN
    result  := {};
    src     := n;
    dst     := src.next(T.Arg);
    (* T.NewLoadNode() should not be used for the arguments to this function
     * because COPY() can include string constants, and character constants.
     *)
    src.arg := T.NewInterfereNode(src.arg, {1});
    dst.arg := T.NewInterfereNode(dst.arg, {2});
    (* Code generation also uses R3 to store the length.
     * It is not counted in the AST, since the AST reflects source. *)
  END StdCopy;

  PROCEDURE FuncCall(n : T.Expr; VAR left, right : T.HintInfo; VAR result : SET);
    VAR e : T.FuncCall; proc : T.Design; procno : SHORTINT;
  BEGIN
    e := n(T.FuncCall);
    proc := e.func;
    IF proc.subcl = T.Dstdproc THEN
      procno := proc.sym(ST.SymbolStdProc).procno;
      IF HintsStdProc[procno] # NIL THEN
        HintsStdProc[procno](e.args, left, right, result);
      END;
    END;
  END FuncCall;

  PROCEDURE Sassign(n : T.StmtList);
    VAR a : T.Assign; l : T.Expr;
  BEGIN
    a := n(T.Assign);
    l := a.lvalue;
    IF a.rvalue.regs # {} THEN
      a.lvalue := T.NewInterfereNode(a.lvalue, a.rvalue.regs);
    END;
  END Sassign;

  PROCEDURE InitExpr;
    VAR i : INTEGER;
  BEGIN
    T.ExprHints[T.Ecall - T.Ebegin] := FuncCall;
    i := 0;
    WHILE i < LEN(HintsStdProc) DO
      HintsStdProc[i] := NIL;
      INC(i);
    END;
    HintsStdProc[ST.getrfn - ST.SPbegin] := StdGetReg;
    HintsStdProc[ST.putrfn - ST.SPbegin] := StdPutReg;
    HintsStdProc[ST.movefn - ST.SPbegin] := StdMove;
    HintsStdProc[ST.copyfn - ST.SPbegin] := StdCopy;
  END InitExpr;

  PROCEDURE InitStmt;
  BEGIN
    T.StmtHints[T.Sassign - T.Sbegin] := Sassign;
  END InitStmt;

  PROCEDURE InitDsgn;
  END InitDsgn;

  PROCEDURE ModuleBegin*;
  BEGIN
    InitExpr;
    InitStmt;
    InitDsgn;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  END ModuleEnd;

END SKLTH.
