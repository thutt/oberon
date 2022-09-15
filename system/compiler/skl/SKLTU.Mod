MODULE SKLTU; (* Type utilities *)
IMPORT
  ST:=SKLST,
  OPM:=SKLMD,
  T:=SKLT,
  CGL:=SKLCGL,
  CGH:=SKLCGH,
  EL:=SKLERR;

   TYPE
      CountTBProcInfo = RECORD (ST.ProcessScopeInfo)
         rec : ST.Record;
      END;

   CONST
      VarParSize = OPM.PointerSize;
      RecVarParSize = 8;

   VAR
      GlobalScope : ST.SymbolScope;
      InitTDList : T.Node;

   PROCEDURE ^ TypeDescriptors(VAR info : ST.ProcessScopeInfo);

   PROCEDURE ScopeCountTBProcs(VAR info : ST.ProcessScopeInfo);
      VAR meth, sym : ST.Symbol; rec : ST.Record;
   BEGIN
     sym := info.sym;
     rec := info(CountTBProcInfo).rec;
     IF sym.kind = ST.tproc THEN
       meth := ST.FindField(sym.name^, rec.ancestor);
       IF meth = NIL THEN (* not in base *)
         sym(ST.SymbolProc).methno := rec.nofmeth;
         INC(rec.nofmeth);
       ELSE
         (* XXX Check that redef comes after original in text? Why? *)
         sym(ST.SymbolProc).methno := meth(ST.SymbolProc).methno;
       END;
       IF ~(ST.body IN sym.flags) THEN
         OPM.err(EL.UnsatisfiedForward); END;
     END;
   END ScopeCountTBProcs;

   PROCEDURE CountTBProcs(type : ST.Type);
      VAR ancestor, rec : ST.Record; scope : CountTBProcInfo;

   BEGIN
     rec := type(ST.Record);
     IF rec.nofmeth = -1 THEN
       ASSERT(~(ST.methodcounted IN rec.flags));
       (* nofmeth = -1 => ~(methodcounted in flags) *)
       (* ~(~(methodcounted in flags) => nofmeth = -1)  *)

       rec.nofmeth := 0;
       ancestor := rec.ancestor;
       IF ancestor # NIL THEN
         CountTBProcs(ancestor);
         rec.nofmeth := ancestor.nofmeth;
       END;
       scope.rec := rec;
       ST.ProcessScope(rec.scope, ScopeCountTBProcs, scope);
       INCL(rec.flags, ST.methodcounted);
     END;
   END CountTBProcs;

   PROCEDURE ^ TBProcedures(scope : ST.SymbolScope);
   PROCEDURE ^ Parameters(proc: ST.SymbolProc; proctype : ST.Procedure);
   PROCEDURE ^ Objects(scope : ST.SymbolScope);

  PROCEDURE AllocateType(type : ST.Type);
    VAR
      base : ST.Type;
      field : ST.Symbol;
      info : ST.ProcessScopeInfo;
  BEGIN
    (* include ST.used? *)
    IF ~(ST.allocated IN type.flags) THEN
      INCL(type.flags, ST.allocated);
      ST.Size(type);
      CASE type.form OF
      | ST.record:
        CountTBProcs(type); base := type(ST.Record).ancestor;
        IF base # NIL THEN
          AllocateType(base);
        END;
        field := ST.FirstScopeVar(type(ST.Record).scope);
        WHILE field # NIL DO
          AllocateType(field.type);
          field := ST.NextField(field);
        END;
        TBProcedures(type(ST.Record).scope);
        ST.ProcessScope(type(ST.Record).scope, TypeDescriptors, info);

      | ST.pointer:
        base := type(ST.Pointer).to;
        AllocateType(base);

      | ST.procedure:
        (* sysflag can be ignored here since only procedure variables
         * can have a non-standard sysflag; since only external procedures
         * should be assigned to these, the assigned address of the procedures
         * does not matter *)
        base := type(ST.Procedure).result;
        AllocateType(base);
        Parameters(NIL, type(ST.Procedure));

      | ST.array:
        base := type(ST.Array).of;
        AllocateType(base);

      | ST.dynarr:
        base := type(ST.Array).of;
        AllocateType(base);
      ELSE (* nop *)
      END;
    END;
  END AllocateType;

  PROCEDURE Parameters(proc: ST.SymbolProc; proctype : ST.Procedure);
    VAR
      par : ST.Symbol;
      type : ST.Type;
      s, padr, vadr : LONGINT;
      f : SHORTINT;
  BEGIN
    vadr := 0;
    padr := 0;
    par := ST.FirstParm(proctype);
    WHILE par # NIL DO
      type := par.type;
      f := type.form;
      AllocateType(type);
      IF par.kind = ST.varpar THEN
        IF f = ST.record THEN
          s := RecVarParSize;
        ELSIF f = ST.dynarr THEN
          s := type.size;
        ELSE
          s := VarParSize;
        END;
      ELSE
        IF f IN CGH.PassedByAddress THEN
          s := VarParSize; (* Pass address of these items, callee will copy. *)
        ELSE
          s := type.size;
        END;
      END;
      OPM.Align(s, 4);
      INC(padr, s);
      par.adr := padr;
      par := ST.NextParm(par);
    END;
    IF proc # NIL THEN
      proc.parsize := padr;
      proc.varsize := vadr;
    END;

    IF (proc # NIL) & (proc.kind = ST.lproc) & (proc.mnolev > 0) THEN
      INC(padr, CGL.LProcParmOffset);
    ELSE
      INC(padr, CGL.XProcParmOffset)
    END;

    par := ST.FirstParm(proctype);
    WHILE par # NIL DO
      par.adr := padr - par.adr;
      par := ST.NextParm(par);
    END;
  END Parameters;

  PROCEDURE Variables(sym : ST.Symbol; VAR dsize : LONGINT);
    VAR
      adr : LONGINT;
      type : ST.Type;
  BEGIN
    adr := dsize;
    OPM.NegAlign(adr, 4);
    WHILE sym # NIL DO
      IF CGL.AllocSeg[sym.kind] = CGL.segData THEN
        type := sym.type;
        AllocateType(type);
        OPM.NegAlign(adr, ST.Base(type));
        DEC(adr, type.size);
        sym.adr := adr;
      END;
      sym := ST.NextSymbol(sym);
    END;
    dsize := adr;
  END Variables;

   (* Create type descriptor symbols for types which require them, and
    * stick them into the global scope so they will be allocated as
    * variables.  The visibility of the type descriptor is essentially
    * the same as the type which it describes.  Type descriptors are
    * pointers, but not true pointers, and should be treated as such
    * by the rest of the allocation system.
    *)
   PROCEDURE TypeDescriptors(VAR info : ST.ProcessScopeInfo);
     VAR
       sym : ST.Symbol;
       type : ST.Type;
       td : ST.SymbolTypeDesc;
       adr : LONGINT;
       tdesc : T.InitTD;
   BEGIN
     sym := info.sym;
     type := sym.type;
     ASSERT(type # NIL);
     td := ST.GetTD(type);
     IF (td # NIL) &  ~(ST.tdinit IN td.flags) THEN
       INCL(td.flags, ST.tdinit);
       tdesc := T.NewInitTDNode(td);
       tdesc.next := InitTDList;
       InitTDList := tdesc;
     END;
   END TypeDescriptors;

   PROCEDURE Constant(sym : ST.Symbol);
   BEGIN
     ASSERT(sym.kind = ST.const);
     IF sym.type = ST.stringtyp THEN
       sym.adr := CGL.GenConstString(sym);
     END;
   END Constant;

   (* sym <=> first procedure parameter symbol *)
   PROCEDURE LocalVars(proc: ST.SymbolProc; VAR varsize : LONGINT);
   BEGIN
     Variables(ST.FirstLocalVar(proc), varsize);
   END LocalVars;

   PROCEDURE Procedure(proc : ST.SymbolProc);
     VAR
       sym : ST.Symbol;
       info : ST.ProcessScopeInfo;
   BEGIN
     ASSERT(proc.type.form = ST.procedure);
     IF ~(ST.body IN proc.flags) THEN
       OPM.err(EL.UnsatisfiedForward);
     END;
     (* XXX check that foward procedures end up with a body *)
     AllocateType(proc.type);
     IF proc.type.sysflag IN {OPM.StdCallVal, OPM.CCallVal} THEN
       ST.ReverseParmList(proc.type(ST.Procedure));
     END;
     Parameters(proc, proc.type(ST.Procedure));
     IF proc.type.sysflag IN {OPM.StdCallVal, OPM.CCallVal} THEN
       ST.ReverseParmList(proc.type(ST.Procedure));
     END;
     LocalVars(proc, proc.varsize);
     ST.ProcessScope(proc.scope, TypeDescriptors, info);
     Objects(proc.scope);
     proc.varsize := -proc.varsize;
     OPM.Align(proc.varsize, 4);
   END Procedure;

   PROCEDURE ProcessTBProcedures(VAR info : ST.ProcessScopeInfo);
     VAR
       proc : ST.SymbolProc;
       sym : ST.Symbol;
       tdinfo : ST.ProcessScopeInfo;
   BEGIN
     sym := info.sym;
     IF sym.kind = ST.tproc THEN
       proc := sym(ST.SymbolProc);
       AllocateType(sym.type);
       Parameters(proc, sym.type(ST.Procedure));
       LocalVars(proc, proc.varsize);
       ST.ProcessScope(proc.scope, TypeDescriptors, tdinfo);
       Objects(proc.scope);
       proc.varsize := -proc.varsize;
       OPM.Align(proc.varsize, 4);
     END;
   END ProcessTBProcedures;

   PROCEDURE TBProcedures(scope : ST.SymbolScope);
     VAR
       info : ST.ProcessScopeInfo;
   BEGIN
     ST.ProcessScope(scope, ProcessTBProcedures, info);
   END TBProcedures;

   PROCEDURE ProcessObjects(VAR info : ST.ProcessScopeInfo);
     VAR
       k : SHORTINT;
       sym : ST.Symbol;
   BEGIN
     sym := info.sym;
     k := sym.kind;
     IF k = ST.type THEN
       AllocateType(sym.type);
     ELSIF k = ST.const THEN
       Constant(sym);
     ELSIF (k IN {ST.lproc, ST.xproc, ST.cproc, ST.iproc}) & ~ST.IsModule(sym) THEN
       Procedure(sym(ST.SymbolProc));
     END;
   END ProcessObjects;

   PROCEDURE Objects(scope : ST.SymbolScope);
      VAR info : ST.ProcessScopeInfo;
   BEGIN
     ST.ProcessScope(scope, ProcessObjects, info);
   END Objects;

  PROCEDURE Allocate*(scope : ST.SymbolScope; VAR inittd : T.InitTD);
    VAR
      info : ST.ProcessScopeInfo;
  BEGIN
    scope.dsize := 0;
    GlobalScope := scope;
    InitTDList := NIL;
    ST.ProcessScope(scope, TypeDescriptors, info);

    Objects(scope);
    Variables(ST.FirstScopeVar(scope), scope.dsize); (* Allocate variables last
                                                      * because Objects can create
                                                      *  new type descriptors
                                                      *)
    IF InitTDList # NIL THEN
      T.ReverseNodeList(InitTDList);
      inittd := InitTDList(T.InitTD);
    ELSE
      inittd := NIL;
    END;
  END Allocate;

BEGIN
  (* If this fails, parameter address assignment needs to be updated. *)
  ASSERT(CGH.PassedByAddress = {ST.array, ST.record});
END SKLTU.
