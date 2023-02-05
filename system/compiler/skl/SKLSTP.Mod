MODULE SKLSTP;
IMPORT
  ST:=SKLST,
  TU:=SKLTU,
  TB:=SKLTB,
  T:=SKLT,
  OPM:=SKLMD,
  EL:=SKLERR,
  CGL:=SKLCGL;

CONST (* check arg flags *)
  RV = 31; (* rvalue *)
  LV = 30; (* lvalue *)
  C = 29; (* constant *)
  EM = 28; (* exact match of type; CV & EM are mutually exclusive *)
  CV = 27; (* convert to type; CV & EM are mutually exclusive *)
  O = 26; (* optional argument *)


PROCEDURE err(n : INTEGER);
BEGIN
  OPM.err(n);
END err;


PROCEDURE ArgN(args : T.Arg; n : SHORTINT) : T.Arg;
  VAR
    arg : T.Arg;
BEGIN
  arg := T.ArgumentN(args, n);
  RETURN arg;
END ArgN;


PROCEDURE Arg0(args : T.Arg) : T.Arg;
BEGIN
  RETURN ArgN(args, 0);
END Arg0;


PROCEDURE Arg1(args : T.Arg) : T.Arg;
BEGIN
  RETURN ArgN(args, 1);
END Arg1;


PROCEDURE ActualArg(argument : T.Arg) : T.Expr; (* bypass Einterfere &
                                                 * Eload nodes *)
  VAR
    arg : T.Node;
BEGIN
  arg := argument.arg;
  WHILE (arg.class = T.Nexpr) & (arg.subcl IN {T.Einterfere, T.Eload}) DO
    arg := arg.next;
  END;
  RETURN arg(T.Expr);
END ActualArg;


(*
   arg <=> arg to check
   f <=> argument flags for checking
   type <=> destination type
*)
PROCEDURE CheckArg(argument : T.Arg; f : SET; type : ST.Type) : BOOLEAN;
  VAR
    b : BOOLEAN;
    ts : SET;
    arg : T.Expr;
