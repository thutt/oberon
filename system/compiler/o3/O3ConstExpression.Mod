MODULE O3ConstExpression; (* front end enusres type-correct tree *)
  IMPORT
    Config := O3Config,
    Symtab := O3Symtab,
    Scanner := O3Scanner,
    AST := O3TreeNode,
    ASTH := O3TreeHelper,
    E := O3Errors;

  VAR
    negRelTab : POINTER TO ARRAY OF AST.NODESUBCLASS;

  PROCEDURE ^ fe(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;

  (* make a proper constant expression node based on the input type *)
  PROCEDURE MakeConstExpr(type : Symtab.Type) : AST.Expr;
    VAR e : AST.Expr; str : Scanner.String;
  BEGIN
    CASE type.form OF
    | Symtab.bool: e := ASTH.NewBoolConst(FALSE);
    | Symtab.char: e := ASTH.NewCharConst(0X);
    | Symtab.sint, Symtab.int, Symtab.lint: e := ASTH.NewIntConst(0);
    | Symtab.real, Symtab.lreal: e := ASTH.NewRealConst(0.0, type);
    | Symtab.set:  e := ASTH.NewSetConst({});
    | Symtab.string: str[0] := 0X; e := ASTH.NewStringConst(str, 1);
    | Symtab.nil: e := ASTH.NewNil();
    END;
    RETURN e;
  END MakeConstExpr;

  (* Design will only return constant value node, no Ndsgn nodes will be returned *)
  PROCEDURE Design(n : AST.Design; VAR cv : BOOLEAN) : AST.Expr;
    VAR e : AST.Expr; val : Symtab.Const;
  BEGIN e := n;
    CASE n.subcl OF
    |  AST.Dconst: val := n.sym(Symtab.SymbolConst).val;
      CASE n.type.form OF
      | Symtab.bool: e := ASTH.NewBoolConst(val.bool);
      | Symtab.char: e := ASTH.NewCharConst(CHR(val.i0));
      | Symtab.sint, Symtab.int, Symtab.lint: e := ASTH.NewIntConst(val.i0);
      | Symtab.real, Symtab.lreal: e := ASTH.NewRealConst(val.real, n.type);
      | Symtab.set:  e := ASTH.NewSetConst(val.set);
      | Symtab.string: e := ASTH.NewStringConst(val.ext^, val.i0);
      | Symtab.nil: e := ASTH.NewNil();
      END;
    ELSE e := MakeConstExpr(n.type); Config.Error(E.NotAConstant); 
    END;
    RETURN e;
  END Design;

  PROCEDURE ConstCheckRealType(f, nr: INTEGER; x: AST.Expr);
    VAR min, max, r: LONGREAL; metric : Symtab.TypeMetric;
  BEGIN metric := Symtab.metrics[f];
    IF f = Symtab.real THEN
      min := metric(Symtab.RealMetric).min; max := metric(Symtab.RealMetric).max;
    ELSE min := metric(Symtab.LRealMetric).min; max := metric(Symtab.LRealMetric).max;
    END;
    
    r := ABS(x.val.real);
    IF (r > max) OR (r < min) THEN Config.Error(nr); x.val.real := 1.0
    ELSIF f = Symtab.real THEN x.val.real := SHORT(x.val.real)  (* single precision *)
    END ;
  END ConstCheckRealType;

  PROCEDURE Cmp(lop, rop : AST.Expr): INTEGER;
    VAR res: INTEGER;
  BEGIN
    CASE lop.type.form OF
    |  Symtab.undef: res := AST.Eeql;
    | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint:
      IF lop.val.i0 < rop.val.i0 THEN res := AST.Elss;
      ELSIF lop.val.i0 > rop.val.i0 THEN res := AST.Egtr;
      ELSE res := AST.Eeql;
      END;
    | Symtab.real, Symtab.lreal:
      IF lop.val.real < rop.val.real THEN res := AST.Elss;
      ELSIF lop.val.real > rop.val.real THEN res := AST.Egtr;
      ELSE res := AST.Eeql;
      END;
    | Symtab.bool:
      IF lop.val.bool # rop.val.bool THEN res := AST.Eneq;
      ELSE res := AST.Eeql;
      END;
    | Symtab.set:
      IF lop.val.set # rop.val.set THEN res := AST.Eneq;
      ELSE res := AST.Eeql;
      END;
    | Symtab.string:
      IF lop.val.ext^ < rop.val.ext^ THEN res := AST.Elss;
      ELSIF lop.val.ext^ > rop.val.ext^ THEN res := AST.Egtr;
      ELSE res := AST.Eeql;
      END
    | Symtab.nil, Symtab.pointer, Symtab.procedure:
      IF lop.val.i0 # rop.val.i0 THEN res := AST.Eneq;
      ELSE res := AST.Eeql;
      END;
    END;
    lop.type := Symtab.booltyp; 
    RETURN res;
  END Cmp;

  PROCEDURE Enot(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN n := fe(n(AST.MExpr).op, cv); n.val.bool := ~n.val.bool; RETURN n;
  END Enot;

  PROCEDURE Euminus(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN (* front end ensures type is numeric or set *)
    n := fe(n(AST.MExpr).op, cv);
    CASE n.type.form OF
    |  Symtab.sint, Symtab.int, Symtab.lint: n.val.i0 := -n.val.i0;
    |  Symtab.real, Symtab.lreal: n.val.real := -n.val.real;
    |  Symtab.set: n.val.set := -n.val.set;
    END;
    RETURN n;
  END Euminus;

  PROCEDURE Euplus(n :AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN (* nop; front end ensures type is numeric or set *) RETURN fe(n(AST.MExpr).op, cv);
  END Euplus;

  PROCEDURE Econvert(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR metric : Symtab.TypeMetric;
  BEGIN
    n := fe(n(AST.MExpr).op, cv); (* front end ensures proper conversions *) 
    n.type := n.type; metric := Symtab.metrics[n.type.form];
    CASE n.type.form OF
    | Symtab.char, Symtab.sint, Symtab.int:
      IF (n.val.i0 < metric(Symtab.OrdMetric).min)
      OR (n.val.i0 > metric(Symtab.OrdMetric).max) THEN 
        n := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge);  
      END;
    | Symtab.lint:
      IF n.type.form IN Symtab.IntSet THEN (* nop; any value is in the proper range *)
      ELSE (* n.type.form IN Symtab.RealSet *) n.val.i0 := ENTIER(n.val.real);
        IF (n.val.real < metric(Symtab.OrdMetric).min) 
        OR (n.val.real > metric(Symtab.OrdMetric).max) THEN  
          n := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge); 
        END;
      END;
    | Symtab.real:
      IF n.type.form IN Symtab.IntSet THEN
        n.val.real := n.val.i0; (* any value is in the proper range *)
      ELSE (* n.type.form = Symtab.lreal *)
        IF (n.val.real < metric(Symtab.RealMetric).min) 
        OR (n.val.real > metric(Symtab.RealMetric).max) THEN  
          n := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge); 
        END;
      END;
    | Symtab.lreal:
      IF n.type.form IN Symtab.IntSet THEN
       n.val.real := n.val.i0; (* any value is in the proper range *)
      (* ELSIF n.type.form = Symtab.real THEN nop; value must be in range *)
      END;
    END;
    RETURN n;
  END Econvert;

  PROCEDURE Etimes(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; t0, t1 : BOOLEAN; lim : LONGINT;
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    CASE n.type.form OF
    |  Symtab.sint, Symtab.int, Symtab.lint:
      IF (lop.val.i0 >= 0) = (rop.val.i0 >= 0) THEN lim := MAX(LONGINT); 
      ELSE lim := MIN(LONGINT); END;
      (* inv: lim <=> overflow limit *)
      IF lop.val.i0 = 0 THEN (* nop *)
      ELSIF rop.val.i0 = 0 THEN lop := rop;
      ELSE (* both operands are not 0 *) lim := lim DIV rop.val.i0; 
        t0 := (lop.val.i0 >= 0) & (lop.val.i0 <= lim); 
        t1 := (lop.val.i0 < 0) & (lop.val.i0 >= lim);
        IF t0 OR t1 THEN lop.val.i0 := lop.val.i0 * rop.val.i0; ASTH.ConstSetIntType(lop);
        ELSE lop := MakeConstExpr(n.type); Config.Error(E.ProductTooLarge);
        END
      END;
    |  Symtab.real, Symtab.lreal: 
      t0 := ABS(rop.val.real) <= 1.0;
      t1 := (ABS(lop.val.real) <= MAX(LONGREAL) / ABS(rop.val.real));
      IF t0 OR t1 THEN
        lop.val.real := lop.val.real * rop.val.real;
        ConstCheckRealType(lop.type.form, E.ProductTooLarge, lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.ProductTooLarge);
      END;
    | Symtab.set: lop.val.set := lop.val.set * rop.val.set;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadTimesOperand);
    END;
    RETURN lop;
  END Etimes;
    
  PROCEDURE Ediv(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF lop.type.form IN {Symtab.sint, Symtab.int, Symtab.lint} THEN
      IF rop.val.i0 # 0 THEN lop.val.i0 := lop.val.i0 DIV rop.val.i0; ASTH.ConstSetIntType(lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DivisionByZero);
      END;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadDivOperand);
    END;
    RETURN lop;
  END Ediv;
    
  PROCEDURE Eslash(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; t0, t1 : BOOLEAN;
  BEGIN
     lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    CASE lop.type.form OF
    |  Symtab.sint, Symtab.int, Symtab.lint:
      IF rop.val.i0 # 0 THEN
        lop.val.real := lop.val.i0 / rop.val.i0;
        ConstCheckRealType(Symtab.real, E.DivisionByZero, lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DivisionByZero);
      END ;
     | Symtab.real, Symtab.lreal:
      t0 := ABS(rop.val.real) >= 1.0; 
      t1 := (ABS(lop.val.real) <= MAX(LONGREAL) * ABS(rop.val.real));
      IF t0 OR t1 THEN 
        lop.val.real := lop.val.real / rop.val.real;
        ConstCheckRealType(lop.type.form, E.DivisionByZero, lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DivisionByZero);
      END;
    |  Symtab.set: lop.val.set := lop.val.set / rop.val.set;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadSlashOperand);
    END;
    RETURN lop;
  END Eslash;
    
  PROCEDURE Emod(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF lop.type.form IN Symtab.IntSet THEN
      IF rop.val.i0 # 0 THEN
        lop.val.i0 := lop.val.i0 MOD rop.val.i0; ASTH.ConstSetIntType(lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DivisionByZero);
      END;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadModOperand);
    END;
    RETURN lop;
  END Emod;
    
  PROCEDURE Eplus(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; t0, t1 : BOOLEAN;
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    CASE lop.type.form OF
    |  Symtab.sint, Symtab.int, Symtab.lint:
      t0 := (rop.val.i0 >= 0) & (lop.val.i0 <= MAX(LONGINT) - rop.val.i0);
      t1 := (rop.val.i0 < 0) & (lop.val.i0 >= MIN(LONGINT) - rop.val.i0);
      IF t0 OR t1 THEN INC(lop.val.i0, rop.val.i0); ASTH.ConstSetIntType(lop)
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.SumTooLarge);
      END
    |  Symtab.real, Symtab.lreal:
      t0 := (rop.val.real >= 0.0) & (lop.val.real <= MAX(LONGREAL) - rop.val.real);
      t1 := (rop.val.real < 0.0) & (lop.val.real >= -MAX(LONGREAL) - rop.val.real);
      IF t0 OR t1 THEN
        lop.val.real := lop.val.real + rop.val.real; 
        ConstCheckRealType(lop.type.form, E.SumTooLarge, lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.SumTooLarge);
      END;
    |  Symtab.set: lop.val.set := lop.val.set + rop.val.set;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadPlusOperand);
    END;
    RETURN lop;      
  END Eplus;
    
  PROCEDURE Eminus(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; t0, t1 : BOOLEAN;
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    CASE lop.type.form OF
    |  Symtab.sint, Symtab.int, Symtab.lint:
      t0 := (rop.val.i0 >= 0) & (lop.val.i0 >= MIN(LONGINT) + rop.val.i0);
      t1 := (rop.val.i0 < 0) & (lop.val.i0 <= MAX(LONGINT) + rop.val.i0);
      IF t0 OR t1 THEN DEC(lop.val.i0, rop.val.i0); ASTH.ConstSetIntType(lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DifferenceTooLarge);
      END;
    |  Symtab.real, Symtab.lreal:
      t0 := (rop.val.real >= 0.0) & (lop.val.real >= -MAX(LONGREAL) + rop.val.real);
      t1 := (rop.val.real < 0.0) & (lop.val.real <= MAX(LONGREAL) + rop.val.real);
      IF t0 OR t1 THEN
        lop.val.real := lop.val.real - rop.val.real;
        ConstCheckRealType(lop.type.form, E.DifferenceTooLarge, lop);
      ELSE lop := MakeConstExpr(n.type); Config.Error(E.DifferenceTooLarge);
      END;
    |  Symtab.set: lop.val.set := lop.val.set - rop.val.set;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadMinusOperand);
    END;
    RETURN lop;    
  END Eminus;
    
  PROCEDURE Eand(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF lop.type.form = Symtab.bool THEN lop.val.bool := lop.val.bool & rop.val.bool;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadAndOperand);
    END;
    RETURN lop;
  END Eand;
    
  PROCEDURE Eor(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF lop.type.form = Symtab.bool THEN lop.val.bool := lop.val.bool OR rop.val.bool;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadOrOperand);
    END;
    RETURN lop;    
  END Eor;
    
  PROCEDURE Eeqlneq(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    lop.val.bool := Cmp(lop, rop) = n.subcl;
    RETURN lop;  
  END Eeqlneq;
    
  PROCEDURE Elssgtr(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF ~(lop.type.form IN {Symtab.bool, Symtab.set, Symtab.nil, Symtab.pointer}) THEN 
      lop.val.bool := Cmp(lop, rop) = n.subcl;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadRelationalTest);
    END;
    RETURN lop;
  END Elssgtr;
    
  PROCEDURE Eleqgeq(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF ~(lop.type.form IN {Symtab.bool, Symtab.set, Symtab.nil, Symtab.pointer}) THEN 
      lop.val.bool := Cmp(lop, rop) # negRelTab[n.subcl - AST.Eeql];
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.BadRelationalTest);
    END;
    RETURN lop;    
  END Eleqgeq;

  PROCEDURE InSetRange(i : LONGINT) : BOOLEAN;
  BEGIN RETURN (i >= 0) & (i <= Symtab.metrics[Symtab.set](Symtab.OrdMetric).max);
  END InSetRange;
    
  PROCEDURE Ein(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN 
    lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    IF InSetRange(lop.val.i0) THEN lop.val.bool := lop.val.i0 IN rop.val.set;
    ELSE lop := MakeConstExpr(n.type); Config.Error(E.IllegalConstValue);
    END;
    RETURN lop;
  END Ein;
    
  PROCEDURE Eupto(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR lop, rop : AST.Expr; 
  BEGIN lop := fe(n(AST.DExpr).lop, cv); rop := fe(n(AST.DExpr).rop, cv); 
    RETURN ASTH.NewSetConst({lop.val.i0..rop.val.i0});
  END Eupto;
    
  PROCEDURE Eis(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN RETURN n;
  END Eis;

  PROCEDURE Estdproc(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR sym : Symtab.SymbolStdProc; args : AST.Arg; lop, rop : AST.Expr; m : Symtab.TypeMetric;
      type : Symtab.Type;
  BEGIN  sym := n(AST.FuncCall).func.sym(Symtab.SymbolStdProc); args := n(AST.FuncCall).args;
    m := Symtab.metrics[n.type.form];
    CASE sym.procno OF
    | Symtab.absfn: lop := fe(args.arg, cv);
      CASE n.type.form OF
      |  Symtab.sint, Symtab.int, Symtab.lint:
        IF (lop.val.i0 > m(Symtab.OrdMetric).min)
         & (lop.val.i0 <= m(Symtab.OrdMetric).max) THEN lop.val.i0 := ABS(lop.val.i0);
        ELSE lop := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge);
        END;
      |  Symtab.real:
        IF (lop.val.real > m(Symtab.RealMetric).min) 
         & (lop.val.real <= m(Symtab.RealMetric).max) THEN lop.val.real := ABS(lop.val.real);
        ELSE lop := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge);
        END;
      |  Symtab.lreal:
        IF (lop.val.real > m(Symtab.LRealMetric).min) 
         & (lop.val.real <= m(Symtab.LRealMetric).max) THEN lop.val.real := ABS(lop.val.real);
        ELSE lop := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge);
        END;
      END;
      
    | Symtab.capfn: 
      lop := fe(args.arg, cv); lop.val.i0 := ORD(CAP(CHR(lop.val.i0)));
    
    | Symtab.oddfn: 
      lop := fe(args.arg, cv); lop.val.bool := ODD(lop.val.i0);
      
    | Symtab.ashfn: 
      lop := fe(args.arg, cv); rop := fe(args.next(AST.Arg).arg, cv);
      lop.val.i0 := ASH(lop.val.i0, rop.val.i0);
      
    | Symtab.ordfn: lop := fe(args.arg, cv);
    
    | Symtab.minfn: type := args.arg.type;
      CASE type.form OF
      | Symtab.bool: 
        lop := ASTH.NewBoolConst(Symtab.metrics[type.form](Symtab.BoolMetric).min);
      | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint, Symtab.set:
        lop := ASTH.NewIntConst(Symtab.metrics[type.form](Symtab.OrdMetric).min);
      | Symtab.real:
        lop := ASTH.NewRealConst(Symtab.metrics[type.form](Symtab.RealMetric).min, Symtab.realtyp);
      | Symtab.lreal:
        lop := ASTH.NewRealConst(Symtab.metrics[type.form](Symtab.LRealMetric).min, Symtab.lrltyp);
      END;
      
    | Symtab.maxfn: type := args.arg.type;
      CASE type.form OF
      | Symtab.bool: 
        lop := ASTH.NewBoolConst(Symtab.metrics[type.form](Symtab.BoolMetric).max);
      | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint, Symtab.set:
        lop := ASTH.NewIntConst(Symtab.metrics[type.form](Symtab.OrdMetric).max);
      | Symtab.real:
        lop := ASTH.NewRealConst(Symtab.metrics[type.form](Symtab.RealMetric).max, Symtab.realtyp);
      | Symtab.lreal:
        lop := ASTH.NewRealConst(Symtab.metrics[type.form](Symtab.LRealMetric).max, Symtab.lrltyp);
      END;
    
    | Symtab.chrfn:
      lop := fe(args.arg, cv); 
      IF (lop.val.i0 < m(Symtab.OrdMetric).min) OR (lop.val.i0 > m(Symtab.OrdMetric).max) THEN
        lop := MakeConstExpr(n.type); Config.Error(E.NumberTooLarge);
      END;
    
    | Symtab.shortfn, Symtab.longfn: (* Supposed to be Econvert node *) ASSERT(FALSE, 1025);
    
    | Symtab.sizefn: 
      ASSERT(args.arg.type.size # Symtab.metrics[Symtab.undef].size); (* size must be known *)
      lop := ASTH.NewIntConst(args.arg.type.size);
    
    ELSE (* not a standard procedure which can be a constant *)
      (* SYSTEM standard procedures are not constant folded because they are system dependent *)
      RETURN n; 
    END;
    RETURN lop;
  END Estdproc;

  PROCEDURE Ecall(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR func : AST.Design;
  BEGIN 
    func := n(AST.FuncCall).func;
    IF func.subcl = AST.Dstdproc THEN RETURN Estdproc(n, cv);
    ELSE RETURN n; (* not a standard procedure so it cannot be a constant expression *)
    END;
  END Ecall;
    
  PROCEDURE Econst(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN RETURN n; (* this is not an error condition, but a true constant value *)
  END Econst;
    
  PROCEDURE Ecast(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN RETURN n; (* SYSTEM.VAL can only be done on designators *)
  END Ecast;
    
  PROCEDURE Eadr(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN RETURN n; (* 'address-of' node will only be generated on designators *)
  END Eadr;
    
  PROCEDURE Expr(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
    VAR metric : Symtab.TypeMetric; op : AST.Expr;
  BEGIN 
    (* a processor for a node which cannot be a constant expression 
     * should return itself to cause an error to be output
     *)
    CASE n.subcl OF
    |  AST.Enot: op := Enot(n, cv);
    |  AST.Euminus: op := Euminus(n, cv);
    |  AST.Euplus: op := Euplus(n, cv);
    |  AST.Econvert: op := Econvert(n, cv);
    |  AST.Etimes: op := Etimes(n, cv);
    |  AST.Ediv: op := Ediv(n, cv);
    |  AST.Eslash: op := Eslash(n, cv);
    |  AST.Emod: op := Emod(n, cv);
    |  AST.Eplus: op := Eplus(n, cv);
    |  AST.Eminus: op := Eminus(n, cv);
    |  AST.Eand: op := Eand(n, cv);
    |  AST.Eor: op := Eor(n, cv);
    |  AST.Eeql, AST.Eneq: op := Eeqlneq(n, cv);
    |  AST.Elss, AST.Egtr: op := Elssgtr(n, cv);
    |  AST.Eleq, AST.Egeq: op := Eleqgeq(n, cv);
    |  AST.Ein: op := Ein(n, cv);
    |  AST.Eupto: op := Eupto(n, cv);
    |  AST.Eis: op := Eis(n, cv);
    |  AST.Ecall: op := Ecall(n, cv);
    |  AST.Econst: op := Econst(n, cv);
    |  AST.Ecast: op := Ecast(n, cv);
    |  AST.Eadr: op := Eadr(n, cv);
    END;
    ASSERT(op.class = AST.Nexpr, 1024);
    op.type := n.type;
    RETURN op;
  END Expr;

  PROCEDURE fe(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr; (* internal fold expression *)
    VAR class, subcl : SHORTINT; op : AST.Expr;
  BEGIN
    class := n.class; subcl := n.subcl;
    CASE n.class OF
    |  AST.Ndsgn:  op := Design(n(AST.Design), cv);
    |  AST.Nexpr:  op := Expr(n(AST.Expr), cv);
    ELSE op := NIL; (* nop; error output at end of this routine *)
    END;
    IF (op = NIL) OR ~(AST.constant IN op.flags) THEN op := MakeConstExpr(n.type); cv := FALSE;
    ELSE op.type := n.type; (* front end ensures the tree has correct type structure *)
    END;
    RETURN op;
  END fe;
  
  (* post: cv = TRUE -> input tree is a 'constant value' (cv) *)
  (* post: cv = FALSE -> input tree is not a 'constant value' *)
  PROCEDURE FoldExpression*(n : AST.Expr; VAR cv : BOOLEAN) : AST.Expr;
  BEGIN cv := TRUE; RETURN fe(n, cv); 
  END FoldExpression;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleEnd;

  PROCEDURE Init;
  BEGIN
     (* negative relational tests *)
    NEW(negRelTab, AST.Egeq - AST.Eeql + 1);
    negRelTab[AST.Eeql - AST.Eeql] := AST.Eneq; negRelTab[AST.Eneq - AST.Eeql] := AST.Eeql;
    negRelTab[AST.Elss - AST.Eeql] := AST.Egeq; negRelTab[AST.Eleq - AST.Eeql] := AST.Egtr;
    negRelTab[AST.Egtr - AST.Eeql] := AST.Eleq; negRelTab[AST.Egeq - AST.Eeql] := AST.Elss;
    
    Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;
  
BEGIN Init;
END O3ConstExpression.
