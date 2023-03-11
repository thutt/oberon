MODULE SKLE;
IMPORT
  ST:=SKLST,
  TB:=SKLTB,
  T:=SKLT,
  SP:=SKLSTP,
  PU:=SKLPU,
  OPS:=SKLOS,
  OPM:=SKLMD,
  EL:=SKLERR;

VAR
  relTab : ARRAY OPS.geq - OPS.eql + 1 OF T.NODESUBCLASS;
  opTab : ARRAY OPS.or - OPS.times + 1 OF T.NODESUBCLASS;
  unopTab : ARRAY OPS.minus - OPS.plus + 1 OF T.NODESUBCLASS;

  (* negative relational tests *)
  negRelTab : ARRAY T.Egeq - T.Eeql + 1 OF T.NODESUBCLASS;
  PowerOf2 : LONGINT;

PROCEDURE ^ Expression*() : T.Expr;


PROCEDURE err(n : EL.ERRORTYPE);
BEGIN
  OPM.err(n);
END err;


PROCEDURE IsPowerOf2(x: LONGINT) : BOOLEAN;
BEGIN
  PowerOf2 := 0;
  IF x > 0 THEN
    WHILE ~ODD(x) DO
      x := x DIV 2;
      INC(PowerOf2)
    END
  END;
  RETURN (x = 1);
END IsPowerOf2;


PROCEDURE StdArgs*() : T.Arg;
  VAR
    arg, argList : T.Arg;
BEGIN (* LMPU.token = OPS.lparen *)
  argList := NIL;
  IF PU.token = OPS.lparen THEN
    OPS.Get(PU.token);
    IF PU.token # OPS.rparen THEN
      LOOP
        arg := T.NewArgNode(Expression());
        argList := T.BindArg(argList, arg);
        IF PU.token = OPS.comma THEN
          OPS.Get(PU.token);
        ELSIF (OPS.lparen <= PU.token) & (PU.token <= OPS.ident) THEN
          err(EL.CommaExpected);
        ELSE
          EXIT;
        END;
      END;
      PU.Match(OPS.rparen);
      T.ReverseArgList(argList);
    ELSE
      OPS.Get(PU.token);
    END;
  ELSE
    err(EL.LparenExpected);
  END;
  RETURN argList;
END StdArgs;


PROCEDURE ConstCharToString*(VAR n: T.Expr);
  VAR
    ch : CHAR;
    l : INTEGER;
    s : OPS.String;
BEGIN
  s[0] := CHR(n.val.i0);
  s[1] := 0X;
  IF s[0] = 0X THEN
    l := 1;
  ELSE
    l := 2;
  END;
  n := TB.NewDesign(ST.MakeStringConst(s, l));
  (*
  ch := CHR(n.val.i0);
  n.val.ext := ST.NewConstExt();
  IF ch = 0X THEN
    l := 1;
  ELSE
    l := 2;
    n.val.ext[1] := 0X;
  END;
  n.val.ext[0] := ch;
  n.val.i0 := l;
  n.type := ST.stringtyp;
 *)
END ConstCharToString;


PROCEDURE ConstCheckRealType(f, nr: INTEGER; x: T.Expr);
  VAR
    min, max, r: LONGREAL;
BEGIN
  IF f = ST.real THEN
    min := OPM.MinReal;
    max := OPM.MaxReal;
  ELSE
    min := OPM.MinLReal;
    max := OPM.MaxLReal;
  END;
  r := ABS(x.val.real);
  IF (r > max) OR (r < min) THEN
    err(nr);
    x.val.real := 1.0;
  ELSIF f = ST.real THEN
    x.val.real := SHORT(x.val.real);   (* single precision *)
  END;
END ConstCheckRealType;


PROCEDURE ConstMOp(op : T.NODESUBCLASS; x : T.Expr) : T.Expr;
  VAR
    f : SHORTINT;
BEGIN
  f := x.type.form;
  CASE op OF
  | T.Enot:
    IF f = ST.bool THEN
      IF x.val.i0 = OPM.FalseVal THEN
        x.val.i0 := OPM.TrueVal;
      ELSE
        x.val.i0 := OPM.FalseVal;
      END;
    ELSE
      err(EL.UnaryNot);
      x := TB.NewBoolConst(FALSE);
    END;

  | T.Euminus:
    IF f IN ST.IntSet THEN
      x.val.i0 := -x.val.i0
    ELSIF f IN ST.RealSet THEN
      x.val.real := -x.val.real;
    ELSIF f = ST.set THEN
      x.val.set := -x.val.set;
    END;

  | T.Euplus: (* nop *)
  END;
  RETURN x;
END ConstMOp;


PROCEDURE ConstOp(op : T.NODESUBCLASS; l, r : T.Expr) : T.Expr;
  VAR
    lf, rf : SHORTINT;
    lval, rval : ST.Const;
    t0, t1 : BOOLEAN;
    lim : LONGINT;


  PROCEDURE iserr;
  BEGIN
    err(EL.DyadicOperator);
    r.type := l.type;
    rval := lval;
  END iserr;


  PROCEDURE Cmp(): INTEGER;
    VAR
      res: INTEGER;
  BEGIN
    CASE lf OF
    | ST.undef:
      res := T.Eeql

    | ST.byte, ST.char, ST.sint, ST.int, ST.lint:
      IF lval.i0 < rval.i0 THEN
        res := T.Elss
      ELSIF lval.i0 > rval.i0 THEN
        res := T.Egtr
      ELSE
        res := T.Eeql
      END

    | ST.real, ST.lreal:
      IF lval.real < rval.real THEN
        res := T.Elss
      ELSIF lval.real > rval.real THEN
        res := T.Egtr
      ELSE
        res := T.Eeql
      END

    | ST.bool:
      IF lval.i0 # rval.i0 THEN
        res := T.Eneq
      ELSE
        res := T.Eeql
      END

    | ST.set:
      IF lval.set # rval.set THEN
        res := T.Eneq
      ELSE
        res := T.Eeql
      END

    | ST.string:
      IF lval.ext^ < rval.ext^ THEN
        res := T.Elss
      ELSIF lval.ext^ > rval.ext^ THEN
        res := T.Egtr
      ELSE
        res := T.Eeql
      END

    | ST.nil, ST.pointer, ST.procedure:
      IF lval.i0 # rval.i0 THEN
        res := T.Eneq
      ELSE
        res := T.Eeql
      END
    END;
    l.type := ST.booltyp;
    RETURN res;
  END Cmp;


  PROCEDURE BoolToInt(b : BOOLEAN) : INTEGER;
  BEGIN
    IF b THEN
      RETURN OPM.TrueVal;
    ELSE
      RETURN OPM.FalseVal;
    END;
  END BoolToInt;


  PROCEDURE IntToBool(x : LONGINT) : BOOLEAN;
  BEGIN
    IF x = OPM.FalseVal THEN
      RETURN FALSE
    ELSE
      RETURN TRUE;
    END;
  END IntToBool;