BEGIN
  IF argument = NIL THEN
    IF O IN f THEN
      b := TRUE;
    ELSE
      b := FALSE;
      err(EL.TooFewAparm);
    END;
  ELSE
    b := TRUE;
    arg := argument.arg;
    IF (arg.class = T.Nmisc) & (arg.subcl = T.Merror) THEN
      b := FALSE;
      IF ~(O IN f) THEN
        err(EL.TooFewAparm);
      END;
    ELSE
      IF (RV IN f) & ((arg.class = T.Ndsgn) & ~(arg.subcl IN T.RValueSet)) THEN
        b := FALSE;
        err(EL.IllegalOperand);
      END;
      IF LV IN f THEN
        IF ~T.LValue(arg) THEN
          b := FALSE;
          err(EL.IncompatibleAssignment);
        ELSIF T.readonly IN arg.flags THEN
          b := FALSE;
          err(EL.ReadOnlyVariable);
        END;
      END;
      IF (C IN f) & ~(T.constant IN arg.flags) THEN
        b := FALSE;
        err(EL.NotAConstant);
      END;
      (*
         (* EM & CV mutually exclusive since both use type parm *)
         ASSERT(f * {EM, CV} # {EM, CV});
       *)
      IF EM IN f THEN
        IF (T.constant IN arg.flags) &
           (arg.type # type) & (arg.type.form IN f) THEN
          arg := TB.Convert(arg, type);
        END;
        IF arg.type # type THEN
          b := FALSE;
          err(EL.IncompatibleAssignment);
        END;
      ELSIF CV IN f THEN
        argument.arg := TB.NewConvert(arg, type);
      ELSIF ~(arg.type.form IN f) THEN
        b := FALSE;
        err(EL.IncompatibleAssignment);
      END;
    END;
  END;
  RETURN b;
END CheckArg;


PROCEDURE ResultType(type : ST.Type) : ST.Type;
  VAR
    proc : ST.Procedure;
BEGIN
  proc := ST.NewProcedureType();
  proc.result := type;
  RETURN type;
END ResultType;


PROCEDURE New(x : T.Expr; args : T.Arg; VAR nofArgs : SHORTINT);
  VAR
    argument : T.Arg;
    arg : T.Expr;
    base : ST.Type;
    arrOf : ST.Type;
    b : BOOLEAN;
BEGIN
  argument := Arg0(args);
  arg := argument.arg;
  IF (arg.class = T.Ndsgn) & (arg.subcl IN T.LValueSet) THEN
    IF ~(T.readonly IN arg.flags) THEN
      IF arg.type.form = ST.pointer THEN
        IF OPM.NEWusingAdr THEN
          TB.CheckLeaf(arg, TRUE);
        END;
        base := arg.type(ST.Pointer).to;
        IF base.form = ST.dynarr THEN
          arrOf := base(ST.Array).of;
          argument := Arg1(args);
          WHILE (argument # NIL) & (arrOf # NIL) DO
            arg := argument.arg;
            b := CheckArg(argument, {RV, CV} + ST.IntSet, ST.linttyp);
            IF b & (T.constant IN arg.flags) &
               ((arg.val.i0 <= 0) OR (arg.val.i0 > OPM.MaxIndex)) THEN
              err(EL.IllegalValue);
            END;
            INC(nofArgs);
            IF arrOf.form = ST.dynarr THEN
              arrOf := arrOf(ST.Array).of;
            ELSE
              arrOf := NIL;
            END;
            argument := ArgN(args, nofArgs);
          END;
          IF arrOf # NIL THEN
            err(EL.TooFewAparm);
          END;
        (*
        ELSE
          record & static array do not need extra parameters
         *)
        END;
      ELSE
        err(EL.IllegalOperand);
      END;
    ELSE
      err(EL.ReadOnlyVariable);
    END;
  ELSE
    err(EL.NotAVariable);
  END;
END New;


PROCEDURE MemRW(x : T.Expr; args : T.Arg; read : BOOLEAN);
  VAR
    b : BOOLEAN;
    v : SET;
BEGIN
  b := CheckArg(Arg0(args), {RV, EM} + ST.IntSet, ST.linttyp);
  b := CheckArg(Arg1(args), {RV, EM, C} + ST.IntSet, ST.linttyp);
  IF read THEN
    v := {LV} ELSE
    v := {RV};
  END;
  b := CheckArg(ArgN(args, 2), v + ST.BasicSet, NIL);
END MemRW;


PROCEDURE GetPut(x : T.Expr; args : T.Arg; get : BOOLEAN);
  VAR
    b : BOOLEAN;
    v : SET;
BEGIN
  b := CheckArg(Arg0(args), {RV, EM} + ST.IntSet, ST.linttyp);
  IF get THEN
    v := {LV}; ELSE
    v := {RV};
  END;
  b := CheckArg(Arg1(args), v + ST.BasicSet, NIL);
END GetPut;


PROCEDURE GetPutReg(x : T.Expr; args : T.Arg; fn : SHORTINT);
  VAR
    argument : T.Arg;
    arg : T.Expr;
    b : BOOLEAN;
    f : SET;
BEGIN
  argument := Arg0(args);
  b := CheckArg(argument, {RV, C, ST.sint, ST.int, ST.lint}, NIL);
  arg := argument.arg;
  IF b & ((arg.val.i0 < OPM.MinRegNr) OR (arg.val.i0 > OPM.MaxRegNr)) THEN
    err(EL.IllegalValue);
  END;
  IF fn = ST.putrfn THEN
    f := {RV};
  ELSE
    f := {LV};
  END;
  argument := Arg1(args);
  IF argument # NIL THEN
    b := CheckArg(argument, f + ST.BasicSet, NIL);
  ELSE
    err(EL.TooFewAparm);
  END;
END GetPutReg;


PROCEDURE Sysnew(x : T.Expr; args : T.Arg);
  VAR
    argument : T.Arg;
    b : BOOLEAN;
BEGIN
  argument := Arg0(args);
  IF (argument # NIL) & OPM.NEWusingAdr THEN
    TB.CheckLeaf(argument.arg, TRUE);
  END;
  b := CheckArg(argument, {LV, ST.pointer}, NIL);
  b := CheckArg(Arg1(args), {RV, CV} + ST.IntSet, ST.linttyp);
END Sysnew;


PROCEDURE Move(x : T.Expr; args : T.Arg);
  VAR
    b : BOOLEAN;
BEGIN
  b := CheckArg(Arg0(args), {RV, EM} + ST.IntSet, ST.linttyp);
  b := CheckArg(Arg1(args), {RV, EM} + ST.IntSet, ST.linttyp);
  b := CheckArg(ArgN(args, 2), {RV, CV} + ST.IntSet, ST.linttyp);
END Move;


PROCEDURE AssertHalt(arg : T.Arg; s : SET) : BOOLEAN;
  VAR
    b : BOOLEAN;
    i : LONGINT;
BEGIN
  b := CheckArg(arg, {RV, C} + ST.IntSet + s, NIL);
  IF b THEN
    i := arg.arg.val.i0;
    IF (i < OPM.MinHaltNr) OR (i > OPM.MaxHaltNr) THEN
      b := FALSE;
      err(EL.IllegalHalt);
    END;
  END;
  RETURN b;
   END AssertHalt;


PROCEDURE Halt(x : T.Expr; args : T.Arg) : T.StmtList;
  VAR
    argument : T.Arg;
    arg : T.Expr;
    b : BOOLEAN;
BEGIN
  argument := Arg0(args);
  b := AssertHalt(argument, {});
  IF ~b THEN
    arg := TB.NewIntConst(OPM.HaltAssert);
  ELSE
    arg := argument.arg;
  END;
  RETURN T.NewHaltNode(TB.NewBoolConst(FALSE), arg);
END Halt;


PROCEDURE Assert(x : T.Expr; args : T.Arg) : T.StmtList;
  VAR
    b : BOOLEAN;
    a0, a1 : T.Arg;
    arg0, arg1 : T.Expr;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, EM, ST.bool}, ST.booltyp);
  IF ~b THEN
    arg0 := TB.NewBoolConst(TRUE); ELSE
    arg0 := a0.arg;
  END;
  a1 := Arg1(args);
  IF a1 # NIL THEN
    b := AssertHalt(a1, {O});
    IF b THEN
      arg1 := a1.arg;
    ELSE
      arg1 := TB.NewIntConst(OPM.HaltAssert);
    END;
  ELSE
    arg1 := TB.NewIntConst(OPM.HaltAssert);
  END;
  RETURN T.NewHaltNode(arg0, arg1);
END Assert;


PROCEDURE IncDec(x : T.Expr; args : T.Arg; inc : BOOLEAN) : T.StmtList;
  VAR
    a0, a1 : T.Arg;
    b : BOOLEAN;
  type : ST.Type;
  expr : T.Expr;
  op : SHORTINT;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {LV} + ST.IntSet, NIL);
  IF b THEN
    type := a0.arg.type;
    a1 := Arg1(args);
    b := CheckArg(a1, {EM, O, RV} + ST.IntSet, type);
    IF ~b OR (a1 =  NIL) THEN
      (* default <=> 1 *)
      args.next := T.NewArgNode(TB.NewIntConst(1));
      a1 := Arg1(args);
      a1.arg.type := type;
    END;

    IF inc THEN
      op := T.Eplus; ELSE
      op := T.Eminus;
    END;
    expr := T.NewDExprNode(op, a0.arg, a1.arg, type);
    RETURN T.NewAssignNode(a0.arg(T.Design), expr);
  ELSE
    RETURN T.NewNullStmtNode();
  END;
END IncDec;


PROCEDURE InclExcl(x : T.Expr; args : T.Arg);
  VAR
    a1 : T.Arg;
    b : BOOLEAN;
    arg : T.Expr;
BEGIN
  b := CheckArg(Arg0(args), {LV, EM, ST.set}, ST.settyp);
  a1 := Arg1(args);
  b := CheckArg(a1, {RV} + ST.IntSet, NIL);
  IF b THEN
    arg := a1.arg;
    IF (T.constant IN arg.flags) & ((arg.val.i0 < 0) OR
                                    (arg.val.i0 > OPM.MaxSet)) THEN
      err(EL.IllegalValue);
    END;
  END;
END InclExcl;


PROCEDURE Copy(x : T.Expr; args : T.Arg);
  VAR
    argument : T.Arg;
    arg : T.Expr;
BEGIN
  argument := Arg0(args);
  IF argument # NIL THEN
    arg := argument.arg;
    IF arg.type = ST.chartyp THEN
      (* ok *)
    ELSIF arg.type = ST.stringtyp THEN
      (* ok *)
    ELSIF (arg.type.form IN {ST.array, ST.dynarr}) &
          (arg.type(ST.Array).of = ST.chartyp) THEN
      (* ok *)
    ELSE
      err(EL.IllegalOperand);
    END;
    argument := Arg1(args);
    IF arg # NIL THEN
      arg := ActualArg(argument);
      IF (arg.class = T.Ndsgn) & (arg.subcl IN T.LValueSet) THEN
        IF ~(T.readonly IN arg.flags) THEN
          IF ~(arg.type.form IN {ST.array, ST.dynarr}) OR
             ~(arg.type(ST.Array).of.form = ST.char) THEN
            err(EL.IllegalOperand);
          END;
        ELSE
          err(EL.ReadOnlyVariable);
        END;
      END;
    ELSE
      err(EL.TooFewAparm);
    END;
  ELSE
    err(EL.TooFewAparm);
  END;
END Copy;


PROCEDURE Finalize(x : T.Expr; args : T.Arg);
  VAR
    argument : T.Arg;
    arg : T.Expr;
    recType : ST.Type;
    at : ST.Procedure;
    p : ST.Symbol;
BEGIN
  argument := Arg0(args);
  IF argument # NIL THEN
    arg := argument.arg;
    IF (arg.class = T.Ndsgn) & (arg.subcl = T.Dtype) &
       (arg.type.form = ST.record) THEN
      recType := arg.type;
      argument :=   Arg1(args);
      IF argument # NIL THEN
        arg := argument.arg;
        (* arg must be a procedure taking one non-var parameter of type
         * POINTER TO recType and returning nothing. *)
        IF (arg.class = T.Ndsgn) & (arg.subcl = T.Dproc) &
           (arg(T.Design).sym # NIL) & (arg(T.Design).sym.mnolev = 0) THEN
          at := arg.type(ST.Procedure);
          IF at.result = ST.notyp THEN
            p := ST.FirstParm(at);
            IF p # NIL THEN
              IF (p.kind # ST.par) OR (p.type.form # ST.pointer) OR
                 (p.type(ST.Pointer).to # recType) THEN
                err(EL.ParmMismatch);
              END;
            ELSE
              err(EL.ParamCountsDiffer);
            END;
          ELSE
            err(EL.ResultMismatch);
          END;
        ELSE
          err(EL.MustBeGlobalProc);
        END;
      ELSE
        err(EL.TooFewAparm);
      END;
    ELSE
      err(EL.NotARecordType);
    END;
  ELSE
    err(EL.TooFewAparm);
  END;
END Finalize;


(* SYSTEM.BITR(x : LONGINT; bit : integer) : BOOLEAN *)
(* SYSTEM.BITS(x : LONGINT; bit : integer) : BOOLEAN *)
PROCEDURE BitSR(x : T.Expr; args : T.Arg);
  VAR
    b : BOOLEAN;
BEGIN
  ASSERT(x.type.form = ST.procedure);
  b := CheckArg(Arg0(args), {RV, EM} + ST.IntSet, ST.linttyp);
  b := CheckArg(Arg1(args), {RV} + ST.IntSet, NIL);
END BitSR;


PROCEDURE StdProcCall*(x : T.Design; args : T.Arg) : T.StmtList;
  VAR
    n : T.Node;
    nofArgs : SHORTINT;
    targ : T.Expr;
    std : T.StmtList;

BEGIN
  nofArgs := 2;
  std := NIL;
  CASE x.sym(ST.SymbolStdProc).procno OF
  | ST.newfn:
    nofArgs := 1;
    New(x, args, nofArgs);

  | ST.getfn:
    GetPut(x, args, TRUE);

  | ST.putfn:
    GetPut(x, args, FALSE);

  | ST.memrfn:
    MemRW(x, args, TRUE);
    nofArgs := 3;

  | ST.memwfn:
    MemRW(x, args, FALSE);
    nofArgs := 3;

  | ST.getrfn:
    GetPutReg(x, args, ST.getrfn);

  | ST.putrfn:
    GetPutReg(x, args, ST.putrfn);

  | ST.sysnewfn:
    Sysnew(x, args);

  | ST.movefn:
    Move(x, args);
    nofArgs := 3;

  | ST.haltfn:
    std := Halt(x, args); nofArgs := 1

  | ST.assertfn:
    std := Assert(x, args);

  | ST.incfn:
    std := IncDec(x, args, TRUE);

  | ST.decfn:
    std := IncDec(x, args, FALSE);

  | ST.inclfn:
    InclExcl(x, args);

  | ST.exclfn:
    InclExcl(x, args);

  | ST.copyfn:
    Copy(x, args);

  | ST.finalizefn:
    Finalize(x, args);

  | ST.bitrfn, ST.bitsfn:
    BitSR(x, args);
  ELSE
    err(EL.StdProcedure);
  END;

  IF std = NIL THEN
    std := T.NewProcCallNode(T.NewFuncCallNode(x, args));
  END;

  targ := T.ArgN(args, nofArgs);
  IF targ.subcl # T.Merror THEN
    err(EL.TooManyAparm);
  END;
  RETURN std;
END StdProcCall;


PROCEDURE Abs(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    b : BOOLEAN;
    arg : T.Expr;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV} + ST.NumSet, NIL);
  IF b THEN
    arg := a0.arg;
    IF T.constant IN arg.flags THEN
      CASE arg.type.form OF
      | ST.sint, ST.int, ST.lint:
        IF arg.val.i0 = MIN(LONGINT) THEN
          err(EL.NumberTooLarge);
        ELSE
          arg.val.i0 := ABS(arg.val.i0);
          TB.ConstSetIntType(arg);
        END;

      | ST.real, ST.lreal:
        arg := TB.NewRealConst(ABS(arg.val.real), arg.type);
      END;
      RETURN arg;
    ELSE
      x.type := ResultType(arg.type);
    END;
  ELSE
    x.type := ST.undftyp;
  END;
  RETURN x;
END Abs;


PROCEDURE Cap(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    arg : T.Expr;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, EM, ST.char}, ST.chartyp);
  IF b THEN
    arg := a0.arg;
    IF (T.constant IN arg.flags) THEN
      arg.val.i0 := ORD(CAP(CHR(arg.val.i0)));
      RETURN arg;
    END;
  END;
  x.type := ST.chartyp;
  RETURN x;
END Cap;


PROCEDURE Odd(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    b : BOOLEAN;
    a0 : T.Arg;
    arg : T.Expr;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV} + ST.IntSet, NIL);
  IF b THEN
    arg := a0.arg;
    IF (T.constant IN arg.flags) THEN
      RETURN TB.NewBoolConst(ODD(arg.val.i0));
    END;
  END;
  x.type := ST.booltyp;
  RETURN x;
END Odd;


PROCEDURE Adr(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {LV, ST.bool..ST.set, ST.pointer,
                     ST.procedure..ST.record}, NIL);
  IF b THEN
    TB.CheckLeaf(a0.arg, FALSE);
  END;
  x.type := ST.linttyp;
  RETURN x;
END Adr;


PROCEDURE Cc(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    arg : T.Expr;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, C} + ST.IntSet, NIL);
  IF b THEN
    arg := a0.arg;
    IF ((arg.val.i0 < 0) OR (arg.val.i0 > OPM.MaxCC)) THEN
      err(EL.IllegalValue);
    END;
  END;
  x.type := ST.booltyp;
  RETURN x;
