MODULE SKLT; (* Node Types & Tree Building routines *)

IMPORT
  OPS := SKLOS, 
  ST := SKLST, 
  OPM := SKLMD;

  CONST (**** flags ****)
    (* fields
      16..31: reserved for global usage
      00..15: for Node extension usage
    *)
    readonly* = 16;          (* value is read-only *)
                            (* read-only propogates through: *)
                            (*    deref: no  *)
                            (*    field: yes *)
                            (*    array: yes *)
                            (*    guard: yes *)
                            (* read-only applies to: *)
                            (*    assignment : yes *)
                            (*    var-parms  : yes *)
                            (*    val-parms  : no  *)
                            (*    expressions: no  *)
                            (*    method     : no  *)
    constant*  = 17;          (*    (class = Ndsgn) & (subcl = Dconst)
                               OR (class = Nexpr) & (subcl = Econst) *)
                            (* constant propogates through: *)
                            (*    nothing *)
    super*    = 15;          (* super call (Dmethod) *)
    used*     = 15;          (* imported unit is used or not (STimport) *)
    main*      = 15;          (* STenter: module init  *)
    noinit*  = 15;     (* STimport: special unit which should not be initialized *)
    defer* = 15; (* Einterfere: this subtree (always on left) evaluation should occur after the other subtree *)

  TYPE
    NODECLASS* = SHORTINT;
    NODESUBCLASS* = SHORTINT;

  CONST (**** Node classes *)
    Ndsgn* = 0;                              (* Design & extensions *)
    Nstmt* = 1;                              (* StatementList & extensions *)
    Nexpr* = 2;                              (* Expr & extensions (except Design) *)
    Nmisc* = 3;                              (* Miscellaneous nodes *)

  CONST (* constant types which must be allocated and treated like variables *)
    AllocedConsts* = {ST.string};

  CONST (**** designator nodes ****)
    Dbegin*        = 0;
    Danon*        = Dbegin + ST.anon;
    Dvar*          = Dbegin + ST.var;
    Dpar*          = Dbegin + ST.par;
    Dvarpar*      = Dbegin + ST.varpar;
    Dconst*        = Dbegin + ST.const;      (* (type.form IN AllocedConst) & really needs alloc *)
    Dstdproc*      = Dbegin + ST.stdproc;
    Dfwdproc*      = Dbegin + ST.fwdproc;     (* cannot occur in tree *)
    Dlproc*        = Dbegin + ST.lproc;      (* cannot occur in tree *)
    Dxproc*        = Dbegin + ST.xproc;      (* cannot occur in tree *)
    Dcproc*        = Dbegin + ST.cproc;      (* cannot occur in tree *)
    Diproc*        = Dbegin + ST.iproc;      (* cannot occur in tree *)
    Dmethod*      = Dbegin + ST.tproc;
    Dfield*        = Dbegin + ST.field;
    Dtype*        = Dbegin + ST.type;
    Dmodule*      = Dbegin + ST.module;  (* module scope; cannot occur in tree *)
    Dscope*        = Dbegin + ST.scope;
    Ddarrdesc*  = Dbegin + ST.darrdesc;
    Darrdesc*    = Dbegin + ST.arrdesc;
    Drecdesc*    = Dbegin + ST.recdesc;
    Dderef*        = ST.nofSymbols + 0;
    Dindex*        = ST.nofSymbols + 1;
    Diguard*      = ST.nofSymbols + 2;
    Deguard*      = ST.nofSymbols + 3;
    Dproc*        = ST.nofSymbols + 4;              (* subsumes {Dfwdproc..Diproc} *)
    Dcommon* = ST.nofSymbols + 5; (* common designator in variable := variable [op] expr *)
    Dlast*        = ST.nofSymbols + 6;

    (* designators which can be assigned, or yield, a value *)
    RValueSet* = {Dvar..Dconst, Dfield, Dderef..Deguard};
    LValueSet* = {Dvar..Dvarpar, Dfield, Dderef..Deguard};

    (*
      LValue(n) <=>          (n.class = Ndsgn) & (n.subcl IN LValueSet) & ~(readonly IN flags)
                              OR  (n.class = Nexpr) & (n.subcl = Ecast) & LValue(n(MExpr).op)
      ~LValue(n) <=>  (n.class # Ndsgn) OR ~(n.subcl IN LValueSet) (an Ecast node does not have to be an LValue)

      RValue(n) <=> (n.class = Nexpr) OR (n.class = Ndsgn) & (n.subcl IN DsgnValueSet)
      Since an RValue only applies to Expr and its descendants, we can say:
        inv:  n.class IN {Nexpr, Ndsgn}
        inv:  n.class = Nexpr => RValue
        RValue(n) <=>    (n.class # Ndsgn) OR (n.subcl IN RValueSet)
                  equiv  (n.class = Nexpr) OR (n.subcl IN RValueSet)
        ~RValue(n) <=>  (n.class = Ndsgn) & ~(n.subcl IN RValueSet)
    *)

  CONST  (**** statement subclasses ****)
    Sbegin*        = 0;
    Snull*        = Sbegin + 00;
    Senter*        = Sbegin + 01;
    Sassign*      = Sbegin + 02;
    Scall*        = Sbegin + 03;
    Sifelse*      = Sbegin + 04;
    Scase*        = Sbegin + 05;
    Swhile*        = Sbegin + 06;
    Srepeat*      = Sbegin + 07;
    Sloop*        = Sbegin + 08;
    Sexit*        = Sbegin + 09;
    Sreturn*      = Sbegin + 10;
    Swith*        = Sbegin + 11;
    Sfor*          = Sbegin + 12;
    Sassert*      = Sbegin + 13;
    Slast*        = Sbegin + 13 + 1;

  CONST (**** expression subclasses ****)
    Ebegin*        = 0;
    Enot*          = Ebegin + 00;
    Euminus*      = Ebegin + 01;
    Euplus*        = Ebegin + 02;
    Econvert*      = Ebegin + 03;
    Etimes*        = Ebegin + 04;
    Ediv*          = Ebegin + 05;
    Eslash*        = Ebegin + 06;
    Emsk*          = Ebegin + 07;
    Emod*          = Ebegin + 08;
    Eplus*        = Ebegin + 09;
    Eminus*        = Ebegin + 10;
    Eand*          = Ebegin + 11;
    Eor*          = Ebegin + 12;
    Eeql*          = Ebegin + 13;
    Eneq*          = Ebegin + 14;
    Elss*          = Ebegin + 15;
    Eleq*          = Ebegin + 16;
    Egtr*          = Ebegin + 17;
    Egeq*          = Ebegin + 18;
    Ein*          = Ebegin + 19;
    Eupto*        = Ebegin + 20;            (* set range *)
    Eis*          = Ebegin + 21;
    Ecall*        = Ebegin + 22;            (* function call *)
    Econst*        = Ebegin + 23;            (* ~(type.form IN AllocedConst) & (class = Ndsgn) *)
    Eaddress*      = Ebegin + 24;            (* address-of operator *)
    Elsh*            = Ebegin + 25;
    Erot*            = Ebegin + 26;
    Eash*          = Ebegin + 27;
    Einterfere*  = Ebegin + 28;
    Eload*      = Ebegin + 29;
    Ecast* = Ebegin + 30;        (* SYSTEM.VAL *)
    Eruntime* = Ebegin + 31;  (* runtime checks for expressions *)
    Elast*        = Ebegin + 31 + 1;

  CONST
    MonoOps* = {Enot, Euminus, Euplus, Econvert, Eaddress, Einterfere, Eload, Ecast};
    DualOps* = {Etimes..Eupto, Elsh, Erot, Eash};

  CONST (**** special node classes ****)
    Mbegin*        = 0;
    Merror*        = Mbegin + 00;              (* Merror can be set in any node type *)
    Mnone*        = Mbegin + 01;              (* incomplete node *)
    Mnop*          = Mbegin + 02;              (* nop can be set in any node type *)
    Marg*          = Mbegin + 03;              (* argument passed to a procedure *)
    Mdecl*        = Mbegin + 04;              (* variable, type or constant declaration *)
    Mifbody*      = Mbegin + 05;
    Mwithlist*    = Mbegin + 06;
    Msglcase*      = Mbegin + 07;
    Mcasestat*    = Mbegin + 08;
    Minittd*      = Mbegin + 09;
    Mimport*      = Mbegin + 10;            (* imported unit *)
    Mlast*        = Mbegin + 10 + 1;

  TYPE
    (* XXX
      There are several node types (IfBody, for example) which declare a pointer where
      the next field could be used.
      This extra pointer makes the code easier to read, but has the undesired characteristic
      of wasting memory.
      In this vein, it might be beneficial to make a BasicNode which has fewer fields and
      make the Node an extension of it.  By doing this, those descriptive fields can remain
      and less memory will be wasted.
    XXX *)
    Node* = POINTER TO NodeDesc;
    NodeDesc* = RECORD
      next* : Node;
      type* : ST.Type;
      pos* : LONGINT;        (* source pos *)
      flags* : SET;
      n* : LONGINT;          (* various uses *)
      class* : NODECLASS;
      subcl* : NODESUBCLASS;
      refno* : INTEGER;      (* reference number for node dumper *)
    END;

  CONST
    fwddecl* = 15;  (* fwddecl IN node(Declaration).flags => forward decl node *)

  TYPE (* Declaration node *)
    Declaration* = POINTER TO DeclarationDesc;
    DeclarationDesc* = RECORD (NodeDesc)
      sym* : ST.Symbol;
    END;

  TYPE (* expression nodes *)
    GRegSet* = SET;     (* CGL.GRegSet *)
    Design* = POINTER TO DesignDesc;        (* selectors *)
    Expr* = POINTER TO ExprDesc;
    ExprDesc* = RECORD (NodeDesc)
      val* : ST.Const;                      (* class # Econst => val = NIL *)
      regs* : GRegSet; (* used by Einterfere, Eload *)
    END;

    MExpr* = POINTER TO MExprDesc;           (* mono-expr *)
    MExprDesc* = RECORD (ExprDesc)
      op* : Expr;
    END;

    DExpr* = POINTER TO DExprDesc;           (* dual-expr *)
    DExprDesc* = RECORD (ExprDesc)
      lop*, rop* : Expr;
    END;

    IsTest* = POINTER TO IsTestDesc;
    IsTestDesc* = RECORD (ExprDesc)
      var* : Design;
      istype* : Design;
    END;

  TYPE (* procedure argument list *)
    Arg* = POINTER TO ArgDesc;
    ArgDesc* = RECORD (NodeDesc)
      arg* : Expr;
    END;

  TYPE (* procedure call *)
    (* inv: func # NIL & func.type IS ST.Procedure (change in semantics 97.08.16: func.type was the result type) *)
    (* FuncCall.type <= func.type(ST.Procedure).result *)
    FuncCall* = POINTER TO FuncCallDesc;
    FuncCallDesc* = RECORD (ExprDesc)
      args* : Arg;
      func* : Design;
    END;

  TYPE (* designator nodes *)
    DesignDesc* = RECORD (ExprDesc)
      sym* : ST.Symbol;
    END;

    Field* = POINTER TO FieldDesc;          (* field *)
    FieldDesc* = RECORD (DesignDesc)
      base* : Design;
      offset* : LONGINT;
    END;

    Index* = POINTER TO IndexDesc;          (* index *)
    IndexDesc* = RECORD (FieldDesc)
      index* : Expr;
      scale* : SHORTINT;                     (* 1, 2, 4, 8; multiplicative of index *)
    END;

    Deref* = POINTER TO DerefDesc;
    DerefDesc* = RECORD (DesignDesc)
      base* : Design;
    END;

    Guard* = POINTER TO GuardDesc;
    GuardDesc* = RECORD (DesignDesc)
      design* : Design;
    END;

  TYPE (* statements *)
    StmtList* = POINTER TO StmtListDesc;
    StmtListDesc* = RECORD (NodeDesc)
      prev* : StmtList;
    END;

    InitTD* = POINTER TO InitTDDesc;
    InitTDDesc* = RECORD (NodeDesc)
      td* : ST.SymbolTypeDesc;
    END;

    Import* = POINTER TO ImportDesc;
    ImportDesc* = RECORD (NodeDesc)
      module* : ST.Symbol;
    END;

    Enter* = POINTER TO EnterDesc;
    EnterDesc* = RECORD (StmtListDesc)
      info* : ST.Symbol;                  (* main IN flags => info IS ST.SymbolScope *)
                                            (* ~(main IN flags) =>  info IS ST.SymbolProc *)
                                            (* SymbolProc: owning procedure *)
                                            (* SymbolScope: owning scope *)
      nestedproc* : Enter;
      import* : Import;                    (* imported units, if module initialization *)
      inittd* : InitTD;                    (* type descriptor initializations *)
      decl* : Declaration;                (* type, constant & var decls in order for this procedure *)
      body* : StmtList;
    END;

    Assign* = POINTER TO AssignDesc;
    AssignDesc* = RECORD (StmtListDesc)
      lvalue* : Expr;
      rvalue* : Expr;
    END;

    Halt* = POINTER TO HaltDesc;
    HaltDesc* = RECORD (StmtListDesc)
      expr* : Expr;                          (* assert boolexpr *)
      val* : Expr;                          (* inv: const IN val.flags *)
    END;

    ProcCall* = POINTER TO ProcCallDesc;
    ProcCallDesc* = RECORD (StmtListDesc)
      call* : FuncCall;
    END;

    (* IF statements *)
    IfBody* = POINTER TO IfBodyDesc;
    IfBodyDesc* = RECORD (NodeDesc)
      cond* : Expr;
      stmt* : StmtList;
      elsif* : IfBody;  (* could use next field for this pointer XXX *)
    END;

    IfElse* = POINTER TO IfElseDesc;
    IfElseDesc* = RECORD (StmtListDesc)
      ifstat* : IfBody;
      else* : StmtList;
    END;

    WithList* = POINTER TO WithListDesc;
    WithListDesc* = RECORD (NodeDesc)
      control* : Design;
      testtype* : Design;
      body* : StmtList;
    END;

    With* = POINTER TO WithDesc;
    WithDesc* = RECORD (StmtListDesc)
      wstat* : WithList;
      else* : StmtList;
    END;

    (* CASE statements *)
    CaseBounds* = POINTER TO CaseBoundsDesc;
    CaseBoundsDesc* = RECORD
      bound* : ST.Const;
      next* : CaseBounds;
    END;

    SingleCase* = POINTER TO SingleCaseDesc;
    SingleCaseDesc* = RECORD (NodeDesc)
      bounds* : CaseBounds;
      stmt* : StmtList;
    END;

    CaseStat* = POINTER TO CaseStatDesc;
    CaseStatDesc* = RECORD (NodeDesc)
      range* : ST.Const;
      else* : StmtList;
      case* : SingleCase;
    END;

    Case* = POINTER TO CaseDesc;
    CaseDesc* = RECORD (StmtListDesc)
      expr* : Expr;
      of* : CaseStat;
    END;

    (* Looping constructs *)
    Loop* = POINTER TO LoopDesc;
    LoopDesc* = RECORD (StmtListDesc)
      body* : StmtList;
    END;

    For* = POINTER TO ForDesc;
    ForDesc* = RECORD (LoopDesc)
      control* : Design;
      temp* : ST.Symbol;
      lower*, upper* : Expr;
      step* : LONGINT;
    END;

    WhileRepeat* = POINTER TO WhileRepeatDesc;
    WhileRepeatDesc* = RECORD (LoopDesc)
      cond* : Expr;
    END;

    (* return *)
    Return* = POINTER TO ReturnDesc;
    ReturnDesc* = RECORD (StmtListDesc)
      expr* : Expr;
      proc* : ST.Symbol; (* for return type checking *)
    END;

  CONST  
   (* The DoCommonDesign system  could be improved to take into
    * account things like 'set := set * set2'.
    *
    * The common designator system does not work for '*' operator with
    * integer or real (for x86 instruction set), but it could work on SET.
    *)

    DoCommonDesign* = FALSE;  (* Identify same designators not containing expressions:
                               *
                               *   design := design op expr
                               *
                               *  Enable for processors that can do assignment with
                               *  an operator (such as x86).
                               *
                               * must be DExpr subclasses; eg: ADD [dest_mem], src_reg
                               *)
    
  TYPE
    HintInfo* = RECORD
      use* : SET; (* *)
      interfere* : SET; (* (additional) registers which are interfered by the instruction *)
      (* the instruction needs to load 'use' and destroys 'interface' registers *)
    END;
    
    (*
      left = registers needed and interfered by the lhs of the expr
      right = registers needed and interfered by the rhs of the expr
      result = registers output from this instruction
    *)
    ExprHintProc* = PROCEDURE (n : Expr; VAR left, right : HintInfo; VAR result : SET);
    
    StmtHintProc* = PROCEDURE (n : StmtList);
    DsgnHintProc* = PROCEDURE (n : Design; result : SET);
    
  VAR
    SameDesignSet- : SET; (* processor specific *)
    ExprHints* : ARRAY Elast - Ebegin OF ExprHintProc;
    StmtHints* : ARRAY Slast - Sbegin OF StmtHintProc;
    DsgnHints* : ARRAY Dlast - Dbegin OF DsgnHintProc;
    
  PROCEDURE ^ InitDesignNode(n : Design; subcl : NODESUBCLASS; type : ST.Type; sym : ST.Symbol);

  PROCEDURE RValue*(n : Expr) : BOOLEAN;
  BEGIN RETURN (n.class # Ndsgn) OR (n.subcl IN RValueSet);
  END RValue;
  
  PROCEDURE LValue*(n : Expr) : BOOLEAN;
  BEGIN
    IF (n.class = Nexpr) & (n.subcl = Ecast) THEN RETURN LValue(n(MExpr).op);
    ELSE RETURN (n.class = Ndsgn) & (n.subcl IN LValueSet) & ~(readonly IN n.flags);
    END;
  END LValue;
  
  (*** Generics ***)
  PROCEDURE BindNodes*(l, r : Node) : Node;
  BEGIN IF l # NIL THEN l.next := r; END; RETURN r;
  END BindNodes;

  PROCEDURE ReverseNodeList*(VAR head : Node);
    VAR h, q, r : Node;
  BEGIN q := NIL; h := head;
    WHILE h # NIL DO r := h.next; h.next := q; q := h; h := r; END;
    head := q;
  END ReverseNodeList;

  PROCEDURE InitBasicNode(n : Node; class : NODECLASS; subcl : NODESUBCLASS; t : ST.Type);
  BEGIN
    n.class := class; n.subcl := subcl; OPM.GetCurrentSourcePos(n.pos); n.type := t;
    n.n := 0; n.flags := {}; n.next := NIL; n.refno := OPM.InitialNodeRef;
  END InitBasicNode;

  PROCEDURE NewBasicNode*(class : NODECLASS; subcl : NODESUBCLASS; type : ST.Type) : Node;
    VAR n : Node;
  BEGIN NEW(n); InitBasicNode(n, class, subcl, type); RETURN n;
  END NewBasicNode;

  PROCEDURE NewDeclarationNode*(sym : ST.Symbol; fwd : BOOLEAN) : Declaration;
    VAR n : Declaration;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Mdecl, sym.type);
    IF fwd THEN INCL(n.flags, fwddecl); END;
    n.sym := sym; RETURN n;
  END NewDeclarationNode;

  PROCEDURE NewInitTDNode*(td : ST.SymbolTypeDesc) : InitTD;
    VAR n : InitTD;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Minittd, ST.notyp); n.td := td; RETURN n;
  END NewInitTDNode;

  PROCEDURE NewImportNode*(mod : ST.Symbol) : Import;
    VAR n : Import;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Mimport, ST.notyp); n.module := mod; RETURN n;
  END NewImportNode;

  (*** Expressions ***)
  PROCEDURE InitExprNode(n : Expr; class : NODECLASS; subcl : NODESUBCLASS; type : ST.Type);
  BEGIN InitBasicNode(n, class, subcl, type); n.val := NIL; n.regs := {}
  END InitExprNode;

  PROCEDURE NewInterfereNode*(op : Expr; regs : GRegSet) : MExpr;
    VAR n : MExpr; rs : GRegSet;
  BEGIN rs := regs;
    NEW(n); InitExprNode(n, Nexpr, Einterfere, op.type); n.op := op; n.regs := regs;
    IF (op.subcl = Eload) & (op.regs * rs # {}) THEN INCL(n.flags, defer); END;
    RETURN n;
  END NewInterfereNode;
  
  PROCEDURE NewLoadNode*(op : Expr; regs : GRegSet) : MExpr;
    VAR n : MExpr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, Eload, op.type); n.op := op; n.regs := regs; RETURN n;
  END NewLoadNode;
  
  PROCEDURE HintsExpr(n : Expr);
    VAR left, right : HintInfo; result : SET; subcl : SHORTINT;
  BEGIN
    IF ExprHints[n.subcl] # NIL THEN
      left.use := {};
      left.interfere := {};
      right.use := {};
      right.interfere := {};
      result := {};
      subcl := n.subcl;
      ExprHints[subcl](n, left, right, result);
      IF subcl IN MonoOps THEN
        ASSERT(right.use = {}, 1000);
        ASSERT(right.interfere = {}, 1001);
        IF left.use # {} THEN
          n(MExpr).op := NewLoadNode(n(MExpr).op, left.use);
        END;
      ELSIF subcl IN DualOps THEN
        IF (left.use # {}) OR (left.interfere # {}) THEN
          n(DExpr).lop := NewLoadNode(n(DExpr).lop, left.use);
          n(DExpr).rop := NewInterfereNode(n(DExpr).rop,
                                           left.use + left.interfere);
        END;
        IF (right.use # {}) OR (right.interfere # {}) THEN
          n(DExpr).lop := NewInterfereNode(n(DExpr).lop,
                                           right.use + right.interfere);
          n(DExpr).rop := NewLoadNode(n(DExpr).rop, right.use);
        END;
        n.regs := (result + left.use + left.interfere +
                   right.use + right.interfere);
      ELSIF subcl = Eis THEN (* NOP unless the children of IsTest are made
                              * into Expr - so we can interfere or load. *)
      ELSIF subcl = Ecall THEN n.regs := result;
      ELSIF  subcl IN {Econst, Einterfere, Eload} (* Expr *) THEN (* nop *)
      ELSE ASSERT(FALSE, 1002);
      END;
    ELSE
      IF n.subcl IN MonoOps THEN n.regs := n(MExpr).op.regs
      ELSIF n.subcl IN DualOps THEN
        n.regs := n(DExpr).lop.regs + n(DExpr).rop.regs;
        IF ~(n.subcl IN {Eand, Eor, Eeql, Eneq, Elss, Eleq, Egtr, Egeq, Eis}) THEN (* no defer eval on relational or IS *)
          IF n(DExpr).lop.regs # {} THEN (* left operand synthesizes registers; make sure right side does not interfere *)
            n(DExpr).rop := NewInterfereNode(n(DExpr).rop, n(DExpr).lop.regs);
          END;
          IF n(DExpr).rop.regs # {} THEN (* right operand is synthesizes registers; make sure left side does not interfere *)
            n(DExpr).lop := NewInterfereNode(n(DExpr).lop, n(DExpr).rop.regs);
          END;
        END;
      ELSE n.regs := {};
      END;
    END;
  END HintsExpr;
  
  PROCEDURE NewExprNode*(subcl : NODESUBCLASS; type : ST.Type) : Expr;
    VAR n : Expr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, type); HintsExpr(n); RETURN n;
  END NewExprNode;

  PROCEDURE NewErrorExpr() : Expr;
    VAR n : Expr;
  BEGIN NEW(n); InitExprNode(n, Nmisc, Merror, ST.undftyp); RETURN n;
  END NewErrorExpr;

  PROCEDURE NewConstExprNode*(type : ST.Type) : Design;
    VAR n : Design;
  BEGIN
    NEW(n);
    InitExprNode(n, Nexpr, Econst, type);
    n.sym := NIL;
    n.val := ST.NewConst(type);
    INCL(n.flags, constant);
    HintsExpr(n);
    RETURN n;
  END NewConstExprNode;

  PROCEDURE NewMExprNode*(subcl : NODESUBCLASS; op : Expr) : MExpr;
    VAR n : MExpr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, op.type); n.op := op;  HintsExpr(n); RETURN n;
  END NewMExprNode;
  
  PROCEDURE NewCastNode*(newtype : ST.Type; op : Expr) : Expr;  (* SYSTEM.VAL *)
    VAR mop : MExpr;
  BEGIN mop := NewMExprNode(Ecast, op); mop.type := newtype; RETURN mop;
  END NewCastNode;
  
  PROCEDURE NewDExprNode*(subcl : NODESUBCLASS; lop, rop : Expr; type : ST.Type) : DExpr;
    VAR n : DExpr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, type); n.lop := lop; n.rop := rop; HintsExpr(n); RETURN n;
  END NewDExprNode;

  PROCEDURE NewIsTestNode*(var : Design; istype : Design) : IsTest;
    VAR n : IsTest;
  BEGIN NEW(n); InitExprNode(n, Nexpr, Eis, ST.booltyp); n.var := var; n.istype := istype; HintsExpr(n); RETURN n;
  END NewIsTestNode;

  (* inv: func.type.form = ST.procedure: the result type must not be void *)
  PROCEDURE  NewFuncCallNode*(func : Design; args : Arg) : FuncCall;
    VAR
      n : FuncCall;
      typ : ST.Type;
  BEGIN
    NEW(n);
    IF func.type IS ST.Procedure THEN
      typ := func.type(ST.Procedure).result;
    ELSE
      typ := ST.inttyp; (* If tree is not a Procedure due to other errors. *)
    END;
    InitExprNode(n, Nexpr, Ecall, typ);
    n.func := func;
    n.args := args;
    HintsExpr(n);
    RETURN n;
  END NewFuncCallNode;

  (*** Arguments ***)
  PROCEDURE  NewArgNode*(arg : Expr) : Arg;
    VAR n : Arg;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Marg, arg.type); n.arg := arg; RETURN n;
  END NewArgNode;

  (*** Designators ***)
  PROCEDURE InitDesignNode(n : Design; subcl : NODESUBCLASS; type : ST.Type; sym : ST.Symbol);
  BEGIN  InitExprNode(n, Ndsgn, subcl, type); n.sym := sym;
  END InitDesignNode;

  PROCEDURE NewDesignNode*(subcl : NODESUBCLASS; sym : ST.Symbol) : Design;
    VAR n : Design;
  BEGIN NEW(n); InitDesignNode(n, subcl, sym.type, sym); 
    IF (sym # NIL) & (sym.mnolev < 0) & (sym.vis = ST.exportR) THEN INCL(n.flags, readonly);  END;
    RETURN n;
  END NewDesignNode;

  PROCEDURE NewFieldNode*(base : Design; offset : LONGINT; field : ST.Symbol) : Field;
    VAR n : Field;
  BEGIN NEW(n); InitDesignNode(n, Dfield, field.type, field);
    n.base := base; n.offset := offset; n.flags := base.flags - {super, used, main};
    IF (field # NIL) & (field.mnolev < 0) & (field.vis = ST.exportR) THEN INCL(n.flags, readonly);  END;
    RETURN n;
  END NewFieldNode;

  PROCEDURE NewIndexNode*(base : Design; offset : LONGINT; scale : SHORTINT; index : Expr; type : ST.Type) : Index;
    VAR n : Index;
  BEGIN NEW(n); InitDesignNode(n, Dindex, type, NIL);
    n.base := base; n.offset := offset; n.scale := scale; n.index := index; n.flags := base.flags;
    n.flags := base.flags - {super, used, main};
    RETURN n;
  END NewIndexNode;

  PROCEDURE NewDerefNode*(base : Design; type : ST.Type) : Deref;
    VAR n : Deref;
  BEGIN NEW(n); InitDesignNode(n, Dderef, type, NIL);
    n.base := base; n.flags := base.flags - {super, readonly, used, main};
    RETURN n;
  END NewDerefNode;

  PROCEDURE NewGuardNode*(subcl : NODESUBCLASS; design : Design; type : ST.Symbol) : Guard;
    VAR n : Guard;
  BEGIN NEW(n); InitDesignNode(n, subcl, type.type, type);
    n.design := design; n.flags := design.flags - {super, used, main};
    RETURN n;
  END NewGuardNode;

  (*** Statements ***)

  PROCEDURE HintsStmt(n : StmtList);
  BEGIN IF StmtHints[n.subcl] # NIL THEN StmtHints[n.subcl](n); END;
  END HintsStmt;
  
  PROCEDURE InitStmtListNode(n : StmtList; subcl : NODESUBCLASS);
  BEGIN InitBasicNode(n, Nstmt, subcl, ST.notyp); OPM.GetCurrentSourcePos(n.pos); n.prev := NIL;
  END InitStmtListNode;

  PROCEDURE NewStmtListNode*(subcl : NODESUBCLASS) : StmtList;
    VAR n : StmtList;
  BEGIN NEW(n); InitStmtListNode(n, subcl); RETURN n;
  END NewStmtListNode;

  PROCEDURE NewNullStmtNode*() : StmtList;
  BEGIN RETURN NewStmtListNode(Snull);
  END NewNullStmtNode;

  PROCEDURE NewEnterNode*
       (    owner : ST.Symbol;
            nested : Enter;
            body : StmtList;
            decl : Declaration;
            inittd : InitTD;
            import : Import) : Enter;
    VAR n : Enter;
  BEGIN
    NEW(n); InitStmtListNode(n, Senter);
    n.info := owner; n.nestedproc := nested; n.body := body;
    n.decl := decl; n.import := import; n.inittd := inittd;
    HintsStmt(n); RETURN n;
  END NewEnterNode;

  PROCEDURE NewAssignNode*(lvalue : Design; rvalue : Expr) : Assign;
    VAR n : Assign;
  BEGIN NEW(n); InitStmtListNode(n, Sassign); n.lvalue := lvalue; n.rvalue := rvalue; HintsStmt(n); RETURN n;
  END NewAssignNode;

  PROCEDURE NewHaltNode*(cond : Expr; val : Expr) : Halt;
    VAR n : Halt;
  BEGIN NEW(n); InitStmtListNode(n, Sassert); n.expr := cond; n.val := val; HintsStmt(n); RETURN n;
  END NewHaltNode;

  PROCEDURE NewProcCallNode*(call : FuncCall) : ProcCall;
    VAR n : ProcCall;
  BEGIN
    NEW(n);
    InitStmtListNode(n, Scall);
    n.call := call;
    n.type := call.type;
    HintsStmt(n);
    RETURN n;
  END NewProcCallNode;

  PROCEDURE NewIfBodyNode*(cond : Expr; body : StmtList) : IfBody;
    VAR n : IfBody;
  BEGIN
    NEW(n); InitBasicNode(n, Nmisc, Mifbody, ST.notyp);
    n.cond := cond; n.elsif := NIL; n.stmt := body; RETURN n;
  END NewIfBodyNode;

  PROCEDURE NewIfElseNode*(if : IfBody; else : StmtList) : IfElse;
    VAR n : IfElse;
  BEGIN
    NEW(n); InitStmtListNode(n, Sifelse); n.ifstat := if; n.else := else; HintsStmt(n); RETURN n;
  END NewIfElseNode;

  PROCEDURE NewWithListNode*(ctrl, testtype : Design; body : StmtList) : WithList;
    VAR n : WithList;
  BEGIN
    NEW(n); InitBasicNode(n, Nmisc, Mwithlist, testtype.type);
    n.control := ctrl; n.testtype := testtype; n.body := body;
    RETURN n;
  END NewWithListNode;

  PROCEDURE NewWithNode*(wstat : WithList; else : StmtList) : With;
    VAR n : With;
  BEGIN NEW(n); InitStmtListNode(n, Swith); n.wstat := wstat; n.else := else; HintsStmt(n); RETURN n;
  END NewWithNode;

  PROCEDURE NewCaseBoundsNode*(bound : ST.Const) : CaseBounds;
    VAR n : CaseBounds;
  BEGIN NEW(n); n.next := NIL; n.bound := bound; RETURN n;
  END NewCaseBoundsNode;

  PROCEDURE BindCaseBounds*(old, new : CaseBounds) : CaseBounds;
  BEGIN new.next := old; RETURN new;
  END BindCaseBounds;

  PROCEDURE NewSingleCaseNode*(bound : CaseBounds; stmt : StmtList) : SingleCase;
    VAR n : SingleCase;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Msglcase, ST.notyp); n.bounds := bound; n.stmt := stmt;
    RETURN n;
  END NewSingleCaseNode;

  PROCEDURE BindSingleCase*(last, new : SingleCase) : SingleCase;
  BEGIN  IF last # NIL THEN last.next := new; END; RETURN new;
  END BindSingleCase;

  PROCEDURE NewCaseStatNode*(low, high : LONGINT; case : SingleCase; else : StmtList) : CaseStat;
    VAR n : CaseStat;
  BEGIN
    NEW(n); InitBasicNode(n, Nmisc, Mcasestat, ST.notyp);
    n.range := ST.NewConst(ST.linttyp); n.range.i0 := low; n.range.i1 := high;
    n.case := case; n.else := else; RETURN n;
  END NewCaseStatNode;

  PROCEDURE NewCaseNode*(expr : Expr; of : CaseStat) : Case;
    VAR n : Case;
  BEGIN NEW(n); InitStmtListNode(n, Scase); n.expr := expr; n.of := of; HintsStmt(n); RETURN n;
  END NewCaseNode;

  PROCEDURE NewLoopNode*(body : StmtList) : Loop;
    VAR n : Loop;
  BEGIN NEW(n); InitStmtListNode(n, Sloop); n.body := body; HintsStmt(n); RETURN n;
  END NewLoopNode;

  PROCEDURE NewForNode*(ctrl : Design; low, hi : Expr; step : LONGINT; body : StmtList) : For;
    VAR n : For;
  BEGIN NEW(n); InitStmtListNode(n, Sfor);
    n.control := ctrl; n.lower := low; n.upper := hi; n.step := step; n.body := body;
    n.temp := ST.NewTempVar(ctrl.type); HintsStmt(n);
    RETURN n;
  END NewForNode;

  PROCEDURE NewWhileRepeatNode*(subcl : NODESUBCLASS; cond : Expr; body : StmtList) : WhileRepeat;
    VAR n : WhileRepeat;
  BEGIN NEW(n); InitStmtListNode(n, subcl); n.cond := cond; n.body := body; HintsStmt(n); RETURN n;
  END NewWhileRepeatNode;

  PROCEDURE NewReturnNode*(owner : ST.Symbol; expr : Expr) : Return;
    VAR n : Return;
  BEGIN NEW(n); InitStmtListNode(n, Sreturn); n.proc := owner; n.expr := expr; HintsStmt(n); RETURN n;
  END NewReturnNode;

  (*** Utility ***)
  (* Binds r onto l, returns tail of the statement list *)
  PROCEDURE BindStmtList*(l, r : StmtList) : StmtList;
    VAR c : NODECLASS; sc : NODESUBCLASS; misc, stmt : BOOLEAN;
  BEGIN ASSERT((l # NIL) OR (r # NIL));
    IF l = NIL THEN RETURN r;
    ELSE
      c := l.class; sc := l.subcl;
      misc := (c = Nmisc) & ((sc = Merror) OR (sc = Mnop) OR (sc = Mnone));
      stmt := (c = Nstmt) & (sc = Snull);
      IF (misc OR stmt) & (r # NIL) THEN RETURN r;
      ELSIF r # NIL THEN
        c := r.class; sc := r.subcl;
        misc := (c = Nmisc) & ((sc = Merror) OR (sc = Mnop) OR (sc = Mnone));
        stmt := (c = Nstmt) & (sc = Snull);
        IF ~misc & ~stmt THEN l.next := r; r.prev := l; END;
        RETURN r;
      ELSE RETURN l;
      END;
    END;
  END BindStmtList;

  PROCEDURE ReverseStmtList*(VAR head : StmtList);
    VAR h, q, r : Node;
  BEGIN q := NIL; h := head;
    WHILE h # NIL DO r := h.next; h.next := q; q := h; h := r; END;
    head := q(StmtList);
    ASSERT(FALSE); (* what about the previous pointer? *)
  END ReverseStmtList;

  PROCEDURE BindIfElsif*(ifb : IfBody; elsif : IfBody);
  BEGIN ifb.elsif := elsif;
  END BindIfElsif;

  PROCEDURE BindArg*(cur : Arg; new : Arg) : Arg;
  BEGIN new.next := cur; RETURN new;
  END BindArg;

  PROCEDURE ReverseArgList*(VAR head : Arg);
    VAR h, q, r : Node;
  BEGIN q := NIL; h := head;
    WHILE h # NIL DO r := h.next; h.next := q; q := h; h := r; END;
    head := q(Arg);
  END ReverseArgList;

  PROCEDURE ArgumentN*(x : Arg; n : INTEGER) : Arg;
    VAR y : Node;
  BEGIN y := x; WHILE (n > 0) & (y # NIL) DO DEC(n); y := y.next; END;
    IF y # NIL THEN RETURN y(Arg); ELSE RETURN NIL; END;
  END ArgumentN;

  (* return nth argument as Expr of a procedure call *)
  PROCEDURE ArgN*(x : Arg; n : INTEGER) : Expr;
    VAR y : Arg;
  BEGIN (* ASSERT(x.class = Ecall) *)
    y := ArgumentN(x, n);
    IF y # NIL THEN RETURN y.arg;
    ELSE RETURN NewErrorExpr();
    END;
  END ArgN;
  
  PROCEDURE IsCommonDesign*(l, r : Expr) : BOOLEAN;

    PROCEDURE SameDesign(l, r : Expr) : BOOLEAN;
    BEGIN
      LOOP
        IF (l.class # r.class) OR (l.subcl # r.subcl) OR (l.type # r.type) THEN RETURN FALSE; END;
        CASE l.subcl OF
        | Dvar, Dvarpar, Dpar, Dproc: RETURN l(Design).sym = r(Design).sym;
        |  Dfield:
          IF l(Design).sym # l(Design).sym THEN l := l(Field).base; r := r(Field).base; (* XXX ? this may be incorrect processing of this case; should examine tree for field access  *)
          ELSE RETURN FALSE;
          END;
        |  Dderef: l := l(Deref).base; r := r(Deref).base;
        |  Diguard, Deguard: RETURN FALSE;
        |  Dindex: RETURN SameDesign(l(Index).index, r(Index).index);
        ELSE RETURN FALSE;
        END;
      END;
    END SameDesign;
  
  BEGIN
    RETURN
      DoCommonDesign & ~(r.type.form IN ST.RealSet) & ~(l.type.form IN ST.RealSet) &
      (r.class = Nexpr) & (r.subcl IN SameDesignSet) & SameDesign(l, r(DExpr).lop);
  END IsCommonDesign;

  PROCEDURE NILGlobalPointers;
    VAR i : INTEGER;
  BEGIN
    i := 0; WHILE i < LEN(ExprHints) DO ExprHints[i] := NIL; INC(i); END;
    i := 0; WHILE i < LEN(StmtHints) DO StmtHints[i] := NIL; INC(i); END;
    i := 0; WHILE i < LEN(DsgnHints) DO DsgnHints[i] := NIL; INC(i); END;
  END NILGlobalPointers;
  
  PROCEDURE ModuleBegin*(design : SET);
  BEGIN
    ASSERT(Dlast <= MAX(SET) + 1); ASSERT(Slast <= MAX(SET) + 1);
    ASSERT(Elast <= MAX(SET) + 1); ASSERT(Mlast <= MAX(SET) + 1);
    SameDesignSet := design; NILGlobalPointers;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN NILGlobalPointers;
  END ModuleEnd;

END SKLT.
