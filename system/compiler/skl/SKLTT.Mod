MODULE SKLTT; (* tree traversal *)
IMPORT
  ST:=SKLST,
  T:=SKLT, 
  TB:=SKLTB, 
  CGL:=SKLCGL, 
  CGH:=SKLCGH, 
  OPM:=SKLMD, 
  OPS:=SKLOS;

  CONST
    DefaultLabel = NIL;

  VAR
    TreeCC : ARRAY T.Egeq - T.Eeql + 1 OF SHORTINT; (* Tree expression to condition code mapping *)
    TreeErr : BOOLEAN;
    ExitLabel, ReturnLabel : CGL.Label;
    CommonDesign : CGL.Item;

  PROCEDURE ^ expr(n : T.Expr; VAR x : CGL.Item);

  PROCEDURE InitConstItem(c : T.Expr; VAR x : CGL.Item);
  BEGIN CGL.InitItem(x); x.mode := CGL.Iconst; x.type := c.type; x.val := c.val^;
  END InitConstItem;

  PROCEDURE dsgn(n : T.Design; VAR x : CGL.Item);
    VAR y : CGL.Item; type : ST.Type; td : ST.SymbolTypeDesc;
  BEGIN
    OPM.SetSourceTextPos(n.pos);
    ASSERT(n.class = T.Ndsgn, 1000);
    CGL.InitItem(x);
    CASE n.subcl OF
    |  T.Danon:
       ASSERT(FALSE, 1001);

    |  T.Dstdproc, T.Dfwdproc:
       ASSERT(FALSE, 1002);

    |  T.Dtype: (* use type descriptor, iff proper type *)
       type := n.type;
       td := ST.GetTD(type);
       IF td # NIL THEN (* we have a type descriptor to deal with *)
         CGH.MakeVar(x, td, ST.linttyp);
         x.mnolev := x.sym.mnolev;
         CGH.TakeAddress(x, {}, FALSE);
         x.type := x.sym(ST.SymbolTypeDesc).described;
         RETURN; (* skip x.type assignment *)
       ELSE
         x.type := n.type;
       END;

    |  T.Dscope, T.Dmodule:
       ASSERT(FALSE, 1003);

    |  T.Dvar:
       x.mode := CGL.Ivar;
       CGH.CompleteItem(n, x);
       x.type := n.type;

    |  T.Dpar:
       IF n.type.form IN CGH.PassedByAddress THEN
         x.mode := CGL.Ivarpar;
       ELSE
         x.mode := CGL.Ipar;
       END;
       CGH.CompleteItem(n, x);
       x.type := n.type;

    |  T.Dvarpar:
       x.mode := CGL.Ivarpar;
       CGH.CompleteItem(n, x);
       x.type := n.type;

    |  T.Dconst:
       IF n.type.form IN {ST.string} THEN (* only constants which are allocated addresses *)
         x.mode := CGL.Ivar;
         CGH.CompleteItem(n, x);
       ELSE
         x.mode := CGL.Iconst;
         CGH.CompleteItem(n, x);
       END;
       x.type := n.type;

    |  T.Dlproc, T.Dxproc, T.Dcproc, T.Diproc:
       ASSERT(FALSE, 1004);(* subsumed by T.Dproc *)

    |  T.Dmethod:
       x.mode := CGL.Imethod;
       CGH.CompleteItem(n, x);
       x.methno := x.sym(ST.SymbolProc).methno; (* VMT reg & super call done later *)
       x.type := n.type;

    |  T.Dfield:
       dsgn(n(T.Field).base, x);
       CGH.Field(x, n(T.Field).offset + n.sym.adr);
       x.type := n.type; (* sym field remains as reference to base *)

    | T.Dderef:
      dsgn(n(T.Deref).base, x);
      CGH.Deref(x);
      x.type := n.type;

    | T.Dcast: (* Change type of node.  Used for synthetic index. *)
      dsgn(n(T.DesignCast).node, x);
      x.type := n.type;
      
    | T.Dindex:
      ASSERT((n(T.Index).base # NIL) & (n(T.Index).index # NIL));
      dsgn(n(T.Index).base, x);
      expr(n(T.Index).index, y);
      CGH.Index(x, y);
      x.type := n.type;

    | T.Diguard, T.Deguard:
      dsgn(n(T.Guard).design, x);
      td := ST.GetTD(n.type); (* ensure type descriptor imported by Object file *)
      CGH.MakeVar(y, ST.GetTD(n.type), ST.sysptrtyp);
      y.mnolev := y.sym.mnolev;
      CGH.TypeGuard(x, y, n.subcl = T.Deguard);
      x.type := n.type;

    |  T.Dproc:
      CASE n.sym.kind OF
      | ST.lproc: x.mode := CGL.Ilproc;
      | ST.xproc: x.mode := CGL.Ixproc;
      | ST.cproc: x.mode := CGL.Icproc;
      | ST.iproc: x.mode := CGL.Iiproc;
      END;
      CGH.CompleteItem(n, x);
      x.type := n.sym.type;

    | T.Ddarrdesc, T.Darrdesc, T.Drecdesc:
      x.mode := CGL.Iadr;
      CGH.CompleteItem(n, x);
      x.type := n.type;

    | T.Dcommon:
      x := CommonDesign;
      INCL(x.flags, CGL.common);
      x.type := n.type;
    END;
  END dsgn;

  PROCEDURE expr(n : T.Expr; VAR x : CGL.Item);

    PROCEDURE MOp(n : T.MExpr; VAR x : CGL.Item);
      VAR f : SHORTINT;
    BEGIN
      expr(n.op, x);
      CASE n.subcl OF
      |  T.Euplus: (* nop *)
      |  T.Enot: CGH.Not(x);
      |  T.Euminus: CGH.Negate(x);
      |  T.Econvert:
        f := n.type.form;
        IF f = ST.set THEN CGH.SetElem(x);
        ELSE CGH.Convert(x, f, x.type.form);
        END;
      |  T.Eaddress: CGH.TakeAddress(x, CGL.RegWord, FALSE);
      |  T.Einterfere: CGH.Interfere(x, n.regs);
      |  T.Eload: CGH.LoadInto(x, n.regs);
      |  T.Ecast: x.type := n.type;
      END;
    END MOp;

    PROCEDURE IsTest(n : T.IsTest; VAR x : CGL.Item);
      VAR y : CGL.Item;
    BEGIN expr(n.var, x); dsgn(n.istype, y); CGH.IsTest(x, y);
    END IsTest;
    
    PROCEDURE DOp(n : T.DExpr; VAR x : CGL.Item);
      VAR y : CGL.Item; l : T.Expr;
    BEGIN
      IF n.subcl IN {T.Eand, T.Eor, T.Eeql, T.Eneq, T.Elss, T.Eleq, T.Egtr, T.Egeq}  THEN
        (* no 'defer' evaluation nodes allowed in relational expressions & IS expressions *)
        ASSERT((n.lop.class # T.Nexpr) OR
               (n.lop.subcl IN {T.Econst, T.Ecall}) OR
               (n.lop.subcl # T.Einterfere) & ~(T.defer IN n.lop.flags));
        expr(n.lop, x);
        IF n.subcl = T.Eand THEN
          CGH.ConditionalAnd(x);
        ELSIF n.subcl = T.Eor THEN
          CGH.ConditionalOr(x);
        ELSIF n.subcl IN {T.Eeql, T.Eneq, T.Elss, T.Eleq, T.Egtr, T.Egeq} THEN
          CGH.Relation(x);
        END;
        expr(n.rop, y);
      ELSE
        l := n.lop;
        IF ((l.class = T.Nexpr) &
            (l.subcl = T.Einterfere) & (T.defer IN l.flags)) THEN
          expr(n.rop, y);
          expr(n.lop, x);
        ELSE
          expr(n.lop, x);
          expr(n.rop, y);
        END;
      END;
      CASE n.subcl OF
      |  T.Etimes: CGH.Mul(x, y);
      |  T.Ediv: CGH.Div(x, y);
      |  T.Eslash: CGH.Slash(x, y);
      |  T.Emsk: CGH.Msk(x, y);
      |  T.Emod: CGH.Mod(x, y);
      |  T.Eplus: CGH.Add(x, y);
      |  T.Eminus: CGH.Sub(x, y);
      |  T.Eand: CGH.And(x, y);
      |  T.Eor: CGH.Or(x, y);
      |  T.Eeql..T.Egeq: CGH.Compare(x, y, TreeCC[n.subcl - T.Eeql]);
      |  T.Ein: CGH.SetIn(x, y);
      |  T.Eupto: CGH.SetRange(x, y);
      |  T.Elsh: CGH.Lsh(x, y);
      |  T.Erot: CGH.Rot(x, y);
      |  T.Eash: CGH.Ash(x, y);
      END;
      x.type := n.type; (* SYSTEM.VAL can set a node type, not the expression
                         * type: S.VAL(LONGINT, S.VAL(SET, x) - {1}) + 100 *)
    END DOp;

    PROCEDURE PassParams(args : T.Arg; method : BOOLEAN; VAR proc : CGL.Item) : INTEGER;
      VAR x : CGL.Item; n : T.Node; fp : ST.Symbol; bytes, b  : INTEGER;
    BEGIN
      ASSERT(proc.type.form = ST.procedure);
      bytes := 0;
      IF proc.type.sysflag IN {OPM.StdCallVal, OPM.CCallVal} THEN
        T.ReverseArgList(args);
        ST.ReverseSymbolList(proc.type(ST.Procedure).parms);
      END;
      n := args;
      fp := ST.FirstParm(proc.type(ST.Procedure));
      IF method THEN
        expr(n(T.Arg).arg, x);
        CGH.LoadVMT(x, proc, n(T.Arg).arg.subcl = T.Dderef);
      END;
      WHILE (n # NIL) & (fp # NIL) DO
        expr(n(T.Arg).arg, x);
        b := CGH.Param(x, fp, n(T.Arg).arg.subcl = T.Dderef);
        fp := ST.NextParm(fp);
        n := n.next;
        INC(bytes, b);
      END;
      ASSERT((fp = NIL) = (n = NIL)); (* fp & n should reach NIL at the same time *)

      IF proc.type.sysflag IN {OPM.StdCallVal, OPM.CCallVal} THEN
        T.ReverseArgList(args);
        ST.ReverseSymbolList(proc.type(ST.Procedure).parms);
      END;
      RETURN bytes;
    END PassParams;

    PROCEDURE Call(n : T.FuncCall; VAR x : CGL.Item);
      VAR
        call : T.Design;
        regs : CGL.SavedRegInfo;
        proc : ST.Symbol;
        parmbytes : INTEGER;
    BEGIN
      CGL.SaveRegisters(regs);
      call := n.func;
      dsgn(call, x);
      ASSERT((call.type.form = ST.procedure) & (x.type = call.type), 128);
      IF T.super IN n.func.flags THEN
        INCL(x.flags, CGL.super); (* super call *)
      END;

      (*
       * 97.09.17:
       * Be aware that there is a defect in SaveRegisters that will
       * save and free registers used for the designator part of
        the call subtree -- see SaveRegisters
      *)
      IF x.mode IN {CGL.Ilproc..CGL.Iiproc} THEN (* proc *) 
        parmbytes := PassParams(n.args, call.subcl = T.Dmethod, x);
        CGH.Call(x, x.sym(ST.SymbolProc));
      ELSE (* proc variable *)
        parmbytes := PassParams(n.args, call.subcl = T.Dmethod, x);
        CGH.Call(x, NIL);
      END;

      IF x.type.sysflag = OPM.CCallVal THEN
        CGH.CRemoveParms(parmbytes);
      END;
      x.type := x.type(ST.Procedure).result;
      CGL.RestoreRegisters(regs, x);
    END Call;

    PROCEDURE StandardProc(n : T.FuncCall; VAR x : CGL.Item);
      VAR
        procno : SHORTINT;
        args : T.Arg;
        arg0, arg1, arg2 : T.Expr;
        a1, a2 : CGL.Item;
        base : ST.Type;
        td : ST.SymbolTypeDesc;

      PROCEDURE CalcDynArrSize(VAR size : CGL.Item; n : T.Arg; type : ST.Type; dim : LONGINT);
      BEGIN
        IF type.form = ST.dynarr THEN
          CalcDynArrSize(size, n.next(T.Arg), type(ST.Array).of, dim + 1);
        ELSE (* element type *)
          CGH.MakeConstItem(size, type.size, ST.linttyp);
        END;
        expr(T.ArgN(n, 0), x);
        CGH.PushDynArrDim(x, size, type);
        CGL.Release(x);
      END CalcDynArrSize;

    BEGIN
      procno := n.func.sym(ST.SymbolStdProc).procno; args := n.args;
      arg0 := T.ArgN(args, 0); expr(arg0, x);
      CASE procno OF
      |  ST.newfn:
        td := ST.GetTD(arg0.type); (* td = NIL => no type descriptor for this type; otherwise ensure it is ST.used & imported *)
        IF arg0.type(ST.Pointer).to.form = ST.dynarr THEN
          base := arg0.type(ST.Pointer).to(ST.Array).of; a2 := x;
          CalcDynArrSize(a1, args.next(T.Arg), base, 0);
          CGH.StdNewDynArray(a2, a1);
        ELSIF arg0.type(ST.Pointer).to.form = ST.array THEN CGH.StdNewStaticArray(x);
        ELSE CGH.StdNew(x);
        END;

      |  ST.getfn, ST.putfn:
         arg1 := T.ArgN(args, 1);
         expr(arg1, a1);
         CGH.StdGetPut(x, a1, procno = ST.getfn);

      |  ST.getrfn, ST.putrfn:
        CGL.MarkRegSetUsed({x.val.i0});
        arg1 := T.ArgN(args, 1); expr(arg1, a1);
        CGL.MarkRegSetFree({x.val.i0});
        CGH.StdGetPutReg(x, a1, procno = ST.getrfn);

      |  ST.sysnewfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdSysNew(x, a1);
      |  ST.movefn: arg1 := T.ArgN(args, 1); arg2 := T.ArgN(args, 2); expr(arg1, a1); expr(arg2, a2); CGH.StdSysMove(x, a1, a2);
      |  ST.haltfn: CGH.StdHalt(x);
      |  ST.assertfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdAssert(x, a1);
      |  ST.incfn, ST.decfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdIncDec(x, a1, procno = ST.incfn);
      |  ST.inclfn, ST.exclfn:
         arg1 := T.ArgN(args, 1);
         expr(arg1, a1);
         CGH.StdInclExcl(x, a1, procno = ST.inclfn);
      |  ST.copyfn:
         arg1 := T.ArgN(args, 1);
         expr(arg1, a1);
         CGH.StdCopy(x, a1);
      | ST.absfn: CGH.StdAbs(x);
      | ST.capfn: CGH.StdCap(x);
      | ST.oddfn: CGH.StdOdd(x);
      | ST.adrfn: CGH.TakeAddress(x, CGL.RegWord, FALSE);
      | ST.ashfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdAsh(x, a1);
      | ST.lshfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdLsh(x, a1);
      | ST.rotfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdRot(x, a1);
      | ST.lenfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdLen(x, a1);
      | ST.bitfn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.StdBit(procno, x, a1);
      |  ST.bitrfn, ST.bitsfn:
         arg1 := T.ArgN(args, 1);
         expr(arg1, a1);
         CGH.StdBitSetReset(procno = ST.bitsfn, x, a1);
      | ST.valfn: HALT(148); (* handled by front end *)
      | ST.minfn: HALT(147); (* handled by front end *)
      | ST.maxfn:  HALT(146); (* handled by front end *)
      | ST.ordfn, ST.chrfn, ST.shortfn, ST.longfn, ST.entierfn: HALT(150); (* front end turns it into an Econvert node *)
      | ST.sizefn: HALT(149); (* handled by front end *)
      |  ST.memrfn, ST.memwfn:
        arg1 := T.ArgN(args, 1); arg2 := T.ArgN(args, 2); expr(arg1, a1); expr(arg2, a2);
        CGH.StdMemRW(x, a1, a2, procno = ST.memrfn);
      |  ST.finalizefn: arg1 := T.ArgN(args, 1); expr(arg1, a1); CGH.Finalize(x, a1);
      END;
      x.type := n.type; (* since the procedure node has a Procedure type, the actual result type of the procedure is the same as the call node *)
    END StandardProc;

  BEGIN ASSERT(n.class IN {T.Nexpr, T.Ndsgn});
    OPM.SetSourceTextPos(n.pos);
    IF n.class = T.Ndsgn THEN dsgn(n(T.Design), x);
    ELSIF n.subcl = T.Econst THEN InitConstItem(n, x); CGH.CompleteItem(n, x);
    ELSIF n.subcl = T.Ecall THEN CGL.InitItem(x);
      IF n(T.FuncCall).func.subcl = T.Dstdproc THEN StandardProc(n(T.FuncCall), x);
      ELSE Call(n(T.FuncCall), x);
      END;
      CGH.CompleteItem(n, x);
    ELSIF n.subcl IN T.MonoOps THEN MOp(n(T.MExpr), x);
    ELSIF n.subcl = T.Eis THEN IsTest(n(T.IsTest), x);
    ELSE DOp(n(T.DExpr), x);
    END;
  END expr;

  PROCEDURE stmt(n : T.Node);
  
    PROCEDURE Sassign(n : T.Assign);
      VAR l, r : CGL.Item;
    BEGIN
      expr(n.lvalue, l);
      IF T.IsCommonDesign(n.lvalue, n.rvalue) THEN
        CommonDesign := l;
        n.rvalue(T.DExpr).lop.subcl := T.Dcommon;
        expr(n.rvalue, r);
        CGL.Release(r); (* assignment done in expr *)
      ELSE
        expr(n.rvalue, r);
        CGH.Assign(l, r);
      END;
    END Sassign;
  
    PROCEDURE Scase(n : T.Case);
      VAR l : CGL.Item; low, high : LONGINT; CaseTab, else, entry, exit : CGL.Label; of : T.CaseStat; c : T.Node; b : T.CaseBounds;
    BEGIN of := n.of; low := of.range.i0; high := of.range.i1; exit := CGL.NewLabel();
      expr(n.expr, l); CGH.Case(l, low, high, CaseTab, else); stmt(of.else); CGL.Jmp(exit);
      c := of.case;
      WHILE c # NIL DO
        entry := CGL.NewLabel(); CGL.SetLabel(entry); stmt(c(T.SingleCase).stmt); CGL.Jmp(exit);
        b := c(T.SingleCase).bounds;
        WHILE b # NIL DO
          CGL.SetCaseEntry(b.bound.i0 - low, b.bound.i1 - low, CaseTab, entry); b := b.next;
        END;
        c := c.next;
      END;
      CGL.SetLabel(exit); CGL.SetCaseElse(CaseTab, low, high, else);
    END Scase;
  
    PROCEDURE Sexit(n : T.StmtList);
    BEGIN CGL.Jmp(ExitLabel);
    END Sexit;
  
    PROCEDURE Swith(n : T.With);
      VAR
        wn : T.Node;
        wl : T.WithList;
        next, exit : CGL.Label;
        control, type : CGL.Item;
        R0 : CGL.Item;
        td : ST.SymbolTypeDesc;
    BEGIN
      R0.mode   := CGL.Icoc;
      R0.reg    := 0;
      R0.cc     := CGL.ccAW;
      R0.type   := ST.undftyp;
      R0.mnolev := 0;

      wn := n.wstat;
      exit := CGL.NewLabel();
      WHILE wn # NIL DO
        wl := wn(T.WithList);
        dsgn(wl.control, control);
        dsgn(wl.testtype, type);
        td := ST.GetTD(wl.testtype.type);
        CGH.IsTest(control, type);
        next := CGL.NewLabel();
        CGH.JmpF(control, next);
        stmt(wl.body);
        CGL.PutJump(CGL.ccAW, R0 (* ignored *), exit);
        CGL.SetLabel(next);
        wn := wn.next;
      END;
      stmt(n.else);
      CGL.SetLabel(exit);
    END Swith;
  
    PROCEDURE Sassert(n : T.Halt);
      VAR e, v : CGL.Item;
    BEGIN expr(n.expr, e); expr(n.val, v); CGH.StdAssert(e, v);
    END Sassert;
  
    PROCEDURE Senter(n : T.Enter);
      VAR
        x, halt : CGL.Item;
        y : T.Node;
        proc : ST.SymbolProc;
        sym : ST.Symbol;
        name  : OPS.FullName;
        nofTD : LONGINT;
        info : ST.ProcessScopeInfo;

    BEGIN
      CGL.Align(CGL.segCode, CGL.AlignProc);
      ReturnLabel := CGL.NewLabel();
      IF T.main IN n.flags THEN (*enter module *)
        sym :=  ST.FindInThisScope(n.info(ST.SymbolScope), n.info.name^);
        proc := sym(ST.SymbolProc);
        CGH.Enter(proc); (* open stack block *)
        
        IF OPM.CGInitImportedUnits THEN
          y := n.import;
          WHILE y # NIL DO
            IF ~(T.noinit IN y.flags) THEN
              x.mode := CGL.Ixproc;
              x.sym := y(T.Import).module;
              x.mnolev := x.sym.mnolev;
              x.type := x.sym.type;
              CGH.InitImportedUnit(x);
            END;
             y := y.next;
          END;
        END;
        
        IF OPM.CGInitTypeDescriptors THEN
          nofTD := 0;
          y := n.inittd;
          WHILE y # NIL DO
            CGH.InitTypeDescriptor(nofTD, y(T.InitTD).td);
            INC(nofTD);
            y := y.next;
          END;
        END;
        IF OPM.CGInitPointersGlobal THEN
          CGH.InitPointersGlobal(n.info(ST.SymbolScope));
        END;
        stmt(n.body);
        CGL.SetLabel(ReturnLabel);
        CGH.Leave(proc); (* close stack block *)
        CGL.GenRefPoint(proc);
        CGL.GenRefName(sym.name^);
        ST.ProcessScope(n.info(ST.SymbolScope), CGL.GenRefs, info);
        IF n.nestedproc # NIL THEN
          INC(CGL.level);
          stmt(n.nestedproc);
          DEC(CGL.level);
        END;
      ELSE (* enter procedure *)
        proc := n.info(ST.SymbolProc);
        CGH.Enter(proc); (* open stack block *)
        IF OPM.CGInitPointersLocal THEN
          CGH.InitPointersLocal(n.info(ST.SymbolProc));
        END;
        stmt(n.body);
        IF n.info.type(ST.Procedure).result # ST.notyp THEN
          InitConstItem(TB.NewIntConst(OPM.HaltFunc), halt);
          CGH.StdHalt(halt);
        END;
        CGL.SetLabel(ReturnLabel);
        CGH.Leave(proc); (* close stack block *)
        ST.GetFullProcedureName(proc, name);
        CGL.GenRefPoint(proc);
        CGL.GenRefName(name);
        ST.ProcessScope(proc.scope, CGL.GenRefs, info);
        IF n.nestedproc # NIL THEN
          INC(CGL.level);
          stmt(n.nestedproc);
          DEC(CGL.level);
        END;
      END;
    END Senter;

    PROCEDURE Scall(n : T.ProcCall);
      VAR x : CGL.Item;
    BEGIN expr(n.call, x);
    END Scall;
    
    PROCEDURE Sifelse(n : T.IfElse);
      VAR exit, lab : CGL.Label; ife : T.IfBody; cond : CGL.Item;
    BEGIN exit := CGL.NewLabel();
      ife := n.ifstat;
      WHILE ife # NIL DO
        lab := CGL.NewLabel();
        expr(ife.cond, cond);
        CGH.JmpF(cond, lab);
        CGL.FixJcc(cond.jump.true);
        stmt(ife.stmt);
        CGL.Jmp(exit);
        CGL.SetLabel(lab);
        ife := ife.elsif;
      END;
      stmt(n.else);
      CGL.SetLabel(exit);
    END Sifelse;

    PROCEDURE Srepeat(n : T.WhileRepeat);
      VAR top : CGL.Label; l : CGL.Item;
    BEGIN top := CGL.NewLabel(); CGL.SetLabel(top); stmt(n.body); expr(n.cond, l); CGH.JmpF(l, top);
    END Srepeat;
  
    PROCEDURE Swhile(n : T.WhileRepeat);
      VAR cond : CGL.Item; top, bot : CGL.Label;
    BEGIN
      top := CGL.NewLabel(); bot := CGL.NewLabel(); CGL.Jmp(bot); CGL.SetLabel(top);
      stmt(n.body); CGL.SetLabel(bot); expr(n.cond, cond); CGH.JmpT(cond, top);
    END Swhile;
  
    PROCEDURE Sloop(n : T.Loop);
      VAR s, top : CGL.Label;
    BEGIN s := ExitLabel; ExitLabel := CGL.NewLabel(); top := CGL.NewLabel(); CGL.SetLabel(top);
      stmt(n.body); CGL.Jmp(top); CGL.SetLabel(ExitLabel); ExitLabel := s;
    END Sloop;
  
    PROCEDURE Sreturn(n : T.Return);
      VAR v : CGL.Item;
    BEGIN
      IF n.expr # NIL THEN
        expr(n.expr, v);
        CGH.Return(n.proc, v);
      END;
      CGL.Jmp(ReturnLabel);
    END Sreturn;
  
    PROCEDURE Sfor(n : T.For);
      VAR
        control, result, v, upper, inc : CGL.Item;
        bot, top : CGL.Label;
        cc : SHORTINT;
    BEGIN
      top := CGL.NewLabel();
      bot := CGL.NewLabel();
      InitConstItem(TB.NewIntConst(n.step), inc);
      dsgn(TB.NewDesign(n.temp), upper);
      expr(n.upper, v);
      dsgn(n.control, control);
      v.type := control.type;
      CGH.Assign(upper, v);
      expr(n.lower, v);
      v.type := control.type;
      CGH.Assign(control, v);
      CGL.SetLabel(top);
      IF n.step > 0 THEN
        cc := CGL.ccGT;
      ELSE
        cc := CGL.ccLT;
      END;
      result := control;
      CGH.Compare(result, upper, cc);
      CGH.JmpT(result, bot);
      stmt(n.body);
      INCL(control.flags, CGL.common);
      inc.type := control.type;
      result := control;
      CGH.Add(result, inc);
      CGH.Assign(control, result);
      CGL.Jmp(top);
      CGL.SetLabel(bot);
    END Sfor;
  
  BEGIN
    REPEAT
      CGL.StatBegin(n.pos); OPM.SetSourceTextPos(n.pos);
      IF n.class = T.Nstmt THEN
        CASE n.subcl OF
        |  T.Snull: (* nop *)
        |  T.Senter: Senter(n(T.Enter));
        |  T.Sassign: Sassign(n(T.Assign));
        |  T.Scall: Scall(n(T.ProcCall));
        |  T.Sifelse: Sifelse(n(T.IfElse));
        |  T.Scase: Scase(n(T.Case));
        |  T.Swhile: Swhile(n(T.WhileRepeat));
        |  T.Srepeat: Srepeat(n(T.WhileRepeat));
        |  T.Sloop: Sloop(n(T.Loop));
        |  T.Sexit: Sexit(n(T.StmtList));
        |  T.Sreturn: Sreturn(n(T.Return));
        |  T.Swith: Swith(n(T.With));
        |  T.Sfor: Sfor(n(T.For));
        |  T.Sassert: Sassert(n(T.Halt));
        END;
      ELSE TreeErr := TRUE;
      END;
      CGL.StatEnd(n.pos); n := n.next;
    UNTIL (n = NIL) OR (n.class # T.Nstmt);
  END stmt;

  PROCEDURE Module*(n : T.Node; td : T.InitTD; VAR err : BOOLEAN);
  BEGIN
    IF (n.class = T.Nstmt) & (n.subcl = T.Senter) THEN ASSERT(T.main IN n(T.Enter).flags);
      n(T.Enter).inittd := td; (* set up type descriptor initializations for module entry *)
      ExitLabel := DefaultLabel;
      ReturnLabel := DefaultLabel;
      TreeErr := FALSE;
      stmt(n(T.StmtList));
      err := TreeErr;
    ELSE err := TRUE;
    END;
  END Module;

  PROCEDURE ModuleBegin*;
  BEGIN ExitLabel := NIL; ReturnLabel := NIL;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN ExitLabel := NIL; ReturnLabel := NIL;
  END ModuleEnd;

BEGIN
  TreeCC[T.Eeql - T.Eeql] := CGL.ccEQ;
  TreeCC[T.Eneq - T.Eeql] := CGL.ccNE;
  TreeCC[T.Elss - T.Eeql] := CGL.ccLT;
  TreeCC[T.Eleq - T.Eeql] := CGL.ccLE;
  TreeCC[T.Egtr - T.Eeql] := CGL.ccGT;
  TreeCC[T.Egeq - T.Eeql] := CGL.ccGE;
END SKLTT.