END Cc;


(* XXX document: a convert node will be put into to reduce
 * the shift count to a SHORTINT *)
PROCEDURE Shifts(x : T.Expr; args : T.Arg; fn : SHORTINT) : T.Expr;
  VAR
    a0, a1 : T.Arg;
    arg, arg2 : T.Expr;
    b, b2 : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV} + ST.IntSet, NIL);
  a1 := Arg1(args);
  b2 := CheckArg(a1, {RV} + ST.IntSet, NIL);
  IF b & b2 THEN
    arg := a0.arg;
    arg2 := a1.arg;
    IF (T.constant IN arg.flags) & (T.constant IN arg2.flags) &
       (fn = ST.ashfn) THEN
      arg.val.i0 := ASH(arg.val.i0, arg2.val.i0);
      arg.type := ST.linttyp;
      RETURN arg;
    END;
    IF ~(T.constant IN arg2.flags) THEN
      IF arg2.type.form = ST.lint THEN
        arg2 := TB.Convert(arg2, ST.inttyp);
      END;
      IF arg2.type.form = ST.int THEN
        arg2 := TB.Convert(arg2, ST.sinttyp);
      END;
    END;
  END;
  x.type := ST.linttyp;
  RETURN x;
END Shifts;


PROCEDURE Len(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0, d0 : T.Arg;
    arg : T.Expr;
    i : LONGINT;
    t : ST.Type;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, ST.array, ST.dynarr}, NIL);
  IF b THEN
    arg := a0.arg;
    d0 := Arg1(args);
    b := CheckArg(d0, {O, RV, C} + ST.IntSet, NIL);
    IF b & (d0 # NIL) THEN
      i := d0.arg.val.i0;
    ELSE
      i := 0;
      args.next := T.NewArgNode(TB.NewIntConst(0));
    END;
    t := arg.type;
    WHILE (i > 0) & (t # NIL) & (t.form IN {ST.array, ST.dynarr}) DO
      DEC(i);
      t := t(ST.Array).of;
    END;

    IF (t # NIL) & (i >= 0) THEN
      IF t.form = ST.array THEN
        RETURN TB.NewIntConst(t(ST.Array).n); (* else dynarr *)
      END;
    ELSE
      err(EL.InvalidLen);
    END;
  END;
  x.type := ST.linttyp;
  RETURN x;
END Len;


(* SYSTEM.BIT(x : LONGINT; bit : integer) : BOOLEAN *)
PROCEDURE Bit(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    b : BOOLEAN;
BEGIN
  b := CheckArg(Arg0(args), {RV, EM} + ST.IntSet, ST.linttyp);
  b := CheckArg(Arg1(args), {RV} + ST.IntSet, NIL);
  x.type := ST.booltyp;
  RETURN x;
END Bit;


PROCEDURE Ord(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    b : BOOLEAN;
    a0 : T.Arg;
    arg : T.Expr;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, EM, ST.char}, ST.chartyp);
  IF b THEN
    arg := a0.arg;
    IF (T.constant IN arg.flags) THEN
      arg.type := ST.inttyp;
      RETURN arg;
    END;
  END;
  RETURN TB.NewConvert(arg, ST.inttyp);
END Ord;


(* entier is replaced by a convert node *)
PROCEDURE Entier(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    b : BOOLEAN;
    a0 : T.Arg;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, ST.real, ST.lreal}, NIL);
  IF b THEN
    RETURN TB.Convert(a0.arg, ST.linttyp);
  ELSE
    x.type := ST.linttyp;
    RETURN x;
  END;
END Entier;


PROCEDURE MinMax(x : T.Expr; args : T.Arg; op : SHORTINT) : T.Expr;
  VAR
    a0 : T.Arg;
    arg : T.Expr;
    f : SHORTINT;
    result : ST.Type;
BEGIN
  a0 := Arg0(args);
  IF (a0 # NIL) THEN
    arg := a0.arg;
    IF (arg.subcl = T.Dtype) THEN
      f := arg.type.form;
      IF f IN {ST.bool, ST.char..ST.set} THEN
        IF op = ST.maxfn THEN
          CASE f OF
          | ST.bool:
            x := TB.NewBoolConst(TRUE);

          | ST.char:
            x := TB.NewIntConst(0FFH);
            x.type := ST.chartyp;

          | ST.sint:
            x := TB.NewIntConst(OPM.MaxSInt);

          | ST.int:
            x := TB.NewIntConst(OPM.MaxInt);

          | ST.lint:
            x := TB.NewIntConst(OPM.MaxLInt);

          | ST.real:
            x := TB.NewRealConst(OPM.MaxReal, ST.realtyp);

          | ST.lreal:
            x := TB.NewRealConst(OPM.MaxLReal, ST.lrltyp);

          | ST.set:
            x := TB.NewIntConst(OPM.MaxSet);
            x.type := ST.inttyp;
          END;
        ELSE
          (* minfn *)
          CASE f OF
          | ST.bool:
            x := TB.NewBoolConst(FALSE);

          | ST.char:
            x := TB.NewIntConst(0);
            x.type := ST.chartyp;

          | ST.sint:
            x := TB.NewIntConst(OPM.MinSInt);

          | ST.int:
            x := TB.NewIntConst(OPM.MinInt);

          | ST.lint:
            x := TB.NewIntConst(OPM.MinLInt);

          | ST.real:
            x := TB.NewRealConst(OPM.MinReal, ST.realtyp);

          | ST.lreal:
            x := TB.NewRealConst(OPM.MinLReal, ST.lrltyp);

          | ST.set:
            x := TB.NewIntConst(0);
            x.type := ST.inttyp;
          END;
        END;
      ELSE
        err(EL.IllegalOperand);
      END;
      RETURN x;
    ELSE
      err(EL.NotAType);
    END;
  ELSE
    err(EL.TooFewAparm);
  END;
  RETURN TB.NewIntConst(0);
END MinMax;


PROCEDURE Chr(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    arg : T.Expr;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV} + ST.IntSet, NIL);
  IF b THEN
    arg := a0.arg;
    IF T.constant IN arg.flags THEN
      IF (arg.val.i0 >= 0) & (arg.val.i0 <= 0FFH) THEN
        arg.type := ST.chartyp;
        RETURN arg;
      ELSE
        err(EL.IllegalValue);
      END;
    END;
  END;
  RETURN TB.Convert(arg, ST.chartyp);
END Chr;


PROCEDURE Short(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 : T.Arg;
    arg : T.Expr;
    dest : ST.Type;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, ST.int, ST.lint, ST.lreal}, NIL);
  IF b THEN
    arg := a0.arg;
    CASE arg.type.form OF
    | ST.int:
      dest := ST.sinttyp;

    | ST.lint:
      dest := ST.inttyp;

    | ST.lreal:
      dest := ST.realtyp;
    END;
    RETURN TB.Convert(arg, dest);
  END;
  x.type := ST.undftyp;
  RETURN x;
END Short;


PROCEDURE Long(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    a0 :T.Arg;
    arg : T.Expr;
    dest : ST.Type;
    b : BOOLEAN;
BEGIN
  a0 := Arg0(args);
  b := CheckArg(a0, {RV, ST.sint, ST.int, ST.real}, NIL);
  IF b THEN
    arg := a0.arg;
    CASE arg.type.form OF
    | ST.sint:
      dest := ST.inttyp;

    | ST.int:
      dest := ST.linttyp;

    | ST.real:
      dest := ST.lrltyp;
    END;
    RETURN TB.Convert(arg, dest);
  END;
  x.type := ST.undftyp;
  RETURN x;
END Long;


PROCEDURE Size(x : T.Expr; args : T.Arg) : T.Expr;
  CONST
    SizeableTypes = {ST.bool, ST.byte, ST.char, ST.sint, ST.int, ST.lint,
                     ST.real, ST.lreal, ST.set, ST.pointer, ST.procedure,
                     ST.array, ST.record};
  VAR
    a0 : T.Arg;
    arg : T.Expr;
BEGIN
  a0 := Arg0(args);
  IF a0 # NIL THEN
    arg := a0.arg;
    IF arg.subcl = T.Dtype THEN
      IF arg.type.form IN SizeableTypes THEN
        ST.Size(arg.type);
        INCL(arg.type.flags, ST.pvused); (* Size is dependent upon the
                                          * private fingerprint. *)
        RETURN TB.NewIntConst(arg.type.size);
      ELSE
        err(EL.IllegalOperand);
      END;
    ELSE
      err(EL.NotAType);
    END;
  ELSE
    err(EL.TooFewAparm);
  END;
  RETURN x;
END Size;


PROCEDURE Val(x : T.Expr; args : T.Arg) : T.Expr;
  VAR
    t0, a0 : T.Arg;
  type, arg : T.Expr;
BEGIN
  t0 := Arg0(args);
  IF t0 # NIL THEN
    type := t0.arg;
    TB.CheckLeaf(type, FALSE);
    IF (type.class = T.Ndsgn) & (type(T.Design).sym.kind = ST.type) THEN
      a0 := Arg1(args);
      IF a0 # NIL THEN
        arg := a0.arg;
        IF (arg.class # T.Ndsgn) OR (arg.subcl IN T.RValueSet) THEN
          arg := T.NewCastNode(type.type, arg);
          RETURN arg;
        ELSE
          err(EL.IllegalOperand);
        END;
      ELSE
        err(EL.TooFewAparm);
      END;
    ELSE
      err(EL.IncompatibleAssignment);
    END;
  ELSE
    err(EL.TooFewAparm);
  END;
  RETURN x;
END Val;


PROCEDURE StdFuncCall*(x : T.Design; args : T.Arg) : T.Expr;
  VAR
    fn, nofArgs : SHORTINT;
    std, targ : T.Expr;

BEGIN
  fn := x.sym(ST.SymbolStdProc).procno;
  std := T.NewFuncCallNode(x, args);
  nofArgs := 1;
  CASE fn OF
  | ST.absfn:
    std := Abs(std, args);

  | ST.capfn:
    std := Cap(std, args);

  | ST.oddfn:
    std := Odd(std, args);

  | ST.adrfn:
    std := Adr(std, args);

  | ST.ashfn:
    std := Shifts(std, args, ST.ashfn);
    nofArgs := 2;

  | ST.lshfn:
    std := Shifts(std, args, ST.lshfn);
    nofArgs := 2;

  | ST.rotfn:
    std := Shifts(std, args, ST.rotfn);
    nofArgs := 2;

  | ST.lenfn:
    std := Len(std, args);
    nofArgs := 2;

  | ST.ordfn:
    std := Ord(std, args);

  | ST.entierfn:
    std := Entier(std, args);

  | ST.minfn:
    std := MinMax(std, args, ST.minfn);

  | ST.maxfn:
    std := MinMax(std, args, ST.maxfn);

  | ST.chrfn:
    std := Chr(std, args);

  | ST.shortfn:
    std := Short(std, args);

  | ST.longfn:
    std := Long(std, args);

  | ST.sizefn:
    std := Size(std, args);

  | ST.valfn:
    std := Val(x, args);
    nofArgs := 2;

  | ST.bitfn:
    std := Bit(std, args);
    nofArgs := 2;
  ELSE
    err(EL.StdProcedure);
  END;

  targ := T.ArgN(args, nofArgs);
  IF targ.subcl # T.Merror THEN
    err(EL.TooManyAparm);
  END;
  RETURN std;
END StdFuncCall;

END SKLSTP.