BEGIN
  lf := l.type.form;
  rf := r.type.form;
  lval := l.val;
  rval := r.val;
  IF lf # rf THEN
    (* convert *)
    CASE lf OF
    | ST.char:
      IF rf = ST.string THEN
        ConstCharToString(l)
      ELSE
        iserr;
      END;

    | ST.sint:
      IF rf IN ST.IntSet THEN
        l.type := r.type;
      ELSIF rf = ST.real THEN
        l.type := ST.realtyp;
        lval.real := lval.i0;
      ELSIF rf = ST.lreal THEN
        l.type := ST.lrltyp;
        lval.real := lval.i0;
      ELSE
        iserr;
      END;

    | ST.int:
      IF rf = ST.sint THEN
        r.type := ST.inttyp;
      ELSIF rf IN ST.IntSet THEN
        l.type := r.type;
      ELSIF rf = ST.real THEN
        l.type := ST.realtyp;
        lval.real := lval.i0;
      ELSIF rf = ST.lreal THEN
        l.type := ST.lrltyp;
        lval.real := lval.i0;
      ELSE
        iserr;
      END;

    | ST.lint:
      IF rf IN ST.IntSet THEN
        r.type := ST.linttyp;
      ELSIF rf = ST.real THEN
        l.type := ST.realtyp;
        lval.real := lval.i0;
      ELSIF rf = ST.lreal THEN
        l.type := ST.lrltyp;
        lval.real := lval.i0;
      ELSE
        iserr;
      END;

    | ST.real:
      IF rf IN ST.IntSet THEN
        r.type := ST.realtyp;
        rval.real := rval.i0;
      ELSIF rf = ST.lreal THEN
        l.type := ST.lrltyp;
      ELSE
        iserr;
      END;

    | ST.lreal:
      IF rf IN ST.IntSet THEN
        r.type := ST.lrltyp;
        rval.real := rval.i0;
      ELSIF rf = ST.real THEN
        r.type := ST.lrltyp;
      ELSE
        iserr;
      END;

    | ST.string:
      IF rf = ST.char THEN
        ConstCharToString(r);
      ELSE
        iserr;
      END;

    | ST.nil:
      IF ~(rf IN {ST.pointer, ST.procedure}) THEN
        iserr;
      END;

    | ST.pointer: (* can only be NIL and some pointer *)
      IF ~PU.ExprCompatPointer(l.type, r.type) THEN
        err(EL.DyadicOperator);
      END;

    | ST.procedure:
      IF rf # ST.nil THEN
        err(EL.DyadicOperator);
      END;
    ELSE
      iserr;
    END;
    lf := l.type.form;
  END; (* types are now equal *)

  CASE op OF
  | T.Eplus:
    CASE lf OF
    | ST.sint, ST.int, ST.lint:
      t0 := (rval.i0 >= 0) & (lval.i0 <= MAX(LONGINT) - rval.i0);
      t1 := (rval.i0 < 0) & (lval.i0 >= MIN(LONGINT) - rval.i0);
      IF t0 OR t1 THEN
        INC(lval.i0, rval.i0);
        TB.ConstSetIntType(l);
      ELSE
        err(EL.SumTooLarge);
      END

    | ST.real, ST.lreal:
      t0 := (rval.real >= 0.0) & (lval.real <= MAX(LONGREAL) - rval.real);
      t1 := (rval.real < 0.0) & (lval.real >= -MAX(LONGREAL) - rval.real);
      IF t0 OR t1 THEN
        lval.real := lval.real + rval.real;
        ConstCheckRealType(lf, EL.SumTooLarge, l);
      ELSE
        err(EL.SumTooLarge)
      END

    | ST.set:
      lval.set := lval.set + rval.set
    ELSE
      err(EL.BadPlusOperand);
    END;

  | T.Eminus:
    CASE lf OF
    | ST.sint, ST.int, ST.lint:
      t0 := (rval.i0 >= 0) & (lval.i0 >= MIN(LONGINT) + rval.i0);
      t1 := (rval.i0 < 0) & (lval.i0 <= MAX(LONGINT) + rval.i0);
      IF t0 OR t1 THEN
        DEC(lval.i0, rval.i0);
        TB.ConstSetIntType(l);
      ELSE
        err(EL.DifferenceTooLarge)
      END

    | ST.real, ST.lreal:
      t0 := (rval.real >= 0.0) & (lval.real >= -MAX(LONGREAL) + rval.real);
      t1 := (rval.real < 0.0) & (lval.real <= MAX(LONGREAL) + rval.real);
      IF t0 OR t1 THEN
        lval.real := lval.real - rval.real;
        ConstCheckRealType(lf, EL.DifferenceTooLarge, l);
      ELSE
        err(EL.DifferenceTooLarge)
      END

    | ST.set:
      lval.set := lval.set - rval.set
    ELSE
      err(EL.BadMinusOperand);
    END;

  | T.Etimes:
    CASE lf OF
    | ST.sint, ST.int, ST.lint:
      IF (lval.i0 >= 0) = (rval.i0 >= 0) THEN
        lim := MAX(LONGINT)
      ELSE
        lim := MIN(LONGINT)
      END;
      IF rval.i0 = 0 THEN
        l := r;
      ELSIF lval.i0 # 0 THEN
        (* lval = 0 => no work to do *)
        lim := lim DIV rval.i0;
        t0 := (lval.i0 >= 0) & (lval.i0 <= lim);
        t1 := (lval.i0 < 0) & (lval.i0 >= lim);
        IF (rval.i0 = 0) OR t0 OR t1 THEN
          lval.i0 := lval.i0 * rval.i0;
          TB.ConstSetIntType(l);
        ELSE
          err(EL.ProductTooLarge)
        END
      END;

    | ST.real, ST.lreal:
      t0 := ABS(rval.real) <= 1.0;
      t1 := (ABS(lval.real) <= MAX(LONGREAL) / ABS(rval.real));
      IF t0 OR t1 THEN
        lval.real := lval.real * rval.real;
        ConstCheckRealType(lf, EL.ProductTooLarge, l);
      ELSE
        err(EL.ProductTooLarge)
      END

    | ST.set:
      lval.set := lval.set * rval.set
    ELSE
      err(EL.BadTimesOperand);
    END;

  | T.Eslash:
    CASE lf OF
    | ST.sint, ST.int, ST.lint:
      IF rval.i0 # 0 THEN
        lval.real := lval.i0 / rval.i0;
        ConstCheckRealType(ST.real, EL.DivisionByZero, l);
      ELSE
        err(EL.DivisionByZero);
        lval.real := 1.0;
      END;
      l.type := ST.realtyp;

    | ST.real, ST.lreal:
      t0 := ABS(rval.real) >= 1.0;
      t1 := (ABS(lval.real) <= MAX(LONGREAL) * ABS(rval.real));
      IF t0 OR t1 THEN
        lval.real := lval.real / rval.real;
        ConstCheckRealType(lf, EL.DivisionByZero, l);
      ELSE
        err(EL.DivisionByZero)
      END

    | ST.set:
      lval.set := lval.set / rval.set
    ELSE
      err(EL.BadSlashOperand);
    END;

  | T.Ediv:
    IF lf IN {ST.sint, ST.int, ST.lint} THEN
      IF rval.i0 # 0 THEN
        lval.i0 := lval.i0 DIV rval.i0;
        TB.ConstSetIntType(l);
      ELSE
        err(EL.DivisionByZero)
      END
    ELSE
      err(EL.BadDivOperand);
    END;

  | T.Emod:
    IF lf IN ST.IntSet THEN
      IF rval.i0 # 0 THEN
        lval.i0 := lval.i0 MOD rval.i0;
        TB.ConstSetIntType(l);
      ELSE
        err(EL.DivisionByZero);
      END;
    ELSE
      err(EL.BadModOperand);
    END;

  | T.Eand:
    IF lf = ST.bool THEN
      t0 := IntToBool(lval.i0) & IntToBool(rval.i0);
      lval.i0 := BoolToInt(t0);
    ELSE
      err(EL.BadAndOperand);
    END;

  | T.Eor:
    IF lf = ST.bool THEN
      t0 := IntToBool(lval.i0) OR IntToBool(rval.i0);
      lval.i0 := BoolToInt(t0);
    ELSE
      err(EL.BadOrOperand);
    END;

  | T.Eeql, T.Eneq:
    lval.i0 := BoolToInt(Cmp() = op);

  | T.Elss, T.Egtr:
    IF ~(lf IN {ST.bool, ST.set, ST.nil, ST.pointer}) THEN
      lval.i0 := BoolToInt(Cmp() = op)
    ELSE
      err(EL.BadRelationalTest)
    END

  | T.Eleq, T.Egeq:
    IF ~(lf IN {ST.bool, ST.set, ST.nil, ST.pointer}) THEN
      lval.i0 := BoolToInt(Cmp() # negRelTab[op - T.Eeql])
    ELSE
      err(EL.BadRelationalTest)
    END
  END;
  RETURN l;
END ConstOp;


(* can insert conversion nodes into l or r *)
PROCEDURE DOp*(op : T.NODESUBCLASS; l, r : T.Expr) : T.Expr;
  VAR
    lF, rF : SHORTINT;
  type, lt, rt : ST.Type;
  t0 : T.Expr;


  (* TRUE => both operands are strings; side-effect: ""
             can be changed into 0X *)
  PROCEDURE strings(): BOOLEAN;
    VAR
      ok, lCharArr, rCharArr: BOOLEAN;
  BEGIN
    lCharArr := (l.type.form IN {ST.array, ST.dynarr}) &
                (l.type(ST.Array).of.form = ST.char) OR (lF=ST.string);
    rCharArr := (r.type.form IN {ST.array, ST.dynarr}) &
                (r.type(ST.Array).of.form = ST.char) OR (rF=ST.string);
    IF lCharArr & (rF = ST.char) & (T.constant IN r.flags) THEN
      ConstCharToString(r);
      rF := ST.string;
      rCharArr := TRUE;
    END;
    IF rCharArr & (lF = ST.char) & (T.constant IN l.flags) THEN
      ConstCharToString(l);
      lF := ST.string;
      lCharArr := TRUE;
    END;
    ok := lCharArr & rCharArr;
    IF ok THEN
      (* replace ""-string compare with 0X-char compare, if possible *)
      IF (lF = ST.string) & (l.val.i0 = 1) THEN
        (* r is array of char *)
        l.type := ST.chartyp;
        l.val.i0 := 0;
        r := T.NewIndexNode(r(T.Design), 0, 0,
                            TB.NewIntConst(0), ST.chartyp) (* r = r[0] *)
      ELSIF (rF = ST.string) & (r.val.i0 = 1) THEN
        (* l is array of char *)
        r.type := ST.chartyp;
        r.val.i0 := 0;
        l := T.NewIndexNode(l(T.Design), 0, 0,
                            TB.NewIntConst(0), ST.chartyp) (* l = l[0] *)
      END
    END;
    RETURN ok
  END strings;

BEGIN
  lF := l.type.form;
  rF := r.type.form;
  IF (lF = ST.undef) OR (rF = ST.undef) THEN
    RETURN l;
  ELSIF (T.constant IN l.flags) & (T.constant IN r.flags) THEN
    RETURN ConstOp(op, l, r);
  ELSE
    IF lF # rF THEN
      CASE lF OF
      | ST.char:
        IF T.constant IN l.flags THEN
          ConstCharToString(l);
        ELSE
          err(EL.DyadicOperator);
        END;

      | ST.sint:
        IF rF IN ST.NumSet THEN
          l := TB.Convert(l, r.type);
        ELSE
          err(EL.DyadicOperator);
        END;

      | ST.int:
        IF rF = ST.sint THEN
          r := TB.Convert(r, l.type)
        ELSIF rF IN ST.NumSet THEN
          l := TB.Convert(l, r.type)
        ELSE
          err(EL.DyadicOperator);
        END;

      | ST.lint:
        IF rF IN ST.IntSet THEN
          r := TB.Convert(r, l.type)
        ELSIF rF IN ST.RealSet THEN
          l := TB.Convert(l, r.type)
        END;

      | ST.real:
        IF rF IN ST.IntSet THEN
          r := TB.Convert(r, l.type);
        ELSIF rF IN ST.RealSet THEN
          l := TB.Convert(l, r.type);
        ELSE
          err(EL.DyadicOperator);
        END;

      | ST.lreal:
        IF rF IN ST.NumSet THEN
          r := TB.Convert(r, l.type);
        ELSE
          err(EL.DyadicOperator);
        END;

      | ST.nil:
        IF ~(rF IN {ST.procedure, ST.pointer}) THEN
          err(EL.DyadicOperator);
        END

      | ST.procedure:
        IF rF # ST.nil THEN
          err(EL.DyadicOperator);
        END;

      | ST.pointer:
        IF ~PU.ExprCompatPointer(l.type, r.type) THEN
          err(EL.DyadicOperator);
        END;

      | ST.array, ST.dynarr, ST.string: (* nop *)
      ELSE
        err(EL.DyadicOperator);
      END;
    END; (* l.type = r.type *)

    type := l.type;
    lF := type.form;
    rF := r.type.form;

    CASE op OF
    | T.Eplus:
      IF ~(lF IN {ST.sint, ST.int, ST.lint, ST.real, ST.lreal, ST.set}) THEN
        err(EL.BadPlusOperand);
      END;

    | T.Eminus:
      IF ~(lF IN {ST.sint, ST.int, ST.lint, ST.real, ST.lreal, ST.set}) THEN
        err(EL.BadMinusOperand);
      END;

    | T.Etimes:
      IF ~(lF IN {ST.sint, ST.int, ST.lint, ST.real, ST.lreal, ST.set}) THEN
        err(EL.BadTimesOperand);
      END;
      IF (lF IN ST.IntSet) THEN
        IF (T.constant IN l.flags) & IsPowerOf2(l.val.i0) THEN
          t0 := r;
          r := l;
          l := t0;
          op := T.Eash;
          r.val.i0 :=  PowerOf2;
          r.type := ST.sinttyp;
        ELSIF (T.constant IN r.flags) & IsPowerOf2(r.val.i0) THEN
          op := T.Eash;
          r.val.i0 :=  PowerOf2;
          r.type := ST.sinttyp;
        END;
      END;

    | T.Eslash:
      IF lF IN ST.IntSet THEN
        type := ST.realtyp;
        l := TB.Convert(l, type);
        r := TB.Convert(r, type);
      ELSIF lF IN ST.RealSet THEN
        (* ok *)
      ELSIF ~(lF IN {ST.set, ST.undef}) THEN
        err(EL.BadSlashOperand);
      END;

    | T.Emod:
      IF ~(lF IN ST.IntSet) THEN
        err(EL.BadModOperand);
      END;
      IF (T.constant IN r.flags) & IsPowerOf2(r.val.i0) THEN
        op := T.Emsk;
        r.val.i0 := ASH(-1, PowerOf2);
        r.type := ST.sinttyp;
      END;

    | T.Ediv:
      IF ~(lF IN ST.IntSet) THEN
        err(EL.BadDivOperand);
      END;
      IF (T.constant IN r.flags) & IsPowerOf2(r.val.i0) THEN
        op := T.Eash;
        r.val.i0 := -PowerOf2;
        r.type := ST.sinttyp;
      END;

    | T.Eand:
      type := ST.booltyp;
      IF lF # ST.bool THEN
        err(EL.BadAndOperand);
      END;

    | T.Eor:
      type := ST.booltyp;
      IF lF # ST.bool THEN
        err(EL.BadOrOperand);
      END;

    | T.Eeql, T.Eneq:
      type := ST.booltyp;
      IF ~(lF IN {ST.bool, ST.byte, ST.char, ST.sint, ST.int, ST.lint,
                  ST.real, ST.lreal, ST.set, ST.nil, ST.pointer,
                  ST.procedure}) & ~strings() THEN
        err(EL.BadEqualityTest);
      END;

    | T.Elss, T.Eleq, T.Egtr, T.Egeq:
      type := ST.booltyp;
      IF ~(lF IN {ST.char, ST.sint, ST.int, ST.lint, ST.real, ST.lreal}) &
         ~strings() THEN
        err(EL.BadRelationalTest);
      END;
    END;
    RETURN T.NewDExprNode(op, l, r, type);
  END;
END DOp;


PROCEDURE MOp*(op : T.NODESUBCLASS; x : T.Expr) : T.Expr;
  VAR
    f : SHORTINT;
BEGIN
  f := x.type.form;
  IF f IN ST.IntSet + ST.RealSet + {ST.bool, ST.set} THEN
    IF T.constant IN x.flags THEN
      RETURN ConstMOp(op, x);
    ELSE
      RETURN T.NewMExprNode(op, x);
    END;
  ELSE
    CASE op OF
    | T.Enot:
      err(EL.UnaryNot);
      
    | T.Euminus:
      err(EL.BadMinusOperand)
         
    | T.Euplus:
      err(EL.BadPlusOperand)
         
    | T.Econvert: (* nop *)
    END;
    RETURN x;
  END;
END MOp;


PROCEDURE CheckParamMatch*(ap, fp : ST.Symbol; checkNames : BOOLEAN);
  VAR
    ft, at : ST.Type;
    fpt, apt : ST.Procedure;
BEGIN
  WHILE fp # NIL DO
    IF ap # NIL THEN
      ft := fp.type;
      at := ap.type;
      WHILE (ft.form = ST.dynarr) & (at.form = ST.dynarr) DO
        ft := ft(ST.Array).of;
        at := at(ST.Array).of;
      END;
      IF ft # at THEN
        IF (ft.form = ST.procedure) & (at.form = ST.procedure) THEN
          fpt := ft(ST.Procedure);
          apt := at(ST.Procedure);
          IF fpt.result = apt.result THEN
            CheckParamMatch(apt.parms, fpt.parms, FALSE);
          ELSE
            err(EL.ResultMismatch);
          END;
        ELSE
          err(EL.ParmMismatch);
        END;
      END;
      IF (fp.kind # ap.kind) OR checkNames & (fp.name^ # ap.name^) THEN
        err(EL.ParmMismatch);
      END;
      ap := ST.NextParm(ap);
    ELSE
      err(EL.ParamCountsDiffer);
    END;
    fp := ST.NextParm(fp);
  END;
  IF ap # NIL THEN
    err(EL.ParamCountsDiffer);
  END;
END CheckParamMatch;


PROCEDURE AssignCompat*(to: ST.Type; from: T.Expr) : T.Expr; (* x := y *)
  VAR
    t, f : SHORTINT;
    ft : ST.Type;
    toArr : ST.Array;
    error : BOOLEAN;


  PROCEDURE CheckProc(to : ST.Procedure; fromSym : ST.Symbol);
  BEGIN
    IF fromSym.kind IN {ST.var, ST.par, ST.varpar, ST.lproc,
                        ST.xproc, ST.cproc, ST.iproc} THEN
      IF (fromSym.kind = ST.lproc) & (fromSym.mnolev # 0) THEN
        err(EL.MustBeGlobalProc);
      END;
      IF to.result = fromSym.type(ST.Procedure).result THEN
        CheckParamMatch(to.parms, fromSym.type(ST.Procedure).parms, FALSE);
        IF to.sysflag # from.type.sysflag THEN
          err(EL.IncompatibleAssignment);
        END;
      ELSE
        err(EL.ResultMismatch);
      END;
    ELSE
      err(EL.IncompatibleAssignment);
    END;
  END CheckProc;

BEGIN
  t := to.form;
  ft := from.type;
  f := ft.form;
  error := FALSE;
  CASE t OF
  | ST.undef: (* erroneous type, don't make more errors *)

  | ST.byte:
    IF ~(f IN {ST.byte, ST.char, ST.sint}) THEN
      error := TRUE;
    END;

  | ST.bool, ST.char, ST.sint, ST.set:
    IF t # f THEN
      error := TRUE;
    END;

  | ST.int:
    IF ~(f IN {ST.sint, ST.int}) THEN
      error := TRUE
    ELSIF f = ST.sint THEN
      from := TB.Convert(from, to);
    END;

  | ST.lint:
    IF ~(f IN ST.IntSet) THEN
      error := TRUE
    ELSIF f IN {ST.sint, ST.int} THEN
      from := TB.Convert(from, to);
    END;

  | ST.real:
    IF ~(f IN ST.IntSet + {ST.real}) THEN
      error := TRUE;
    ELSIF f IN ST.IntSet THEN
      from := TB.Convert(from, to);
    END;

  | ST.lreal:
    IF ~(f IN ST.NumSet) THEN
      error := TRUE
    ELSIF f IN ST.IntSet + {ST.real} THEN
      from := TB.Convert(from, to);
    END;

  | ST.void, ST.nil:
    error := TRUE;

  | ST.pointer:
    IF (to = ft) OR (f = ST.nil) OR
       (to = ST.sysptrtyp) & (f = ST.pointer) THEN
      (* valid *)
    ELSIF f = ST.pointer THEN
      IF ~ST.Extends(ft, to) THEN
        error := TRUE;
      END;
    ELSE
      error := TRUE;
    END;

  | ST.procedure:
    IF (to = ft) OR (f = ST.nil) THEN
      (* valid *)
    ELSIF from.type.form = ST.procedure THEN
      CheckProc(to(ST.Procedure), from(T.Design).sym);
    ELSE
      error := TRUE;
    END;

  | ST.array:
    (* idfp of 'from' guarantees assignment compatibility with 'to' *)
    INCL(to.flags, ST.pvused);
    toArr := to(ST.Array);
    IF (T.constant IN from.flags) & (f = ST.char) THEN
      ConstCharToString(from(T.Expr));
      ft := from.type;
      f := ST.string;
    END;
    IF toArr = ft THEN
      (* valid *)
    ELSIF (f = ST.string) & (toArr.of = ST.chartyp) THEN
      (* string length valid? *)
      ASSERT(from.class = T.Ndsgn, 1000);
      ASSERT(from.subcl = T.Dconst, 1001);
      IF from(T.Design).sym(ST.SymbolConst).val.i0 > toArr.len THEN
        err(EL.StringDoesNotFit);
      END;
    ELSE
      error := TRUE;
    END;

  | ST.record:
    (* idfp of 'from' guarantees assignment compatibility with 'to' *)
    INCL(to.flags, ST.pvused);
    IF ~ST.Extends(from.type, to) THEN
      error := TRUE;
    END;

  | ST.dynarr:
    error := TRUE;
  END;
  IF error THEN
    err(EL.IncompatibleAssignment);
  ELSIF (T.constant IN from.flags) & (f < t) &
        (f >= ST.sint) & (t IN ST.NumSet) THEN
    (* Variable type conversions handled when processing operators. *)
    from := TB.Convert(from, to);
  END;
  RETURN from;
END AssignCompat;


PROCEDURE selector*(x: T.Design) : T.Design;
  VAR
    obj : ST.Symbol;
    name: OPS.Name;
    e : T.Expr;


  PROCEDURE RecordRef(x : T.Design; fldName : OPS.Name) : T.Design;
    VAR
      scope : ST.SymbolScope;
      owner, proc, obj, field : ST.Symbol;
      typ: ST.Type;
      rec : T.Design;

  BEGIN
    IF x.type.form = ST.record THEN
      obj := ST.FindField(fldName, x.type(ST.Record));
      IF obj # NIL THEN
        IF obj.kind = ST.tproc THEN
          x := TB.NewMethod(x, obj);
          IF PU.token = OPS.arrow THEN
            (* super call *)
            OPS.Get(PU.token);
            field := obj;
            rec := x(T.Field).base; (* deref or design node *)
            IF (rec.class = T.Ndsgn) & (rec.subcl = T.Dderef) THEN
              rec := rec(T.Deref).base;
            END;
            (* rec = record variable *)

            scope := ST.topScope;   (* method making supercall *)
            (* Find tproc which owns the scope containing the
               super call (ie: nested procs in a tproc) or it will find that a
               super call is not valid in the current context. *)
            LOOP
              owner := ST.ScopeOwner(scope);
              IF (owner = NIL) OR (owner.kind = ST.tproc) THEN
                EXIT;
              END;
              scope := ST.PreviousScope(scope);
            END;

            (* first parm # Self => supercall invalid (y <=> record (Self)) *)
            IF (owner = NIL) OR (owner.type(ST.Procedure).parms # rec.sym) THEN
              err(EL.InvalidSupercall);
            END;
            typ := rec.sym.type;
            IF typ.form = ST.pointer THEN
              typ := typ(ST.Pointer).to;
            END;
            proc := ST.FindField(field.name^, typ(ST.Record).ancestor);

            IF proc # NIL THEN
              INCL(x.flags, T.super)
            ELSE
              err(EL.BaseMethodNotFound);
            END;
          END;
          IF (obj.type(ST.Procedure).result # ST.notyp) &
             (PU.token # OPS.lparen) THEN
            err(EL.LparenExpected); (* function method? *)
          END;
        ELSE
          x := T.NewFieldNode(x, 0, obj);
        END;
      ELSE
        err(EL.UndefinedField);
      END;
    ELSE
      err(EL.NotARecordType);
    END;
    RETURN x;
  END RecordRef;

BEGIN
  LOOP
    CASE PU.token OF
    | OPS.arrow:
      OPS.Get(PU.token);
      x := TB.NewDeref(x);
      
    | OPS.lbrak: (* array access *)
      OPS.Get(PU.token);
      LOOP
        IF x.type.form = ST.pointer THEN
          x := TB.NewDeref(x);
        END;
        e := Expression();
        IF e.type = ST.undftyp THEN
          e.type := ST.linttyp;
        END;
        x := TB.NewIndex(x, e);
        IF PU.token = OPS.comma THEN
          OPS.Get(PU.token)
        ELSE
          EXIT
        END;
      END;
      PU.Match(OPS.rbrak);

    | OPS.period: (* record access *)
      OPS.Get(PU.token);
      IF PU.token = OPS.ident THEN
        name := OPS.name;
        OPS.Get(PU.token);
        IF x.type.form = ST.pointer THEN
          x := TB.NewDeref(x);
        END;
        x := RecordRef(x, name);
      ELSE
        err(EL.IdentExpected);
      END;

    | OPS.lparen: (* possible type guard *)
      IF (x.class = T.Ndsgn) &
         ~(x.subcl IN {T.Dproc, T.Dmethod, T.Dstdproc}) &
         ~((x.subcl IN {T.Dvar, T.Dpar, T.Dvarpar, T.Dfield, T.Dindex}) &
           (x.type.form = ST.procedure)) THEN
        OPS.Get(PU.token);
        IF PU.token = OPS.ident THEN
          PU.qualident(obj);
          x := TB.NewGuard(x, obj);
        ELSE
          err(EL.IdentExpected);
        END;
        PU.Match(OPS.rparen)
      ELSE
        EXIT; (* it is a procedure call *)
      END;
    ELSE
      EXIT
    END;
  END;
  RETURN x;
END selector;


PROCEDURE ActualParameters*(fpar: ST.Symbol; parms : T.Arg) : T.Arg;
  VAR
    aparlist, apar : T.Arg;
    par : T.Expr;


  PROCEDURE CheckParam(VAR ap: T.Expr; fp: ST.Symbol);

    PROCEDURE DynArrParCheck(ftyp : ST.Array; atyp: ST.Type; fvarpar: BOOLEAN);
      VAR
        f: INTEGER;
    BEGIN (* ftyp.form = ST.dynarr *)
      f := atyp.form;
      IF fvarpar & (ftyp.of = ST.bytetyp) THEN
        (* ok *)
      ELSIF f IN {ST.array, ST.dynarr} THEN
        IF ftyp.of.form = ST.dynarr THEN
          DynArrParCheck(ftyp.of(ST.Array), atyp(ST.Array).of, fvarpar);
        ELSIF ftyp.of # atyp(ST.Array).of THEN
          err(EL.OpenArrayMismatch);
        END;
      ELSE
        err(EL.NotSuitableOpenArray);
      END;
    END DynArrParCheck;

  BEGIN
    IF fp.type.form # ST.undef THEN
      IF fp.kind = ST.varpar THEN
        IF (ap.class # T.Ndsgn) OR ~(ap.subcl IN T.LValueSet) THEN
          err(EL.NotAVariable)
        ELSE
          TB.CheckLeaf(ap, FALSE);
        END;
        IF T.readonly IN ap.flags THEN
          err(EL.ReadOnlyVariable);
        END;

        IF fp.type.form = ST.dynarr THEN
          DynArrParCheck(fp.type(ST.Array), ap.type, TRUE)
        ELSIF (fp.type.form = ST.record) & (ap.type.form = ST.record) THEN
          IF ~ST.Extends(ap.type, fp.type) THEN
            err(EL.IncompatibleAssignment);
          END;
        ELSIF (fp.type = ST.sysptrtyp) & (ap.type.form = ST.pointer) THEN
          (* ok *)
        ELSIF (ap.type # fp.type) &
              ~((fp.type.form = ST.byte) &
                (ap.type.form IN {ST.char, ST.sint})) THEN
          err(EL.VarParmMismatch)
        END;
      ELSIF fp.type.form = ST.dynarr THEN
        IF (T.constant IN ap.flags) & (ap.type.form = ST.char) THEN
          ConstCharToString(ap);
        END;
        IF (ap.type.form = ST.string) &
           (fp.type(ST.Array).of.form = ST.char) THEN
          (* ok *)
        ELSIF (ap.class # T.Ndsgn) OR ~(ap.subcl IN T.LValueSet) THEN
          err(EL.IllegalOpenArray)
        ELSE
          DynArrParCheck(fp.type(ST.Array), ap.type, FALSE)
        END
      ELSE
        ap := AssignCompat(fp.type, ap);
      END;
    END
  END CheckParam;

BEGIN
  aparlist := parms;
  IF PU.token # OPS.rparen THEN
    LOOP
      par := Expression();
      IF (fpar # NIL) & (fpar.kind IN {ST.par, ST.varpar}) THEN
        CheckParam(par, fpar);
        apar := T.NewArgNode(par);
        aparlist := T.BindArg(aparlist, apar);
        fpar := ST.NextParm(fpar);
      ELSE
        err(EL.TooManyAparm);
      END;
      IF PU.token = OPS.comma THEN
        OPS.Get(PU.token);
      ELSIF (PU.token >= OPS.lparen) & (PU.token <= OPS.ident) THEN
        err(EL.CommaExpected)
      ELSE
        EXIT;
      END;
    END;
    T.ReverseArgList(aparlist);
  END;
  IF (fpar # NIL) & (fpar.kind IN {ST.par, ST.varpar}) THEN
    err(EL.TooFewAparm);
  END;
  RETURN aparlist;
END ActualParameters;


PROCEDURE Expression*() : T.Expr;
  VAR
    lhs : T.Expr;
    typename : ST.Symbol;
    op : T.NODECLASS;


  PROCEDURE SimpleExpression() : T.Expr;
    VAR
      op : T.NODECLASS;
      n : T.Expr;


    PROCEDURE Term() : T.Expr;
      VAR
        op : T.NODECLASS;
        n, m : T.Expr;


      PROCEDURE Factor() : T.Expr;
        VAR
          ident, fpar : ST.Symbol;
          x : T.Expr;
          apar : T.Arg;
          owner : ST.Symbol;


        PROCEDURE Set() : T.Expr;
          VAR
            l, r : T.Expr;
            pos : LONGINT;


          PROCEDURE Element() : T.Expr;
            VAR
              lo, hi : T.Expr;
          BEGIN
            lo := Expression();
            IF PU.token = OPS.upto THEN
              OPS.Get(PU.token);
              hi := Expression();
              RETURN TB.NewSetRange(lo, hi);
            ELSE
              RETURN TB.NewSetElem(lo);
            END;
          END Element;

        BEGIN
          OPS.Get(PU.token);
          IF PU.token # OPS.rbrace THEN
            l := Element();
            LOOP
              IF PU.token = OPS.comma THEN
                OPS.Get(PU.token);
              ELSIF (PU.token >= OPS.lparen) & (PU.token <= OPS.ident) THEN
                err(EL.CommaExpected)
              ELSE
                EXIT;
              END;
              r := Element();
              IF (T.constant IN l.flags) & (T.constant IN r.flags) THEN
                l := ConstOp(T.Eplus, l, r);
              ELSE
                l := T.NewDExprNode(T.Eplus, l, r, ST.settyp);
              END;
            END;
          ELSE
            l := TB.NewEmptySet();
          END;
          PU.Match(OPS.rbrace);
          RETURN l;
        END Set;

        PROCEDURE CompleteDynarrIndex(x : T.Design) : T.Design;
          VAR
            index : T.Design;
            type : ST.Type;
        BEGIN
          (* x is the last dimension indexed. *)
          IF x.type.form = ST.dynarr THEN
            type := x.type;
            WHILE x.type.form = ST.dynarr DO
              index := TB.NewIndex(x, TB.NewIntConst(0));
              x := index;
            END;
            x := T.NewDesignCast(x, type);
          END;
          RETURN x;
        END CompleteDynarrIndex;

      BEGIN
        PU.Sync(OPS.lparen, EL.BadFactorStart);

        CASE PU.token OF
         | OPS.ident:
           PU.qualident(ident);
           x := selector(TB.NewDesign(ident));
           IF x.subcl = T.Dindex THEN
             x := CompleteDynarrIndex(x(T.Design));
           END;

           IF x.subcl = T.Dstdproc THEN
             x := SP.StdFuncCall(x(T.Design), StdArgs());
           ELSIF PU.token = OPS.lparen THEN
             (* regular or super call *)
             OPS.Get(PU.token);
             x := TB.SetupCall(x(T.Design), fpar, apar);
             apar := ActualParameters(fpar, apar);
             PU.Match(OPS.rparen);
             x := T.NewFuncCallNode(x(T.Design), apar);
             IF PU.level > 0 THEN
               owner := ST.ScopeOwner(ST.topScope);
               EXCL(owner.flags, ST.leaf);
             END;
           END;

         | OPS.number:
           CASE OPS.numtyp OF
            | OPS.char:
              x := TB.NewIntConst(OPS.intval);
              x.type := ST.chartyp;
              
            | OPS.integer:
              x := TB.NewIntConst(OPS.intval);
              
            | OPS.real:
              x := TB.NewRealConst(OPS.realval, ST.realtyp);
              
            | OPS.longreal:
              x := TB.NewRealConst(OPS.lrlval, ST.lrltyp);
           END;
           OPS.Get(PU.token);

         | OPS.string:
           OPS.Get(PU.token);
           x := TB.NewDesign(ST.MakeStringConst(OPS.str, OPS.intval));
           
         | OPS.nil:
           OPS.Get(PU.token);
           x := TB.NewNil();

         | OPS.lparen:
           OPS.Get(PU.token);
           x := Expression();
           PU.Match(OPS.rparen);

         | OPS.lbrak:
           OPS.Get(PU.token);
           err(EL.LparenExpected);
           x := Expression();
           PU.Match(OPS.rparen);

         | OPS.lbrace:
           x := Set();

         | OPS.not:
           OPS.Get(PU.token);
           x := TB.NewMonoExpr(T.Enot, Factor());
        ELSE
          OPS.Get(PU.token);
          x := TB.NewIntConst(0);
          err(EL.BadFactorStart);
        END;
        RETURN x;
      END Factor;

    BEGIN
      n := Factor();
      WHILE (PU.token <= MAX(SET)) &
            (PU.token IN {OPS.times, OPS.slash, OPS.div, OPS.mod, OPS.and}) DO
        op := opTab[PU.token - OPS.times];
        OPS.Get(PU.token);
        m := Factor();
        n := DOp(op, n, m);
      END;
      RETURN n;
    END Term;

  BEGIN
    IF (PU.token <= MAX(SET)) & (PU.token IN {OPS.minus, OPS.plus}) THEN
      op := unopTab[PU.token - OPS.plus];
      OPS.Get(PU.token);
      n := Term();
      n := MOp(op, n);
    ELSE
      n := Term();
    END;

    WHILE (PU.token <= MAX(SET)) &
          (PU.token IN {OPS.plus, OPS.minus, OPS.or}) DO
      op := opTab[PU.token - OPS.times];
      OPS.Get(PU.token);
      n := DOp(op, n, Term());
    END;
    RETURN n;
  END SimpleExpression;

BEGIN
  lhs := SimpleExpression();
  CASE PU.token OF
  | OPS.eql, OPS.neq, OPS.lss, OPS.leq, OPS.gtr, OPS.geq:
    op := relTab[PU.token - OPS.eql];
    OPS.Get(PU.token);
    lhs := DOp(op, lhs, SimpleExpression());

  | OPS.in:
    OPS.Get(PU.token);
    lhs := TB.NewInTest(lhs, SimpleExpression());

  | OPS.is:
    OPS.Get(PU.token);
    IF PU.token = OPS.ident THEN
      PU.qualident(typename);
      lhs := TB.NewIsTest(lhs, TB.NewDesign(typename));
    ELSE
      err(EL.IdentExpected);
    END;
  ELSE
    (* nop *)
  END;
  RETURN lhs;
END Expression;


PROCEDURE ConstExpression*() : T.Expr;
  VAR
    x : T.Expr;
BEGIN
  x := Expression();
  IF ~(T.constant IN x.flags) THEN
    x := TB.NewIntConst(0);
    err(EL.NotAConstant);
  END;
  RETURN x;
END ConstExpression;

BEGIN
  relTab[OPS.eql - OPS.eql] := T.Eeql;
  relTab[OPS.neq - OPS.eql] := T.Eneq;
  relTab[OPS.lss - OPS.eql] := T.Elss;
  relTab[OPS.leq - OPS.eql] := T.Eleq;
  relTab[OPS.gtr - OPS.eql] := T.Egtr;
  relTab[OPS.geq - OPS.eql] := T.Egeq;

  opTab[OPS.times - OPS.times] := T.Etimes;
  opTab[OPS.slash - OPS.times] := T.Eslash;
  opTab[OPS.div   - OPS.times] := T.Ediv;
  opTab[OPS.mod   - OPS.times] := T.Emod;
  opTab[OPS.plus  - OPS.times] := T.Eplus;
  opTab[OPS.minus - OPS.times] := T.Eminus;
  opTab[OPS.and   - OPS.times] := T.Eand;
  opTab[OPS.or    - OPS.times] := T.Eor;

  unopTab[OPS.plus - OPS.plus] := T.Euplus;
  unopTab[OPS.minus - OPS.plus] := T.Euminus;

  negRelTab[T.Eeql - T.Eeql] := T.Eneq;
  negRelTab[T.Eneq - T.Eeql] := T.Eeql;
  negRelTab[T.Elss - T.Eeql] := T.Egeq;
  negRelTab[T.Eleq - T.Eeql] := T.Egtr;
  negRelTab[T.Egtr - T.Eeql] := T.Eleq;
  negRelTab[T.Egeq - T.Eeql] := T.Elss;
END SKLE.
