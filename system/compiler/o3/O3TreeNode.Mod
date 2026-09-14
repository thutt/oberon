MODULE O3TreeNode; (* Node Types & Tree Building routines *)
  IMPORT Symtab:=O3Symtab, Config:=O3Config;

  CONST
    InitialNodeRef* = -1;

  CONST (**** flags ****)
    (* fields 00..31: reserved for global usage *)
    constant*  = 17;          (*    (class = Ndsgn) & (subcl = Dconst)
                               OR (class = Nexpr) & (subcl = Econst) *)
                            (* constant propogates through: *)
                            (*    nothing *)
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
    super*    = 15;          (* super call (Dmethod) *)
    used*     = 14;          (* imported unit is used or not (STimport) *)
    main*      = 13;          (* STenter: module init  *)
    noinit*  = 12;     (* STimport: special unit which should not be initialized *)
    defer* = 11; (* Einterfere: this subtree (always on left) evaluation should occur after the other subtree *)
    generated* = 10; (* compiler generated node; for example, the missing else of a CASE
                      * or WITH
                      *)

  TYPE
    NODECLASS* = SHORTINT;
    NODESUBCLASS* = SHORTINT;

  CONST (**** Node classes *)
    Ndsgn* = 0;                              (* Design & extensions *)
    Nstmt* = 1;                              (* StatementList & extensions *)
    Nexpr* = 2;                              (* Expr & extensions (except Design) *)
    Nmisc* = 3;                              (* Miscellaneous nodes *)

  CONST (* constant types which must be allocated and treated like variables *)
    AllocedConsts* = {Symtab.string};

  CONST (**** designator nodes (Ndsgn) ****)
    Dbegin*        = 0;
    Danon*        = Dbegin + Symtab.anon;
    Dvar*          = Dbegin + Symtab.var;
    Dpar*          = Dbegin + Symtab.par;
    Dvarpar*      = Dbegin + Symtab.varpar;
    Dconst*        = Dbegin + Symtab.const;
    Dstdproc*      = Dbegin + Symtab.stdproc;
    Dfwdproc*      = Dbegin + Symtab.fwdproc;     (* cannot occur in tree *)
    Dlproc*        = Dbegin + Symtab.lproc;      (* cannot occur in tree *)
    Dxproc*        = Dbegin + Symtab.xproc;      (* cannot occur in tree *)
    Dcproc*        = Dbegin + Symtab.cproc;      (* cannot occur in tree *)
    Diproc*        = Dbegin + Symtab.iproc;      (* cannot occur in tree *)
    Dmethod*      = Dbegin + Symtab.tproc;
    Dfield*        = Dbegin + Symtab.field;
    Dtype*        = Dbegin + Symtab.type;
    Dmodule*      = Dbegin + Symtab.module;  (* module scope; cannot occur in tree *)
    Dscope*        = Dbegin + Symtab.scope;
    Ddarrdesc*  = Dbegin + Symtab.darrdesc;
    Darrdesc*    = Dbegin + Symtab.arrdesc;
    Drecdesc*    = Dbegin + Symtab.recdesc;
    Dderef*        = Symtab.nofSymbols + 0;
    Dindex*        = Symtab.nofSymbols + 1;
    Diguard*      = Symtab.nofSymbols + 2;
    Deguard*      = Symtab.nofSymbols + 3;
    Dproc*        = Symtab.nofSymbols + 4;              (* subsumes {Dfwdproc..Diproc} *)
    Dlast*        = Symtab.nofSymbols + 5;

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

  CONST  (**** statement subclasses (Nstmt) ****)
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

  CONST (**** expression subclasses (Nexpr) ****)
    Ebegin*        = 0;
    Enot*          = Ebegin + 00;
    Euminus*      = Ebegin + 01;
    Euplus*        = Ebegin + 02;
    Econvert*      = Ebegin + 03;
    Etimes*        = Ebegin + 04;
    Ediv*          = Ebegin + 05;
    Eslash*        = Ebegin + 06;
    Emod*          = Ebegin + 07;
    Eplus*        = Ebegin + 08;
    Eminus*        = Ebegin + 09;
    Eand*          = Ebegin + 10;
    Eor*          = Ebegin + 11;
    Eeql*          = Ebegin + 12;
    Eneq*          = Ebegin + 13;
    Elss*          = Ebegin + 14;
    Eleq*          = Ebegin + 15;
    Egtr*          = Ebegin + 16;
    Egeq*          = Ebegin + 17;
    Ein*          = Ebegin + 18;
    Eupto*        = Ebegin + 19;            (* set range *)
    Eis*          = Ebegin + 20;
    Ecall*        = Ebegin + 21;            (* function call *)
    Econst*        = Ebegin + 22;
    Ecast*        = Ebegin + 23;        (* unchecked conversion; eg: SYSTEM.VAL *)
    Eadr*         = Ebegin + 24;        (* address of the operand (compiler-generated)
                                         * See standard procedure SYSTEM.ADR() for 
                                         * source-generated address nodes.
                                         *)
    Elast*        = Ebegin + 24 + 1;

  CONST
    MonoOps* = {Enot, Euminus, Euplus, Econvert, Ecast, Eadr};
    DualOps* = {Etimes..Eupto};

  CONST (**** special node classes (Nmisc) ****)
    Mbegin*        = 0;
    Marg*          = Mbegin + 00;              (* argument passed to a procedure *)
    Mdecl*        = Mbegin + 01;              (* variable, type or constant declaration *)
    Mifbody*      = Mbegin + 02;
    Mwithlist*    = Mbegin + 03;
    Msglcase*      = Mbegin + 04;
    Mcasestat*    = Mbegin + 05;
    Minittd*      = Mbegin + 06;
    Mimport*      = Mbegin + 07;            (* imported unit *)
    Mlast*        = Mbegin + 07 + 1;

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
      type* : Symtab.Type;
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
      sym* : Symtab.Symbol;
      expr* : Node; (* constant symbol expression trees *)
    END;

  TYPE (* expression nodes *)
    GRegSet* = SET;     (* CGL.GRegSet *)
    Design* = POINTER TO DesignDesc;        (* selectors *)
    Expr* = POINTER TO ExprDesc;
    ExprDesc* = RECORD (NodeDesc)
      val* : Symtab.Const;                      (* class # Econst => val = NIL *)
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
    (* inv: func # NIL & func.type IS Symtab.Procedure
     *       (change in semantics 97.08.16: func.type was
     *        the result type)
     *)
    (* FuncCall.type <= func.type(Symtab.Procedure).result *)
    FuncCall* = POINTER TO FuncCallDesc;
    FuncCallDesc* = RECORD (ExprDesc)
      args* : Arg;
      func* : Design;
    END;

  TYPE (* designator nodes *)
    DesignDesc* = RECORD (ExprDesc)
      sym* : Symtab.Symbol;
    END;

    Field* = POINTER TO FieldDesc;          (* field *)
    FieldDesc* = RECORD (DesignDesc)
      base* : Design;
    END;

    Index* = POINTER TO IndexDesc;          (* index *)
    IndexDesc* = RECORD (FieldDesc)
      index* : Expr;
      scale* : SHORTINT;                     (* 1, 2, 4, 8; multiplicative of index *)
      offset* : LONGINT;
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
      td* : Symtab.SymbolTypeDesc;
    END;

    Import* = POINTER TO ImportDesc;
    ImportDesc* = RECORD (NodeDesc)
      module* : Symtab.Symbol;
    END;

    Enter* = POINTER TO EnterDesc;
    EnterDesc* = RECORD (StmtListDesc)
      info* : Symtab.Symbol;                  (* main IN flags => info IS Symtab.SymbolScope *)
                                            (* ~(main IN flags) =>  info IS Symtab.SymbolProc *)
                                            (* SymbolProc: owning procedure *)
                                            (* SymbolScope: owning scope *)
      nestedproc* : Enter;
      import* : Import;                    (* imported units, if module initialization *)
      inittd* : InitTD;                  (* type descriptor initializations *)
      decl* : Declaration;                (* type, constant & var decls in order for this procedure *)
      body* : StmtList;
    END;

    Assign* = POINTER TO AssignDesc;
    AssignDesc* = RECORD (StmtListDesc)
      lvalue* : Design;
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
      bound* : Symtab.Const;
      next* : CaseBounds;
    END;

    SingleCase* = POINTER TO SingleCaseDesc;
    SingleCaseDesc* = RECORD (NodeDesc)
      bounds* : CaseBounds;
      stmt* : StmtList;
    END;

    CaseStat* = POINTER TO CaseStatDesc;
    CaseStatDesc* = RECORD (NodeDesc)
      range* : Symtab.Const;
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
      proc* : Symtab.Symbol; (* for return type checking *)
    END;

  CONST  
    DoCommonDesign* = TRUE;  (* identify same designators not containing expressions: design := design op expr *)
    (* operators on this processor which can do assignment + operator. must be DExpr subclasses; eg: ADD [mem], R0 *)
    (* XXX common designator could be improved to take into account things like 'set := set * set2' -- times does not
      work on integer or real, but it can on set
    *)

  TYPE (* Procedure signature to be used by backends of the Oberon-3 compiler *)
    (*
      The procedure is passed the root of the tree.
      The function should traverse the tree and perform any necessary output.
      Returning TRUE indicates the compilation process was successful.
      Returning FALSE indicates teh compilation process was unsuccessful.
      
      A code generator should export a procedure, with this signature, named 'Module'
    *)
    TreeTraversalProc* = PROCEDURE (n : Node) : BOOLEAN;
    
  TYPE

  VAR
    Module- : TreeTraversalProc; (* set by loaded code generator for walking the AST *)
    
  PROCEDURE ^ InitDesignNode(n : Design;
                             subcl : NODESUBCLASS;
                             type : Symtab.Type;
                             sym : Symtab.Symbol);

  PROCEDURE RValue*(n : Expr) : BOOLEAN;
  BEGIN RETURN (n.class # Ndsgn) OR (n.subcl IN RValueSet);
  END RValue;
  
  PROCEDURE LValue*(n : Expr) : BOOLEAN;
  BEGIN
    IF (n.class = Nexpr) & (n.subcl = Ecast) THEN
      RETURN LValue(n(MExpr).op);
    ELSE
      RETURN ((n.class = Ndsgn) &
              (n.subcl IN LValueSet) &
              ~(readonly IN n.flags));
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

  PROCEDURE InitBasicNode(n : Node; class : NODECLASS; subcl : NODESUBCLASS; t : Symtab.Type);
  BEGIN
    n.class := class; n.subcl := subcl; Config.GetSourcePos(n.pos); n.type := t;
    n.n := 0; n.flags := {}; n.next := NIL; n.refno := InitialNodeRef;
  END InitBasicNode;

  PROCEDURE NewBasicNode*(class : NODECLASS; subcl : NODESUBCLASS; type : Symtab.Type) : Node;
    VAR n : Node;
  BEGIN NEW(n); InitBasicNode(n, class, subcl, type); RETURN n;
  END NewBasicNode;

  PROCEDURE NewDeclarationNode*(sym : Symtab.Symbol; expr : Node; fwd : BOOLEAN) : Declaration;
    VAR n : Declaration;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Mdecl, sym.type);
    IF fwd THEN INCL(n.flags, fwddecl); END;
    n.sym := sym; n.expr := expr; 
    RETURN n;
  END NewDeclarationNode;

  PROCEDURE NewInitTDNode*(td : Symtab.SymbolTypeDesc) : InitTD;
    VAR n : InitTD;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Minittd, Symtab.notyp); n.td := td; RETURN n;
  END NewInitTDNode;

  PROCEDURE NewImportNode*(mod : Symtab.Symbol) : Import;
    VAR n : Import;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Mimport, Symtab.notyp); n.module := mod; RETURN n;
  END NewImportNode;

  (*** Expressions ***)
  PROCEDURE InitExprNode(n : Expr; class : NODECLASS; subcl : NODESUBCLASS; type : Symtab.Type);
  BEGIN InitBasicNode(n, class, subcl, type); n.val := NIL;
  END InitExprNode;

  PROCEDURE NewExprNode*(subcl : NODESUBCLASS; type : Symtab.Type) : Expr;
    VAR n : Expr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, type); RETURN n;
  END NewExprNode;

  PROCEDURE NewConstExprNode*(type : Symtab.Type) : Design;
    VAR n : Design;
  BEGIN
    NEW(n); InitExprNode(n, Nexpr, Econst, type); n.sym := NIL; 
    n.val := Symtab.NewConst(type); INCL(n.flags, constant);
    RETURN n;
  END NewConstExprNode;

  PROCEDURE NewMExprNode*(subcl : NODESUBCLASS; op : Expr) : MExpr;
    VAR n : MExpr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, op.type); n.op := op;  RETURN n;
  END NewMExprNode;
  
  PROCEDURE NewCastNode*(newtype : Symtab.Type; op : Expr) : Expr;  (* SYSTEM.VAL *)
    VAR mop : MExpr;
  BEGIN mop := NewMExprNode(Ecast, op); mop.type := newtype; RETURN mop;
  END NewCastNode;
  
  PROCEDURE NewAdrNode*(newtype : Symtab.Type; op : Expr) : Expr;  (* address-of *)
    VAR mop : MExpr;
  BEGIN mop := NewMExprNode(Eadr, op); mop.type := newtype; RETURN mop;
  END NewAdrNode;
  
  PROCEDURE NewDExprNode*(subcl : NODESUBCLASS; lop, rop : Expr; type : Symtab.Type) : DExpr;
    VAR n : DExpr;
  BEGIN NEW(n); InitExprNode(n, Nexpr, subcl, type); n.lop := lop; n.rop := rop; RETURN n;
  END NewDExprNode;

  PROCEDURE NewIsTestNode*(var : Design; istype : Design) : IsTest;
    VAR n : IsTest;
  BEGIN NEW(n); InitExprNode(n, Nexpr, Eis, Symtab.booltyp); n.var := var; n.istype := istype; RETURN n;
  END NewIsTestNode;

  (* inv: func.type.form = Symtab.procedure: the result type must not be void *)
  PROCEDURE NewFuncCallNode*(func : Design; args : Arg) : FuncCall;
    VAR n : FuncCall;
  BEGIN
    ASSERT(func.type.form = Symtab.procedure);
    NEW(n);
    InitExprNode(n, Nexpr, Ecall, func.type(Symtab.Procedure).result);
    n.func := func;
    n.args := args;
    RETURN n;
  END NewFuncCallNode;

  (*** Arguments ***)
  PROCEDURE  NewArgNode*(arg : Expr) : Arg;
    VAR n : Arg;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Marg, arg.type); n.arg := arg; RETURN n;
  END NewArgNode;

  (*** Designators ***)
  PROCEDURE InitDesignNode(n : Design; subcl : NODESUBCLASS; type : Symtab.Type; sym : Symtab.Symbol);
  BEGIN InitExprNode(n, Ndsgn, subcl, type); n.sym := sym;
  END InitDesignNode;

  PROCEDURE NewDesignNode*(subcl : NODESUBCLASS; sym : Symtab.Symbol) : Design;
    VAR n : Design;
  BEGIN NEW(n); InitDesignNode(n, subcl, sym.type, sym); 
    IF (sym # NIL) & (sym.mnolev < 0) & (sym.vis = Symtab.exportR) THEN INCL(n.flags, readonly);  END;
    RETURN n;
  END NewDesignNode;

  PROCEDURE NewFieldNode*(base : Design; field : Symtab.Symbol) : Field;
    VAR n : Field;
  BEGIN NEW(n); InitDesignNode(n, Dfield, field.type, field);
    n.base := base; n.flags := base.flags - {super, used, main};
    IF (field # NIL) & (field.mnolev < 0) & (field.vis = Symtab.exportR) THEN INCL(n.flags, readonly);  END;
    RETURN n;
  END NewFieldNode;

  PROCEDURE NewIndexNode*(base : Design; offset : LONGINT; scale : SHORTINT; index : Expr; type : Symtab.Type) : Index;
    VAR n : Index;
  BEGIN NEW(n); InitDesignNode(n, Dindex, type, NIL);
    n.base := base; n.offset := offset; n.scale := scale; n.index := index; n.flags := base.flags;
    n.flags := base.flags - {super, used, main};
    RETURN n;
  END NewIndexNode;

  PROCEDURE NewDerefNode*(base : Design; type : Symtab.Type) : Deref;
    VAR n : Deref;
  BEGIN NEW(n); InitDesignNode(n, Dderef, type, NIL);
    n.base := base; n.flags := base.flags - {super, readonly, used, main};
    RETURN n;
  END NewDerefNode;

  PROCEDURE NewGuardNode*(subcl : NODESUBCLASS; design : Design; type : Symtab.Symbol) : Guard;
    VAR n : Guard;
  BEGIN NEW(n); InitDesignNode(n, subcl, type.type, type);
    n.design := design; n.flags := design.flags - {super, used, main};
    RETURN n;
  END NewGuardNode;

  (*** Statements ***)

  PROCEDURE InitStmtListNode(n : StmtList; subcl : NODESUBCLASS);
  BEGIN InitBasicNode(n, Nstmt, subcl, Symtab.notyp); Config.GetSourcePos(n.pos); n.prev := NIL;
  END InitStmtListNode;

  PROCEDURE NewStmtListNode*(subcl : NODESUBCLASS) : StmtList;
    VAR n : StmtList;
  BEGIN NEW(n); InitStmtListNode(n, subcl); RETURN n;
  END NewStmtListNode;

  PROCEDURE NewNullStmtNode*() : StmtList;
  BEGIN RETURN NewStmtListNode(Snull);
  END NewNullStmtNode;

  PROCEDURE NewEnterNode*
       (    owner : Symtab.Symbol;
            nested : Enter;
            body : StmtList;
            decl : Declaration;
            init : InitTD;
            import : Import) : Enter;
    VAR n : Enter;
  BEGIN
    NEW(n); InitStmtListNode(n, Senter);
    n.info := owner; n.nestedproc := nested; n.body := body;
    n.decl := decl; n.import := import; n.inittd := init;
    RETURN n;
  END NewEnterNode;

  PROCEDURE NewAssignNode*(lvalue : Design; rvalue : Expr) : Assign;
    VAR n : Assign;
  BEGIN NEW(n); InitStmtListNode(n, Sassign); n.lvalue := lvalue; n.rvalue := rvalue; RETURN n;
  END NewAssignNode;

  PROCEDURE NewHaltNode*(cond : Expr; val : Expr) : Halt;
    VAR n : Halt;
  BEGIN NEW(n); InitStmtListNode(n, Sassert); n.expr := cond; n.val := val; RETURN n;
  END NewHaltNode;

  PROCEDURE NewProcCallNode*(call : FuncCall) : ProcCall;
    VAR n : ProcCall;
  BEGIN NEW(n); InitStmtListNode(n, Scall); n.call := call; n.type := call.type; RETURN n;
  END NewProcCallNode;

  PROCEDURE NewIfBodyNode*(cond : Expr; body : StmtList) : IfBody;
    VAR n : IfBody;
  BEGIN
    NEW(n); InitBasicNode(n, Nmisc, Mifbody, Symtab.notyp);
    n.cond := cond; n.elsif := NIL; n.stmt := body; RETURN n;
  END NewIfBodyNode;

  PROCEDURE NewIfElseNode*(if : IfBody; else : StmtList) : IfElse;
    VAR n : IfElse;
  BEGIN
    NEW(n); InitStmtListNode(n, Sifelse); n.ifstat := if; n.else := else; RETURN n;
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
  BEGIN NEW(n); InitStmtListNode(n, Swith); n.wstat := wstat; n.else := else; RETURN n;
  END NewWithNode;

  PROCEDURE NewCaseBoundsNode*(bound : Symtab.Const) : CaseBounds;
    VAR n : CaseBounds;
  BEGIN NEW(n); n.next := NIL; n.bound := bound; RETURN n;
  END NewCaseBoundsNode;

  PROCEDURE BindCaseBounds*(old, new : CaseBounds) : CaseBounds;
  BEGIN new.next := old; RETURN new;
  END BindCaseBounds;

  PROCEDURE NewSingleCaseNode*(bound : CaseBounds; stmt : StmtList) : SingleCase;
    VAR n : SingleCase;
  BEGIN NEW(n); InitBasicNode(n, Nmisc, Msglcase, Symtab.notyp); n.bounds := bound; n.stmt := stmt;
    RETURN n;
  END NewSingleCaseNode;

  PROCEDURE BindSingleCase*(last, new : SingleCase) : SingleCase;
  BEGIN  IF last # NIL THEN last.next := new; END; RETURN new;
  END BindSingleCase;

  PROCEDURE NewCaseStatNode*(low, high : LONGINT; case : SingleCase; else : StmtList) : CaseStat;
    VAR n : CaseStat;
  BEGIN
    NEW(n); InitBasicNode(n, Nmisc, Mcasestat, Symtab.notyp);
    n.range := Symtab.NewConst(Symtab.linttyp); n.range.i0 := low; n.range.i1 := high;
    n.case := case; n.else := else; RETURN n;
  END NewCaseStatNode;

  PROCEDURE NewCaseNode*(expr : Expr; of : CaseStat) : Case;
    VAR n : Case;
  BEGIN NEW(n); InitStmtListNode(n, Scase); n.expr := expr; n.of := of; RETURN n;
  END NewCaseNode;

  PROCEDURE NewLoopNode*(body : StmtList) : Loop;
    VAR n : Loop;
  BEGIN NEW(n); InitStmtListNode(n, Sloop); n.body := body; RETURN n;
  END NewLoopNode;

  PROCEDURE NewForNode*(ctrl : Design; low, hi : Expr; step : LONGINT; body : StmtList) : For;
    VAR n : For;
  BEGIN NEW(n); InitStmtListNode(n, Sfor);
    n.control := ctrl; n.lower := low; n.upper := hi; n.step := step; n.body := body;
    RETURN n;
  END NewForNode;

  PROCEDURE NewWhileRepeatNode*(subcl : NODESUBCLASS; cond : Expr; body : StmtList) : WhileRepeat;
    VAR n : WhileRepeat;
  BEGIN NEW(n); InitStmtListNode(n, subcl); n.cond := cond; n.body := body; RETURN n;
  END NewWhileRepeatNode;

  PROCEDURE NewReturnNode*(owner : Symtab.Symbol; expr : Expr) : Return;
    VAR n : Return;
  BEGIN NEW(n); InitStmtListNode(n, Sreturn); n.proc := owner; n.expr := expr; RETURN n;
  END NewReturnNode;

  (*** Utility ***)
  (* Binds r onto l, returns tail of the statement list *)
  PROCEDURE BindStmtList*(l, r : StmtList) : StmtList;
    VAR c : NODECLASS; sc : NODESUBCLASS; misc, stmt : BOOLEAN;
  BEGIN ASSERT((l # NIL) OR (r # NIL));
    IF l = NIL THEN RETURN r;
    ELSE
      c := l.class; sc := l.subcl;
      misc := (c = Nmisc);
      stmt := (c = Nstmt) & (sc = Snull);
      IF (misc OR stmt) & (r # NIL) THEN RETURN r;
      ELSIF r # NIL THEN
        c := r.class; sc := r.subcl;
        misc := (c = Nmisc);
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
  (* NIL => parameter does not exist *)
  PROCEDURE ArgN*(x : Arg; n : INTEGER) : Expr;
    VAR y : Arg;
  BEGIN (* ASSERT(x.class = Ecall) *)
    y := ArgumentN(x, n);
    IF y # NIL THEN RETURN y.arg;
    ELSE RETURN NIL;
    END;
  END ArgN;
  
  PROCEDURE SetTreeTraversalProc*(m : TreeTraversalProc);
  BEGIN Module := m;
  END SetTreeTraversalProc;

  PROCEDURE NILGlobalPointers;
  BEGIN Module := NIL;
  END NILGlobalPointers;
  
  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    ASSERT(Dlast <= MAX(SET) + 1, 1024); ASSERT(Slast <= MAX(SET) + 1, 1025);
    ASSERT(Elast <= MAX(SET) + 1, 1026); ASSERT(Mlast <= MAX(SET) + 1, 1027);
    ASSERT(Module # NIL, 1028);
    RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;

BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
END O3TreeNode.
