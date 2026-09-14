MODULE O3StdProc;
  IMPORT
    Config:=O3Config,
    Symtab:=O3Symtab,
    Scanner:=O3Scanner,
    AST:=O3TreeNode,
    ASTH:=O3TreeHelper,
    ConstExpr := O3ConstExpression,
    TA := O3TypeAllocate,
    E:=O3Errors;

  CONST (* check arg flags *)
    RV = 31; (* rvalue *) LV = 30; (* lvalue *) C = 29; (* constant *)
    EM = 28; (* exact match of type; CV & EM are mutually exclusive *)
    CV = 27; (* convert to type if not already the same; CV & EM are mutually exclusive *)
    O = 26; (* optional argument *)
    FirstParmFlag = 26;

  PROCEDURE ArgN(args : AST.Arg; n : SHORTINT) : AST.Arg;
    VAR arg : AST.Arg;
  BEGIN arg := AST.ArgumentN(args, n); RETURN arg;
  END ArgN;

  PROCEDURE Arg0(args : AST.Arg) : AST.Arg;
  BEGIN RETURN ArgN(args, 0);
  END Arg0;

  PROCEDURE Arg1(args : AST.Arg) : AST.Arg;
  BEGIN RETURN ArgN(args, 1);
  END Arg1;

  (*
    arg <=> arg to check
    f <=> argument flags for checking
    type <=> destination type
  *)
  PROCEDURE CheckArg(argument : AST.Arg; f : SET; type : Symtab.Type) : BOOLEAN;
    VAR
      b : BOOLEAN;
      ts : SET;
      arg : AST.Expr;
  BEGIN
    IF argument = NIL THEN
      IF O IN f THEN
        b := TRUE;
      ELSE
        b := FALSE;
        Config.Error(E.TooFewAparm);
      END;
    ELSE
      b := TRUE;
      arg := argument.arg;
      IF (RV IN f) & ((arg.class = AST.Ndsgn) &
                      ~(arg.subcl IN AST.RValueSet)) THEN
        b := FALSE;
        Config.Error(E.IllegalOperand);
      END;
      IF LV IN f THEN
        IF ~AST.LValue(arg) THEN
          b := FALSE;
          Config.Error(E.IncompatibleAssignment);
        ELSIF AST.readonly IN arg.flags THEN
          b := FALSE;
          Config.Error(E.ReadOnlyVariable);
        END;
      END;
      IF C IN f THEN
        arg := ConstExpr.FoldExpression(argument.arg, b);
        (* inv: b -> constant value *)
        (* inv: ~b -> not constant value *)
        IF b THEN
          argument.arg := arg;
        ELSE
          Config.Error(E.NotAConstant);
        END;
      END;

      ASSERT(f * {EM, CV} # {EM, CV});
      IF EM IN f THEN
        IF (AST.constant IN arg.flags) &
           (arg.type # type) &
           (arg.type.form IN f) THEN
          arg := ASTH.NewConvert(arg, type);
        END;
        IF arg.type # type THEN
          b := FALSE;
          Config.Error(E.IncompatibleAssignment);
        END;
      ELSIF (CV IN f) & (arg.type # type) THEN
        argument.arg := ASTH.NewConvert(arg, type);
      ELSIF ~(arg.type.form IN f) THEN
        b := FALSE;
        Config.Error(E.IncompatibleAssignment);
      END;
    END;
    RETURN b;
  END CheckArg;

  (* ResultType: create a procedure type with desired result for use in AST *)
  PROCEDURE ResultType(type : Symtab.Type) : Symtab.Type;
    VAR proc : Symtab.Procedure;
  BEGIN proc := Symtab.NewProcedureType(); proc.result := type; RETURN type;
  END ResultType;

  PROCEDURE New(x : AST.Expr; args : AST.Arg; VAR nofArgs : SHORTINT) : AST.StmtList;
    VAR
      argument : AST.Arg; arg : AST.Expr; base : Symtab.Type;
      arrOf : Symtab.Type; b : BOOLEAN; new : AST.StmtList;
      var : AST.Design; call : AST.Expr; tdarg : AST.Arg; td : Symtab.SymbolTypeDesc;
  BEGIN new := NIL;
    argument := Arg0(args); arg := argument.arg;
    IF (arg.class = AST.Ndsgn) & (arg.subcl IN AST.LValueSet) THEN
      IF ~(AST.readonly IN arg.flags) THEN
        IF arg.type.form = Symtab.pointer THEN
          var := arg(AST.Design);
          base := arg.type(Symtab.Pointer).to;
          IF base.form = Symtab.dynarr THEN
            arrOf := base(Symtab.Array).of;
            argument := Arg1(args);
            WHILE (argument # NIL) & (arrOf # NIL) DO arg := argument.arg;
              b := CheckArg(argument, {RV, CV} + Symtab.IntSet, Symtab.linttyp);
              IF b THEN (* argument checked out, do a bit more validation *)
                IF  (AST.constant IN arg.flags) & (arg.val.i0 < 0) THEN
                  Config.Error(E.IllegalValue);
                END;
              END;
              INC(nofArgs);
              IF arrOf.form = Symtab.dynarr THEN arrOf := arrOf(Symtab.Array).of;
              ELSE arrOf := NIL;
              END;
              argument := ArgN(args, nofArgs);
            END;
            IF arrOf # NIL THEN Config.Error(E.TooFewAparm);
            ELSE
              td := Symtab.GetTD(base.sym, var.type);
              tdarg := AST.NewArgNode(AST.NewDesignNode(AST.Ddarrdesc, td));
              tdarg := AST.BindArg(Arg1(args), tdarg);
              call := AST.NewFuncCallNode(x(AST.Design), tdarg);
              new := ASTH.NewAssign(var, call, var.type);
              call.type := var.type;
            END;
          ELSE (* record & static array *)
            IF base.form = Symtab.record THEN
              td := Symtab.GetTD(base.sym, base);
              tdarg := AST.NewArgNode(AST.NewDesignNode(AST.Drecdesc, td));
            ELSE
              td := Symtab.GetTD(base.sym, arg.type);
              tdarg := AST.NewArgNode(AST.NewDesignNode(AST.Darrdesc, td));
            END;
            call := AST.NewFuncCallNode(x(AST.Design), tdarg);
            new := ASTH.NewAssign(var, call, var.type);
            call.type := var.type;
          END;
        ELSE Config.Error(E.PointerRequired);
        END;
      ELSE Config.Error(E.ReadOnlyVariable);
      END;
    ELSE Config.Error(E.NotAVariable);
    END;
    RETURN new;
  END New;

  PROCEDURE MemRW(x : AST.Expr; args : AST.Arg; read : BOOLEAN);
    VAR b : BOOLEAN; v : SET;
  BEGIN
    b := CheckArg(Arg0(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    b := CheckArg(Arg1(args), {RV, EM, C} + Symtab.IntSet, Symtab.linttyp);
    IF read THEN v := {LV} ELSE v := {RV}; END;
    b := CheckArg(ArgN(args, 2), v + Symtab.BasicSet, NIL);
  END MemRW;

  PROCEDURE GetPut(x : AST.Expr; args : AST.Arg; get : BOOLEAN) : AST.StmtList;
    VAR b : BOOLEAN; v : SET;
      gp : AST.StmtList; var : AST.Design; call : AST.Expr; argument : AST.Arg;
  BEGIN
    b := CheckArg(Arg0(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    IF get THEN v := {LV}; ELSE v := {RV}; END;
    b := CheckArg(Arg1(args), v + Symtab.BasicSet, NIL);

    IF b & get THEN argument := Arg1(args);
      var := argument.arg(AST.Design);
      call := AST.NewFuncCallNode(x(AST.Design), args);
      gp := ASTH.NewAssign(var, call, var.type);

      (* set the call node type to be the destination
       * and chop off argument 1; it is now the assignment lhs
       *)
      call.type := var.type;
      args.next := NIL;
    ELSE gp := NIL;
    END;
    RETURN gp;
  END GetPut;

  PROCEDURE GetPutReg(x : AST.Expr; args : AST.Arg; get : BOOLEAN) : AST.StmtList;
    VAR arg : AST.Expr; b : BOOLEAN; f : SET;
      gp : AST.StmtList; var : AST.Design; call : AST.Expr; argument : AST.Arg;
  BEGIN
    argument := Arg0(args);
    b := CheckArg(argument, {RV, C, Symtab.sint, Symtab.int, Symtab.lint}, NIL);
    arg := argument.arg;
    IF get THEN f := {LV}; ELSE f := {RV}; END;
    argument := Arg1(args);
    IF argument # NIL THEN b := CheckArg(argument, f + Symtab.BasicSet, NIL);
    ELSE Config.Error(E.TooFewAparm);
    END;

    IF b & get THEN argument := Arg1(args);
      var := argument.arg(AST.Design);
      call := AST.NewFuncCallNode(x(AST.Design), args);
      gp := ASTH.NewAssign(var, call, var.type);

      (* set the call node type to be the destination
       * and chop off argument 1; it is now the assignment lhs
       *)
      call.type := var.type;
      args.next := NIL;
    ELSE gp := NIL;
    END;

    RETURN gp;
  END GetPutReg;

  (* Sysnew:
   * SYSTEM.NEW
   *
   *   Allocate a 'system' block that will be ignored by the GC.
   *
   *   The first argument must be an lvalue of type SYSTEM.PTR.
   *   It can be cast from another type, and therefore may be an
   *   Expression tree; at the heart there will be a designator.
   *
   *   The second parameter is the number of bytes to allocate.
   *)

  PROCEDURE Sysnew(x : AST.Expr; args : AST.Arg) : AST.StmtList;
    VAR
      argument : AST.Arg;
      b : BOOLEAN;
      new : AST.StmtList;
      var : AST.Design;
      call : AST.Expr;
      cast : AST.Node;
  BEGIN
    argument := Arg0(args);
    (* the backend should do an optimization: if the address
     * is required then the variable is not a leaf variable
     *)
    b := CheckArg(argument, {LV, Symtab.pointer}, NIL);
    b := b & CheckArg(Arg1(args), {RV, CV} + Symtab.IntSet, Symtab.linttyp);
    IF b THEN
      call := AST.NewFuncCallNode(x(AST.Design), args.next(AST.Arg));
      (* SYSTEM.NEW is special in that the first argument must be of
       * type SYSTEM.PTR.  It is likely that the argument will be a variable
       * cast via 'SYSTEM.VAL(SYSTEM.PTR, x)'.  The tree will be an expression
       * with a designator embedded.  The designator must be extracted.
       *)
      cast := argument.arg;
      WHILE (cast # NIL) & (cast.class = AST.Nexpr) DO
        ASSERT(cast.subcl = AST.Ecast);
        cast := cast(AST.MExpr).op;
      END;
      ASSERT((cast # NIL) & (cast.class = AST.Ndsgn));
      var := cast(AST.Design);
      new := ASTH.NewAssign(var, call, var.type);
      (* set the call node type to be the destination
       * and chop off argument 1; it is now the assignment lhs
       *)
      call.type := var.type;
      args.next := NIL;
    ELSE new := NIL;
    END;
    RETURN new;
  END Sysnew;

  PROCEDURE Move(x : AST.Expr; args : AST.Arg);
    VAR b : BOOLEAN;
  BEGIN
    b := CheckArg(Arg0(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    b := CheckArg(Arg1(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    b := CheckArg(ArgN(args, 2), {RV, CV} + Symtab.IntSet, Symtab.linttyp);
  END Move;

  PROCEDURE AssertHalt(arg : AST.Arg; s : SET) : BOOLEAN;
    VAR b : BOOLEAN; i : LONGINT;
  BEGIN
    b := CheckArg(arg, {RV, C} + Symtab.IntSet + s, NIL);
    IF b THEN i := arg.arg.val.i0;
      IF (i < Config.MinHaltValue) OR (i > Config.MaxHaltValue) THEN
        b := FALSE; Config.Error(E.IllegalHalt);
      END;
    END;
    RETURN b;
  END AssertHalt;

  PROCEDURE Halt(x : AST.Expr; args : AST.Arg) : AST.StmtList;
    VAR argument : AST.Arg; arg : AST.Expr; b : BOOLEAN;
  BEGIN
    argument := Arg0(args); b := AssertHalt(argument, {});
    IF ~b THEN arg := ASTH.NewIntConst(Config.HaltAssert);
    ELSE arg := argument.arg;
    END;
    RETURN AST.NewHaltNode(ASTH.NewBoolConst(FALSE), arg);
  END Halt;

  PROCEDURE Assert(x : AST.Expr; args : AST.Arg) : AST.StmtList;
    VAR b : BOOLEAN; a0, a1 : AST.Arg; arg0, arg1 : AST.Expr;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV, EM, Symtab.bool}, Symtab.booltyp);
    IF ~b THEN arg0 := ASTH.NewBoolConst(TRUE); ELSE arg0 := a0.arg; END;
    a1 := Arg1(args);
    IF a1 # NIL THEN b := AssertHalt(a1, {O});
      IF b THEN arg1 := a1.arg;
      ELSE arg1 := ASTH.NewIntConst(Config.HaltAssert);
      END;
    ELSE arg1 := ASTH.NewIntConst(Config.HaltAssert);
    END;
    RETURN AST.NewHaltNode(arg0, arg1);
  END Assert;

  PROCEDURE IncDec(x : AST.Expr; args : AST.Arg; inc : BOOLEAN) : AST.StmtList;
    VAR a0, a1 : AST.Arg; b : BOOLEAN; type : Symtab.Type; expr : AST.Expr; op : SHORTINT;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {LV} + Symtab.IntSet, NIL);
    IF b THEN type := a0.arg.type; a1 := Arg1(args);
      b := CheckArg(a1, {CV, O, RV} + {type.form}, type);
      IF ~b OR (a1 =  NIL) THEN (* default <=> 1 *)
        args.next := AST.NewArgNode(ASTH.NewIntConst(1));  a1 := Arg1(args); a1.arg.type := type;
      END;

      IF inc THEN op := AST.Eplus; ELSE op := AST.Eminus;  END;
      expr := AST.NewDExprNode(op, a0.arg, a1.arg, type);
      RETURN AST.NewAssignNode(a0.arg(AST.Design), expr);
    ELSE RETURN AST.NewNullStmtNode();
    END;
  END IncDec;

  PROCEDURE InclExcl(x : AST.Expr; args : AST.Arg) : AST.StmtList;
    VAR a1 : AST.Arg; b : BOOLEAN; arg : AST.Expr;
      ie : AST.StmtList; var : AST.Design; call : AST.Expr; argument : AST.Arg;
  BEGIN
    b := CheckArg(Arg0(args), {LV, EM, Symtab.set}, Symtab.settyp);
    a1 := Arg1(args); b := CheckArg(a1, {RV} + Symtab.IntSet, NIL);
    IF b THEN
      arg := a1.arg;
      IF arg.type # Symtab.sinttyp THEN
        a1.arg := ASTH.NewConvert(arg, Symtab.sinttyp);
      END;
    END;

    IF b THEN argument := Arg0(args);
      var := argument.arg(AST.Design);
      call := AST.NewFuncCallNode(x(AST.Design), args);
      ie := ASTH.NewAssign(var, call, var.type);

      (* set the call node type to be the destination *)
      call.type := var.type;
    ELSE ie := NIL;
    END;

    RETURN ie;
  END InclExcl;

  PROCEDURE Copy(x : AST.Expr; args : AST.Arg) : AST.StmtList;
    VAR argument : AST.Arg; arg : AST.Expr; b : BOOLEAN;
    copy : AST.StmtList; src, dst : AST.Arg; s : AST.Expr; str : Scanner.String;
  BEGIN b := TRUE;
    argument := Arg0(args);
    IF argument # NIL THEN arg := argument.arg;
      IF arg.type = Symtab.chartyp THEN (* ok *)
      ELSIF arg.type = Symtab.stringtyp THEN (* ok *)
      ELSIF (arg.type.form IN {Symtab.array, Symtab.dynarr, Symtab.openarr})
          & (arg.type(Symtab.Array).of = Symtab.chartyp) THEN  (* ok *)
      ELSE Config.Error(E.IllegalOperand); b := FALSE;
      END;

      argument := Arg1(args);
      IF argument # NIL THEN arg := argument.arg;
        IF (arg.class = AST.Ndsgn) & (arg.subcl IN AST.LValueSet) THEN
          IF ~(AST.readonly IN arg.flags) THEN
            IF ~(arg.type.form IN {Symtab.array, Symtab.dynarr, Symtab.openarr})
            OR ~(arg.type(Symtab.Array).of.form = Symtab.char) THEN
              Config.Error(E.IllegalOperand); b := FALSE;
            END;
          ELSE Config.Error(E.ReadOnlyVariable); b := FALSE;
          END;
        END;
      ELSE Config.Error(E.TooFewAparm); b := FALSE;
      END;
    ELSE Config.Error(E.TooFewAparm); b := FALSE;
    END;

    IF b THEN src := Arg0(args); dst := Arg1(args); s := src.arg;
      IF src.type = Symtab.chartyp THEN str[0] := CHR(s.val.i0); str[1] := 0X;
        s := ASTH.NewDesign(Symtab.MakeStringConst(str, 1));
      END;
      copy := ASTH.NewAssign(dst.arg(AST.Design), s, dst.arg.type);
    ELSE copy := NIL;
    END;
    RETURN copy;
  END Copy;

  PROCEDURE Finalize(x : AST.Expr; args : AST.Arg);
    VAR argument : AST.Arg; arg : AST.Expr; recType : Symtab.Type;
      at : Symtab.Procedure; p : Symtab.Symbol;
  BEGIN
    argument := Arg0(args);
    IF argument # NIL THEN arg := argument.arg;
      IF (arg.class = AST.Ndsgn) & (arg.subcl = AST.Dtype) & (arg.type.form = Symtab.record) THEN
        recType := arg.type; argument :=  Arg1(args);
        IF argument # NIL THEN arg := argument.arg;
          (* arg must be a procedure taking one non-var parameter of type
           * POINTER TO recType and returning nothing
           *)
          IF (arg.class = AST.Ndsgn)
           & (arg.subcl = AST.Dproc)
           & (arg(AST.Design).sym # NIL)
           & (arg(AST.Design).sym.mnolev = 0) THEN
            at := arg.type(Symtab.Procedure);
            IF at.result = Symtab.notyp THEN p := Symtab.FirstParm(at);
              IF p # NIL THEN
                IF (p.kind # Symtab.par)
                OR (p.type.form # Symtab.pointer)
                OR (p.type(Symtab.Pointer).to # recType) THEN Config.Error(E.ParmMismatch); END;
              ELSE Config.Error(E.ParamCountsDiffer);
              END;
            ELSE Config.Error(E.ResultMismatch);
            END;
          ELSE Config.Error(E.MustBeGlobalProc);
          END;
        ELSE Config.Error(E.TooFewAparm);
        END;
      ELSE Config.Error(E.NotARecordType);
      END;
    ELSE Config.Error(E.TooFewAparm);
    END;
  END Finalize;

  (* SYSTEM.BITR(x : LONGINT; bit : integer) : BOOLEAN *)
  (* SYSTEM.BITS(x : LONGINT; bit : integer) : BOOLEAN *)
  PROCEDURE BitSR(x : AST.Expr; args : AST.Arg);
    VAR b : BOOLEAN;
  BEGIN ASSERT(x.type.form = Symtab.procedure);
    b := CheckArg(Arg0(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    b := CheckArg(Arg1(args), {RV} + Symtab.IntSet, NIL);
  END BitSR;

  PROCEDURE StdProcCall*(x : AST.Design; args : AST.Arg) : AST.StmtList;
    VAR n : AST.Node; nofArgs : SHORTINT; targ : AST.Expr;
      std : AST.StmtList;

  BEGIN nofArgs := 2; std := NIL;
    CASE x.sym(Symtab.SymbolStdProc).procno OF
    |  Symtab.newfn: nofArgs := 1; std := New(x, args, nofArgs);
    |  Symtab.getfn: std := GetPut(x, args, TRUE);
    |  Symtab.putfn: std := GetPut(x, args, FALSE);
    |  Symtab.memrfn: MemRW(x, args, TRUE); nofArgs := 3;
    |  Symtab.memwfn: MemRW(x, args, FALSE); nofArgs := 3;
    |  Symtab.getrfn: std := GetPutReg(x, args, TRUE);
    |  Symtab.putrfn: std := GetPutReg(x, args, FALSE);
    |  Symtab.sysnewfn: std := Sysnew(x, args);
    |  Symtab.movefn: Move(x, args); nofArgs := 3;
    |  Symtab.haltfn: std := Halt(x, args); nofArgs := 1
    |  Symtab.assertfn: std := Assert(x, args);
    |  Symtab.incfn: std := IncDec(x, args, TRUE);
    |  Symtab.decfn: std := IncDec(x, args, FALSE);
    |  Symtab.inclfn: std := InclExcl(x, args);
    |  Symtab.exclfn: std := InclExcl(x, args);
    |  Symtab.copyfn: std := Copy(x, args);
    |  Symtab.finalizefn: Finalize(x, args);
    |  Symtab.bitrfn, Symtab.bitsfn: BitSR(x, args);
    ELSE Config.Error(E.StdProcedure);
    END;

    IF std = NIL THEN std := AST.NewProcCallNode(AST.NewFuncCallNode(x, args)); END;

    targ := AST.ArgN(args, nofArgs);
    IF targ # NIL THEN Config.Error(E.TooManyAparm); END;
    RETURN std;
  END StdProcCall;

  PROCEDURE Abs(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; b : BOOLEAN; arg : AST.Expr;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV} + Symtab.NumSet, NIL);
    IF b THEN x.type := ResultType(a0.arg.type);
    ELSE x.type := Symtab.undftyp;
    END;
    RETURN x;
  END Abs;

  PROCEDURE Cap(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; arg : AST.Expr; b : BOOLEAN;
  BEGIN a0 := Arg0(args); b := CheckArg(a0, {RV, EM, Symtab.char}, Symtab.chartyp);
    x.type := Symtab.chartyp; RETURN x;
  END Cap;

  PROCEDURE Odd(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR b : BOOLEAN; a0 : AST.Arg; arg : AST.Expr;
  BEGIN a0 := Arg0(args); b := CheckArg(a0, {RV} + Symtab.IntSet, NIL);
    x.type := Symtab.booltyp; RETURN x;
  END Odd;

  PROCEDURE Adr(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; b : BOOLEAN;
  BEGIN a0 := Arg0(args);
    b := CheckArg(a0,
                  {LV, Symtab.bool..Symtab.set, Symtab.pointer, Symtab.procedure..Symtab.record},
                  NIL);
    IF b THEN ASTH.CheckLeaf(a0.arg, FALSE); END;
    x.type := Symtab.linttyp; RETURN x;
  END Adr;

  PROCEDURE Cc(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; arg : AST.Expr; b : BOOLEAN;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV, C} + Symtab.IntSet, NIL);
    x.type := Symtab.booltyp; RETURN x;
  END Cc;

  PROCEDURE Shifts(x : AST.Expr; args : AST.Arg; fn : SHORTINT) : AST.Expr;
    VAR a0, a1 : AST.Arg; arg, arg2 : AST.Expr; b, b2 : BOOLEAN;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV} + Symtab.IntSet, NIL);
    a1 := Arg1(args); b2 := CheckArg(a1, {RV} + Symtab.IntSet, NIL);
    IF b & b2 THEN
      (* downcast the shift count to a SHORTINT *)
      arg2 := a1.arg;
      IF arg2.type.form = Symtab.lint THEN
        arg2 := ASTH.NewConvert(arg2, Symtab.inttyp);
      END;
      IF arg2.type.form = Symtab.int THEN
        arg2 := ASTH.NewConvert(arg2, Symtab.sinttyp);
      END;
      a1.arg := arg2; (* ensure that the new convert nodes are put into the tree *)

      (* upcast the shifted operand to a LONGINT *)
      arg := a0.arg;
      IF arg.type.form = Symtab.sint THEN
        arg := ASTH.NewConvert(arg, Symtab.linttyp);
      END;
      IF arg.type.form = Symtab.int THEN
        arg := ASTH.NewConvert(arg, Symtab.linttyp);
      END;
      a0.arg := arg; (* ensure that the new convert nodes are put into the tree *)
    END;
    x.type := Symtab.linttyp;
    RETURN x;
  END Shifts;

  PROCEDURE Len(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0, d0 : AST.Arg; arg : AST.Expr; i : LONGINT; t : Symtab.Type; b : BOOLEAN;
  BEGIN (* or 2 *)
    a0 := Arg0(args); b := CheckArg(a0, {RV, Symtab.array, Symtab.dynarr, Symtab.openarr}, NIL);
    IF b THEN arg := a0.arg;
      d0 := Arg1(args);
      b := CheckArg(d0, {O, RV, C} + Symtab.IntSet, NIL);
      (* inv: d0 <-> user specified dimension *)
      IF b & (d0 # NIL) THEN i := d0.arg.val.i0;
      ELSE i := 0; args.next := AST.NewArgNode(ASTH.NewIntConst(0));
      END;
      d0 := Arg1(args); ASSERT(d0 # NIL);
      IF d0.type # Symtab.linttyp THEN
        d0.arg := ASTH.NewConvert(d0.arg, Symtab.linttyp);
        d0.arg := ConstExpr.FoldExpression(d0.arg, b);
      END;

      t := arg.type;
      WHILE (i > 0) & (t # NIL) & (t.form IN {Symtab.array, Symtab.dynarr, Symtab.openarr}) DO
        DEC(i); t := t(Symtab.Array).of;
      END;

      IF (t # NIL) & (i >= 0) THEN
        IF t.form = Symtab.array THEN
          RETURN ASTH.NewIntConst(t(Symtab.Array).n); (* else dynarr *)
        END;
      ELSE Config.Error(E.InvalidLen);
      END;
    END;
    x.type := Symtab.linttyp; RETURN x;
  END Len;

  (* SYSTEM.BIT(x : LONGINT; bit : integer) : BOOLEAN *)
  PROCEDURE Bit(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR b : BOOLEAN;
  BEGIN
    b := CheckArg(Arg0(args), {RV, EM} + Symtab.IntSet, Symtab.linttyp);
    b := CheckArg(Arg1(args), {RV} + Symtab.IntSet, NIL);
    x.type := Symtab.booltyp; RETURN x;
  END Bit;

  PROCEDURE Ord(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR b : BOOLEAN; a0 : AST.Arg;
  BEGIN
    a0 := Arg0(args);
    b := CheckArg(a0, {RV, EM, Symtab.char}, Symtab.chartyp);
    IF b THEN
      RETURN ASTH.NewConvert(a0.arg, Symtab.inttyp);
    ELSE
      RETURN x;
    END;
  END Ord;

  (* entier is replaced by a convert node *)
  PROCEDURE Entier(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR b : BOOLEAN; a0 : AST.Arg;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV, Symtab.real, Symtab.lreal}, NIL);
    IF b THEN RETURN ASTH.NewConvert(a0.arg, Symtab.linttyp);
    ELSE x.type := Symtab.linttyp; RETURN x;
    END;
  END Entier;

  PROCEDURE MinMax(x : AST.Expr; args : AST.Arg; op : SHORTINT) : AST.Expr;
    VAR a0 : AST.Arg; arg : AST.Expr; f : SHORTINT; result : Symtab.Type;
  BEGIN a0 := Arg0(args);
    IF (a0 # NIL) THEN arg := a0.arg;
      IF (arg.subcl = AST.Dtype) THEN f := arg.type.form;
        CASE f OF
        | Symtab.bool, Symtab.byte, Symtab.char,
          Symtab.sint, Symtab.int, Symtab.lint, Symtab.real, Symtab.lreal:
          x.type := arg.type;
          RETURN x;
        | Symtab.set:
          x.type := Symtab.inttyp;
          RETURN x;
        ELSE Config.Error(E.IllegalOperand);
        END;
      ELSE Config.Error(E.NotAType);
      END;
    ELSE Config.Error(E.TooFewAparm);
    END;
    RETURN ASTH.NewIntConst(0);
  END MinMax;

  PROCEDURE Chr(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; b : BOOLEAN;
  BEGIN
    a0 := Arg0(args);
    b := CheckArg(a0, {RV} + Symtab.IntSet, NIL);
    IF b THEN
      RETURN ASTH.NewConvert(a0.arg, Symtab.chartyp);
    ELSE
      RETURN x;
    END;
  END Chr;

  PROCEDURE Short(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 : AST.Arg; arg : AST.Expr; dest : Symtab.Type; b : BOOLEAN;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV, Symtab.int, Symtab.lint, Symtab.lreal}, NIL);
    IF b THEN arg := a0.arg;
      CASE arg.type.form OF
      |  Symtab.int: dest := Symtab.sinttyp;
      |  Symtab.lint: dest := Symtab.inttyp;
      |  Symtab.lreal: dest := Symtab.realtyp;
      END;
      RETURN ASTH.NewConvert(arg, dest);
    END;
    x.type := Symtab.undftyp; RETURN x;
  END Short;

  PROCEDURE Long(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR a0 :AST.Arg; arg : AST.Expr; dest : Symtab.Type; b : BOOLEAN;
  BEGIN
    a0 := Arg0(args); b := CheckArg(a0, {RV, Symtab.sint, Symtab.int, Symtab.real}, NIL);
    IF b THEN arg := a0.arg;
      CASE arg.type.form OF
      |  Symtab.sint: dest := Symtab.inttyp;
      |  Symtab.int: dest := Symtab.linttyp;
      |  Symtab.real: dest := Symtab.lrltyp;
      END;
      RETURN ASTH.NewConvert(arg, dest);
    END;
    x.type := Symtab.undftyp; RETURN x;
  END Long;

  PROCEDURE Size(x : AST.Expr; args : AST.Arg) : AST.Expr;
    CONST SizeableTypes = {Symtab.bool, Symtab.byte, Symtab.char,
                           Symtab.sint, Symtab.int, Symtab.lint,
                           Symtab.real, Symtab.lreal, Symtab.set,
                           Symtab.pointer, Symtab.procedure, Symtab.array, Symtab.record};
    VAR a0 : AST.Arg; arg : AST.Expr;
  BEGIN a0 := Arg0(args);
    IF a0 # NIL THEN arg := a0.arg;
      IF arg.subcl = AST.Dtype THEN
        IF arg.type.form IN SizeableTypes THEN TA.Size(arg.type);
          (* using the size of a type causes a dependency on the private fingerprint *)
          INCL(arg.type.flags, Symtab.pvused); x.type := Symtab.IntTypeOf(arg.type.size);
          RETURN x;
        ELSE Config.Error(E.IllegalOperand);
        END;
      ELSE Config.Error(E.NotAType);
      END;
    ELSE Config.Error(E.TooFewAparm);
    END;
    RETURN x;
  END Size;

  PROCEDURE Val(x : AST.Expr; args : AST.Arg) : AST.Expr;
    VAR t0, a0 : AST.Arg; type, arg : AST.Expr;
  BEGIN
    t0 := Arg0(args);
    IF t0 # NIL THEN type := t0.arg;
      ASTH.CheckLeaf(type, FALSE);
      IF (type.class = AST.Ndsgn) & (type(AST.Design).sym.kind = Symtab.type) THEN
        a0 := Arg1(args);
        IF a0 # NIL THEN arg := a0.arg;
          IF (arg.class # AST.Ndsgn)
          OR (arg.subcl IN AST.RValueSet) THEN arg := AST.NewCastNode(type.type, arg);
            RETURN arg;
          ELSE Config.Error(E.IllegalOperand);
          END;
        ELSE Config.Error(E.TooFewAparm);
        END;
      ELSE Config.Error(E.IncompatibleAssignment);
      END;
    ELSE Config.Error(E.TooFewAparm);
    END;
    RETURN x;
  END Val;

  PROCEDURE StdFuncCall*(x : AST.Design; args : AST.Arg) : AST.Expr;
    VAR fn, nofArgs : SHORTINT; std, targ : AST.Expr;

  BEGIN
    fn := x.sym(Symtab.SymbolStdProc).procno; std := AST.NewFuncCallNode(x, args); nofArgs := 1;
    CASE fn OF
    |  Symtab.absfn: std := Abs(std, args);
    |  Symtab.capfn: std := Cap(std, args);
    |  Symtab.oddfn: std := Odd(std, args);
    |  Symtab.adrfn: std := Adr(std, args);
    |  Symtab.ccfn: std := Cc(std, args);
    |  Symtab.ashfn: std := Shifts(std, args, Symtab.ashfn); nofArgs := 2;
    |  Symtab.lshfn: std := Shifts(std, args, Symtab.lshfn); nofArgs := 2;
    |  Symtab.rotfn: std := Shifts(std, args, Symtab.rotfn); nofArgs := 2;
    |  Symtab.lenfn: std := Len(std, args); nofArgs := 2;
    |  Symtab.ordfn: std := Ord(std, args);
    |  Symtab.entierfn: std := Entier(std, args);
    |  Symtab.minfn: std := MinMax(std, args, Symtab.minfn);
    |  Symtab.maxfn: std := MinMax(std, args, Symtab.maxfn);
    |  Symtab.chrfn: std := Chr(std, args);
    |  Symtab.shortfn: std := Short(std, args);
    |  Symtab.longfn: std := Long(std, args);
    |  Symtab.sizefn: std := Size(std, args);
    |  Symtab.valfn: std := Val(x, args); nofArgs := 2;
    |  Symtab.bitfn: std := Bit(std, args); nofArgs := 2;
    ELSE Config.Error(E.StdProcedure);
    END;

    targ := AST.ArgN(args, nofArgs);
    IF targ # NIL THEN Config.Error(E.TooManyAparm); END;
    RETURN std;
  END StdFuncCall;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleEnd;

  PROCEDURE Init;
  BEGIN ASSERT(FirstParmFlag > Symtab.nofTypes); Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;

BEGIN Init;
END O3StdProc.
