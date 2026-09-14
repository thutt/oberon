MODULE O3TypeAllocate; (* Type & Variable allocation *)
  IMPORT
    Config := O3Config,
    AST := O3TreeNode,
    Symtab := O3Symtab,
    E := O3Errors;

  CONST (*- Dynamic Array Info *)
    (* These constants define a bit about the structure of dynamic
     * array blocks on the heap and their values are tightly coupled
     * to the heap allocator and the garbage collector as well as to the
     * code generator.
     *
     * These values are set here rather than being installed by the machine
     * because they are designed to not require changing when creating a new
     * backend.  Plus, changing them requires extensive changes to the Oberon
     * Kernel module as well and that work should be discouraged.
     *)

    (* Offsets in a descriptor for (heap-based) dynamic arrays where
     * the 0-th bound is stored.
     * Offsets to larger dimensions are stored at larger negative offsets;
     * See LMST.Size().
     * See documentation for layout of a heap-allocated array
     *)
    DynArrSmpLen0Offs = -(SIZE(LONGINT) +
                          SIZE(LONGINT));  (* element: simple & procedure *)
    DynArrPtrLen0Offs = -(SIZE(LONGINT) +
                          SIZE(LONGINT));  (* element: pointer *)
    DynArrRecLen0Offs = -(SIZE(LONGINT) +
                          SIZE(LONGINT));  (* element: record *)

    (* (base) offsets of the 0-th element in dynamic arrays*)
    DynArrSmpElem0Offs = 0;  (* element: simple & procedure *)
    DynArrPtrElem0Offs = 0;  (* element: pointer *)
    DynArrRecElem0Offs = 0;  (* element: record *)

    (* Basic size of dynamic array types.
     * 97.06.15:
     * Since the allocation size of heap-based dynamic arrays is handled
     * by the heap allocator (by using the information from the type
     * descriptor), the size of a heap-based dynamic array is unused by
     * the compiler. (They are unused because there is no way to access the
     * size of a dynamically allocated array entity.)
     *)
    DynArrSmpElemSize = 0;
    DynArrPtrElemSize = 0;
    DynArrRecElemSize = 0;


  TYPE
    CountTBProcInfo = RECORD (Symtab.ProcessScopeInfo)
      rec : Symtab.Record;
    END;

    TDInfo = RECORD (Symtab.ProcessScopeInfo)
      owner : Symtab.Symbol;
    END;

    VariableInfo = RECORD (Symtab.ProcessScopeInfo)
      dsize : LONGINT;
    END;

  VAR
    InitTDList, InitTDListTail : AST.Node;

  PROCEDURE ^ TBProcedures(scope : Symtab.SymbolScope);
  PROCEDURE ^ Parameters(proc: Symtab.SymbolProc; proctype : Symtab.Procedure);
  PROCEDURE ^ Procedure(proc : Symtab.SymbolProc);
  PROCEDURE ^ AllocateType(type : Symtab.Type);
  PROCEDURE ^ Allocate(scope : Symtab.SymbolScope; owner : Symtab.Symbol);

  (* alignment of base type *)
  PROCEDURE BaseAlignment*(type : Symtab.Type) : LONGINT;
    VAR
      align : LONGINT;
  BEGIN
    WHILE type.form = Symtab.array DO
      type := type(Symtab.Array).of;
    END;
    IF type.form = Symtab.record THEN
      RETURN type(Symtab.Record).align;
    ELSE
      align := type.size;
      IF align > 4 THEN
        RETURN 4;
      ELSE
        RETURN align;
      END;
    END;
  END BaseAlignment;

  PROCEDURE Size*(type : Symtab.Type);
    VAR
      f : SHORTINT;
      offset, size, align, falign, offs : LONGINT;
      elem, base : Symtab.Type;
      arr : Symtab.Array;
      rec : Symtab.Record;
      fld : Symtab.Symbol;
  BEGIN
    IF ~(Symtab.allocated IN type.flags) THEN
      f := type.form;
      CASE f OF
      | Symtab.record:
        rec := type(Symtab.Record);
        base := rec.ancestor;
        IF base = NIL THEN
          offset := 0;
          align := 1;
        ELSE
          Size(base);
          offset := base.size;
          align := base(Symtab.Record).align;
        END;

        fld := Symtab.FirstField(rec);
        WHILE (fld # NIL) & (fld.kind = Symtab.field) DO
          base := fld.type; Size(base);
          size := base.size;
          falign := BaseAlignment(base);
          Config.PositiveAlign(offset, falign);
          fld.adr := offset;
          INC(offset, size);
          IF falign > align THEN
            align := falign;
          END;
          fld := Symtab.NextField(fld);
        END;
        rec.align := align;
        Config.PositiveAlign(offset, BaseAlignment(rec));
        rec.size := offset;

      | Symtab.array:
        arr := type(Symtab.Array);
        base := arr.of; Size(base);
        arr.size := arr.n * base.size;

      | Symtab.openarr: arr := type(Symtab.Array); base := arr.of; Size(base);
        IF base.form = Symtab.openarr THEN
          arr.size := base.size + SIZE(LONGINT);
          arr.offset := base(Symtab.Array).offset + SIZE(LONGINT);
        ELSE
          arr.size := SIZE(LONGINT) + SIZE(LONGINT); (* data pointer + LEN(arr, 0) *)
          arr.offset := SIZE(LONGINT); (* LEN(arr, 0) offset *)
        END;

      | Symtab.dynarr:
        arr := type(Symtab.Array);
        base := arr.of;
        Size(base);
        IF base.form = Symtab.dynarr THEN
          arr.size := base.size + SIZE(LONGINT);
          arr.offset := base(Symtab.Array).offset - SIZE(LONGINT);
        ELSE
          elem := Symtab.ElemType(arr);
          IF elem.form = Symtab.array THEN
            elem := Symtab.ElemType(elem(Symtab.Array));
          END;
          CASE elem.form OF
          | Symtab.bool, Symtab.byte, Symtab.char, Symtab.sint,
            Symtab.int, Symtab.lint, Symtab.real, Symtab.lreal,
            Symtab.set, Symtab.procedure:
            arr.size := DynArrSmpElemSize;
            arr.offset := DynArrSmpLen0Offs;

          | Symtab.pointer:
            arr.size := DynArrPtrElemSize;
            arr.offset := DynArrPtrLen0Offs;

          | Symtab.record:
            arr.size := DynArrRecElemSize;
            arr.offset := DynArrRecLen0Offs;
          END;
        END;

      | Symtab.pointer:
        type.size := Symtab.metrics[Symtab.pointer].size;

      | Symtab.procedure:
        type.size := Symtab.metrics[Symtab.procedure].size;
      END;

      INCL(type.flags, Symtab.allocated);
    END;
  END Size;

  (*
   * Create type descriptor symbols for types which require them, and stick
   * them into the global scope so they will be allocated.  The visibility
   * of the type descriptor is essentially the same as the type which it
   * describes.
   *
   * Type descriptors are pointers, but not true pointers, but should be
   * treated as pointers by the rest of the allocation system.
   *)
  PROCEDURE ProcessTD(VAR info : Symtab.ProcessScopeInfo);
    VAR
      sym, owner : Symtab.Symbol;
    type : Symtab.Type;
    td : Symtab.SymbolTypeDesc;
    tdesc : AST.InitTD;
  BEGIN
    sym := info.sym;
    owner := info(TDInfo).owner;
    type := sym.type;
    ASSERT(type # NIL);
    td := Symtab.GetTD(owner, type);
    IF (td # NIL) & ~(Symtab.tdinit IN td.flags) THEN
      (* TD not yet encountered *)
      INCL(td.flags, Symtab.tdinit);
      tdesc := AST.NewInitTDNode(td);
      tdesc.next := InitTDList;
      InitTDList := tdesc;
      IF InitTDListTail = NIL THEN
        InitTDListTail := tdesc;
      END;
    END;
  END ProcessTD;

  PROCEDURE ProcessVariables(VAR info : Symtab.ProcessScopeInfo);
    VAR
      sym : Symtab.Symbol;
      type : Symtab.Type;
      adr : LONGINT;
  BEGIN
    sym := info.sym;
    adr := info(VariableInfo).dsize;
    Config.NegativeAlign(adr, Symtab.metrics[Symtab.lint].size);
    CASE sym.kind OF
    | Symtab.var, Symtab.darrdesc, Symtab.arrdesc, Symtab.recdesc:
      (* Type descriptors are pseudo-pointers allocated in the data segment.
       * Ultimately, they are fixed up to point to the actual data of the
       * descriptor. This is handled through the GSA inittd instructions.
       *)
      type := sym.type; AllocateType(type);
      Config.NegativeAlign(adr, BaseAlignment(type));
      DEC(adr, type.size);
      sym.adr := adr;
      info(VariableInfo).dsize := adr;
    ELSE (* nop *)
    END;
  END ProcessVariables;

  PROCEDURE ProcessObjects(VAR info : Symtab.ProcessScopeInfo);
    VAR
      sym : Symtab.Symbol;
  BEGIN
    sym := info.sym;
    CASE sym.kind OF
    | Symtab.lproc, Symtab.xproc, Symtab.cproc, Symtab.iproc:
      IF ~Symtab.IsModule(sym) THEN
        Procedure(sym(Symtab.SymbolProc));
      END;

    | Symtab.type:
      AllocateType(sym.type);
    ELSE (* nop *)
    END;
  END ProcessObjects;

  PROCEDURE ProcessTBProcedures(VAR info : Symtab.ProcessScopeInfo);
    VAR
      proc : Symtab.SymbolProc;
      sym : Symtab.Symbol;
      tdinfo : Symtab.ProcessScopeInfo;
  BEGIN
    sym := info.sym;
    IF sym.kind = Symtab.tproc THEN
      proc := sym(Symtab.SymbolProc);
      AllocateType(sym.type);
      Parameters(proc, sym.type(Symtab.Procedure));
      Allocate(proc.scope, proc);
    END;
  END ProcessTBProcedures;

  PROCEDURE ProcessCountTBP(VAR info : Symtab.ProcessScopeInfo);
    VAR
      meth, sym : Symtab.Symbol;
      rec : Symtab.Record;
  BEGIN
    sym := info.sym;
    rec := info(CountTBProcInfo).rec;
    IF sym.kind = Symtab.tproc THEN
      meth := Symtab.FindField(sym.name^, rec.ancestor);
      IF meth = NIL THEN (* not in base *)
        sym(Symtab.SymbolProc).methno := rec.nofmeth;
        INC(rec.nofmeth);
      ELSE
        sym(Symtab.SymbolProc).methno := meth(Symtab.SymbolProc).methno;
      END;

      IF ~(Symtab.body IN sym.flags) THEN
        Config.Error(E.UnsatisfiedForward);
      END;
    END;
  END ProcessCountTBP;

  PROCEDURE CountTBProcs(type : Symtab.Type);
    VAR
      ancestor, rec : Symtab.Record;
      scope : CountTBProcInfo;
  BEGIN
    rec := type(Symtab.Record);
    IF ~(Symtab.methodcounted IN rec.flags) THEN
      ASSERT(rec.nofmeth < 0);
      rec.nofmeth := 0;
      ancestor := rec.ancestor;

      IF ancestor # NIL THEN
        CountTBProcs(ancestor);
        rec.nofmeth := ancestor.nofmeth;
      END;
      scope.rec := rec;
      Symtab.ProcessScope(rec.scope, ProcessCountTBP, scope);
      INCL(rec.flags, Symtab.methodcounted);
    END;
  END CountTBProcs;

  PROCEDURE AllocateType(type : Symtab.Type);
    VAR
      base : Symtab.Type;
      field : Symtab.Symbol;
      info : TDInfo;
  BEGIN
    (* include Symtab.used? *)
    IF ~(Symtab.allocated IN type.flags) THEN
      Size(type);
      CASE type.form OF
      | Symtab.record:
        CountTBProcs(type);
        base := type(Symtab.Record).ancestor;
        IF base # NIL THEN
          AllocateType(base);
        END;

        field := Symtab.FirstScopeVar(type(Symtab.Record).scope);
        WHILE field # NIL DO
          AllocateType(field.type);
          field := Symtab.NextField(field);
        END;
        TBProcedures(type(Symtab.Record).scope);
        info.owner := type.sym;
        Symtab.ProcessScope(type(Symtab.Record).scope, ProcessTD, info);

      | Symtab.pointer: base := type(Symtab.Pointer).to; AllocateType(base);

      | Symtab.procedure:
        (* sysflag can be ignored here since only procedure variables
         * can have a non-standard sysflag; since only external procedures
         * should be assigned to these, the assigned address of the procedures
         * does not matter *)
        base := type(Symtab.Procedure).result;
        AllocateType(base);
        Parameters(NIL, type(Symtab.Procedure));

      | Symtab.array, Symtab.dynarr, Symtab.openarr:
        base := type(Symtab.Array).of;
        AllocateType(base);
      ELSE (* nop *)
      END;
    END;
  END AllocateType;

  PROCEDURE Parameters(proc: Symtab.SymbolProc; proctype : Symtab.Procedure);
    VAR
      par : Symtab.Symbol;
      s, padr, vadr : LONGINT;
      f : SHORTINT;
  BEGIN
    padr := 0;
    vadr := 0;
    par := Symtab.FirstParm(proctype);
    WHILE par # NIL DO
      AllocateType(par.type);
      IF par.kind = Symtab.varpar THEN
        f := par.type.form;
        IF f = Symtab.record THEN
          s := (Symtab.sysptrtyp.size + (* Type desc. *)
                Symtab.sysptrtyp.size); (* Address *)
        ELSIF f = Symtab.dynarr THEN
          s := par.type.size;
        ELSE
          s := Symtab.sysptrtyp.size; 
        END;
      ELSE
        IF f IN Symtab.AggregateSet THEN
          (* Pass address of these items, callee will copy. *)
          s := Symtab.sysptrtyp.size; 
        ELSE
          s := par.type.size;
        END;
      END;
      Config.PositiveAlign(s, 4);
      INC(padr, s);
      par.adr := padr;
      par := Symtab.NextParm(par);
    END;

    IF proc # NIL THEN
      proc.parsize := padr;
      proc.varsize := vadr;
    END;

    IF (proc # NIL) & (proc.kind = Symtab.lproc) & (proc.mnolev > 0) THEN
      INC(padr, Config.LProcParmOffset);
    ELSE
      INC(padr, Config.XProcParmOffset)
    END;

    par := Symtab.FirstParm(proctype);
    WHILE par # NIL DO
      par.adr := padr - par.adr;
      par := Symtab.NextParm(par);
    END;
  END Parameters;

  PROCEDURE Procedure(proc : Symtab.SymbolProc);
    VAR
      sym : Symtab.Symbol;
      info : Symtab.ProcessScopeInfo;
  BEGIN
    ASSERT(proc.type.form = Symtab.procedure);
    IF ~(Symtab.body IN proc.flags) THEN
      Config.Error(E.UnsatisfiedForward);
    END;
    AllocateType(proc.type);
    Parameters(proc, proc.type(Symtab.Procedure));
    Allocate(proc.scope, proc);
  END Procedure;

  PROCEDURE TBProcedures(scope : Symtab.SymbolScope);
    VAR
      info : Symtab.ProcessScopeInfo;
  BEGIN
    Symtab.ProcessScope(scope, ProcessTBProcedures, info);
  END TBProcedures;

  PROCEDURE TypeDescriptors(scope : Symtab.SymbolScope; owner : Symtab.Symbol);
    VAR
      info : TDInfo;
  BEGIN
    info.owner := owner;
    Symtab.ProcessScope(scope, ProcessTD, info); (* Put all type descriptors
                                                  * on the init list. *)
  END TypeDescriptors;

  PROCEDURE Objects(scope : Symtab.SymbolScope);
    VAR
      info : Symtab.ProcessScopeInfo;
  BEGIN
    Symtab.ProcessScope(scope, ProcessObjects, info);
  END Objects;

  PROCEDURE Variables(scope : Symtab.SymbolScope);
    VAR
      info : VariableInfo;
  BEGIN
    info.dsize := scope.dsize;
    Symtab.ProcessScope(scope, ProcessVariables, info);
    scope.dsize := info.dsize;
  END Variables;

  PROCEDURE Allocate(scope : Symtab.SymbolScope; owner : Symtab.Symbol);
  BEGIN
    TypeDescriptors(scope, owner);
    Objects(scope);
    Variables(scope);
  END Allocate;

  PROCEDURE AllocateScope*(scope : Symtab.SymbolScope; VAR inittd : AST.InitTD);
    VAR
      info : Symtab.ProcessScopeInfo;
  BEGIN
    scope.dsize := 0;
    Allocate(scope, Symtab.topScope);
    IF InitTDList # NIL THEN
      AST.ReverseNodeList(InitTDList);
      inittd := InitTDList(AST.InitTD);
    ELSE
      inittd := NIL;
    END;
  END AllocateScope;

  PROCEDURE NILGlobalPointers;
  BEGIN
    InitTDList := NIL;
    InitTDListTail := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    NILGlobalPointers;
    RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    NILGlobalPointers;
    RETURN TRUE;
  END ModuleEnd;

BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
END O3TypeAllocate.
