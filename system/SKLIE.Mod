MODULE SKLIE;
IMPORT
  OPM:=SKLMD,
  ST:=SKLST, 
  OPS:=SKLOS,
  EL:=SKLERR;

  CONST  (* symbol file tags *)
    sftFirst      = ST.nofTypes + 0;
    sftMNAME      = sftFirst + 0;
    sftEND        = sftFirst + 1;
    sftTYPE        = sftFirst + 2;
    sftALIAS      = sftFirst + 3;
    sftVAR        = sftFirst + 4;
    sftRVAR        = sftFirst + 5;
    sftVALPAR      = sftFirst + 6;
    sftVARPAR      = sftFirst + 7;
    sftFLD        = sftFirst + 8;
    sftRFLD        = sftFirst + 9;
    sftHDPTR      = sftFirst + 10;
    sftHDPRO      = sftFirst + 11;
    sftTPRO        = sftFirst + 12;
    sftHDTPRO      = sftFirst + 13;
    sftXPRO        = sftFirst + 14;
    sftIPRO        = sftFirst + 15;
    sftCPRO        = sftFirst + 16;
    sftSTRUCT      = sftFirst + 17;
    sftSYS        = sftFirst + 18;
    sftPTR        = sftFirst + 19;
    sftARR        = sftFirst + 20;
    sftDARR        = sftFirst + 21;
    sftREC        = sftFirst + 22;
    sftPRO        = sftFirst + 23;
    sftTD        = sftFirst + 24;
    sftNOTD        = sftFirst + 25;
    sftCONST  = sftFirst + 26;
    sftLast        = sftFirst + 27;

  CONST (* symbol structure tags (for MakeSymbol) *)
    sstFirst      = sftLast + 0;
    sstSymbol      = sstFirst + 0;
    sstConst      = sstFirst + 1;
    sstScope      = sstFirst + 2;
    sstRecordTD    = sstFirst + 3;
    sstDynArrTD    = sstFirst + 4;
    sstArrTD    = sstFirst + 5;
    sstProcedure  = sstFirst + 6;
    sstCode        = sstFirst + 7;
    sstLast        = sstFirst + 8;

  CONST (* type struct tags (for extended type reconstitution) *)
    tstFirst        = sstLast + 0;
    tstType        = tstFirst + 0;
    tstArray      = tstFirst  + 1;
    tstDynArray    = tstFirst  + 2;
    tstPointer    = tstFirst  + 3;
    tstRecord      = tstFirst  + 4;
    tstProcedure  = tstFirst  + 5;
    tstLast        = tstFirst  + 6;

  CONST  (* first reference number for user defined types; must be greater than all SF tags *)
    FirstRef = tstLast + 0;
    nofTypeMax = FirstRef + OPM.nofTypeMax;

  CONST
    SelfImportAlias = "@self";

  TYPE
    ImportContext = RECORD
      nextTag : INTEGER;
      reffp : LONGINT;
      nofr, minr, nofm : INTEGER;
      self : BOOLEAN;
      ref : POINTER TO ARRAY nofTypeMax OF ST.Type;
      old : POINTER TO ARRAY nofTypeMax OF ST.Symbol;
      pvfp : ARRAY nofTypeMax OF LONGINT;
      glbmno : ARRAY OPM.MaxImports OF SHORTINT;
    END;

    ExportContext = RECORD
      reffp : LONGINT;
      ref : INTEGER;
      nofm : SHORTINT;
      locmno : ARRAY OPM.MaxImports OF SHORTINT;
    END;

  TYPE
    FPrintScopeInfo = RECORD (ST.ProcessScopeInfo)
      pbfp, pvfp : LONGINT;
    END;

    OutTProcInfo = RECORD (ST.ProcessScopeInfo)
      owner : ST.Record;
    END;
  
  VAR
    nofhdfld : LONGINT;
    impContext : ImportContext;
    expContext : ExportContext;
    symNew, symExtended : BOOLEAN;
    SymPresent : BOOLEAN; (* true => symbol file present; false => symbol file not present *)

  PROCEDURE ^ FPrintSymbol*(sym : ST.Symbol);
  PROCEDURE ^ FPrintId(type : ST.Type);
  PROCEDURE ^ FPrintFlds(rec : ST.Record; adr : LONGINT; visible : BOOLEAN; VAR pbfp, pvfp : LONGINT);
  PROCEDURE ^ FPrintType*(type : ST.Type);
  PROCEDURE ^ InType(VAR type : ST.Type);
  PROCEDURE ^ OutType(type : ST.Type);
  PROCEDURE ^ OutFlds(rec : ST.Record; adr : LONGINT; visible : BOOLEAN);

  PROCEDURE FPrintSignature(VAR fp : LONGINT; proc : ST.Procedure);
    VAR par : ST.Symbol;
  BEGIN
    FPrintId(proc.result);
    OPM.FPrint(fp, proc.result.idfp);
    par := ST.FirstParm(proc);
    WHILE (par # NIL) & (par.kind IN {ST.par, ST.varpar}) DO
      OPM.FPrint(fp, par.kind);
      FPrintId(par.type);
      OPM.FPrint(fp, par.type.idfp);
      par := ST.NextParm(par);
    END;
  END FPrintSignature;

  PROCEDURE FPrintName(VAR fp : LONGINT; name : ARRAY OF CHAR);
    VAR i : INTEGER; ch : CHAR;
  BEGIN i := 0; REPEAT ch := name[i]; INC(i); OPM.FPrint(fp, ORD(ch)); UNTIL ch = 0X;
  END FPrintName;

  PROCEDURE FPrintId(type : ST.Type);
    VAR f : SHORTINT; idfp : LONGINT; sym : ST.Symbol; base : ST.Type;
  BEGIN
    IF ~(ST.idfpdone IN type.flags) THEN
      INCL(type.flags, ST.idfpdone); (* may be recursive *)
      idfp := OPM.DefaultFP; f := type.form; sym := type.sym; OPM.FPrint(idfp, f);
      IF (sym # NIL) & (sym.name^ # "") THEN
        FPrintName(idfp, ST.GlbMod[type.mno].name^);
        FPrintName(idfp, sym.name^);
      END;
      CASE f OF
      |  ST.pointer: base := type(ST.Pointer).to; FPrintId(base); OPM.FPrint(idfp, base.idfp);
      |  ST.record:
        base := type(ST.Record).ancestor;
        IF base  # NIL THEN FPrintId(base); OPM.FPrint(idfp, base.idfp); END;
      |  ST.dynarr: base := type(ST.Array).of; FPrintId(base); OPM.FPrint(idfp, base.idfp);
      |  ST.array:
        base := type(ST.Array).of; FPrintId(base);
        OPM.FPrint(idfp, base.idfp); OPM.FPrint(idfp, type(ST.Array).n);
      |  ST.procedure:
        FPrintSignature(idfp, type(ST.Procedure));
      ELSE (* nop *)
      END;
      type.idfp := idfp;
    END;
  END FPrintId;

  PROCEDURE FPrintHdFld(type : ST.Type; fld : ST.Symbol; adr : LONGINT; VAR pbfp, pvfp : LONGINT);
    VAR i, j, n : LONGINT; baseT : ST.Type;
  BEGIN
    IF type.form = ST.record THEN FPrintFlds(type(ST.Record), adr, FALSE, pbfp, pvfp);
    ELSIF type.form = ST.array THEN
      baseT := type(ST.Array).of; n := type(ST.Array).n;
      WHILE baseT.form = ST.array DO (* why is this done? it is not used! *)
        n := n * baseT(ST.Array).n;
        baseT := baseT(ST.Array).of;
      END;
      IF (baseT.form = ST.pointer) OR (baseT.form = ST.record) THEN
        j := nofhdfld;
        FPrintHdFld(baseT, fld, adr, pbfp, pvfp);
        IF j # nofhdfld THEN
          i := 1;
          WHILE (i < n) & (nofhdfld <= OPM.MaxHdFld) DO
            INC(adr, baseT.size);
            FPrintHdFld(baseT, fld, adr, pbfp, pvfp);
            INC(i);
          END;
        END;
      END;
    ELSIF type.form = ST.pointer THEN OPM.FPrint(pvfp, ST.pointer); OPM.FPrint(pvfp, adr); INC(nofhdfld);
    ELSIF type.form = ST.procedure THEN OPM.FPrint(pvfp, ST.procedure); OPM.FPrint(pvfp, adr); INC(nofhdfld);
    END;
  END FPrintHdFld;

  PROCEDURE FPrintFlds(rec : ST.Record; adr : LONGINT; visible : BOOLEAN; VAR pbfp, pvfp : LONGINT);
    VAR fld : ST.Symbol;
  BEGIN
    fld := ST.FirstField(rec);
    WHILE fld # NIL DO
      IF (fld.vis IN {ST.export, ST.exportR}) & visible THEN
        OPM.FPrint(pbfp, fld.vis); FPrintName(pbfp, fld.name^); OPM.FPrint(pbfp, fld.adr);
        FPrintType(fld.type); OPM.FPrint(pbfp, fld.type.pbfp); OPM.FPrint(pvfp, fld.type.pvfp);
      ELSE FPrintHdFld(fld.type, fld, fld.adr + adr, pbfp, pvfp);
      END;
      fld := ST.NextField(fld);
    END;
  END FPrintFlds;

  PROCEDURE FPrintTProcs(VAR info : ST.ProcessScopeInfo);
    VAR sym : ST.Symbol;
  BEGIN sym := info.sym;
    IF sym.kind = ST.tproc THEN
      IF sym.vis IN {ST.export, ST.exportR} THEN
        OPM.FPrint(info(FPrintScopeInfo).pbfp, ST.tproc);
        OPM.FPrint(info(FPrintScopeInfo).pbfp, sym(ST.SymbolProc).methno);
        FPrintSignature(info(FPrintScopeInfo).pbfp, sym.type(ST.Procedure));
        FPrintName(info(FPrintScopeInfo).pbfp, sym.name^);
      ELSE (* hidden tprocs *)
        OPM.FPrint(info(FPrintScopeInfo).pvfp, ST.tproc);
        OPM.FPrint(info(FPrintScopeInfo).pvfp, sym(ST.SymbolProc).methno);
      END;
    END;
  END FPrintTProcs;

  PROCEDURE FPrintType*(type : ST.Type);
    VAR f : SHORTINT; baseT : ST.Type; baseS, typeS : ST.Symbol; fpinfo : FPrintScopeInfo;
  BEGIN
    IF ~(ST.typfpdone IN type.flags) THEN
      FPrintId(type);
      fpinfo.pbfp := type.idfp;
      IF type.sysflag # OPM.DefaultSysFlag THEN OPM.FPrint(fpinfo.pbfp, type.sysflag); END;
      fpinfo.pvfp := fpinfo.pbfp;
      type.pbfp := fpinfo.pbfp;
      type.pvfp := fpinfo.pvfp; (* might be recursive *)
      INCL(type.flags, ST.typfpdone);
      f := type.form;
      CASE f OF
        ST.pointer:
        baseT := type(ST.Pointer).to; baseS := baseT.sym; typeS := type.sym;
        IF (typeS = NIL) OR (typeS.name^ = "") OR (baseS = NIL) OR (baseS.name^ = "") THEN
          FPrintType(baseT); OPM.FPrint(fpinfo.pbfp, baseT.pbfp); fpinfo.pvfp := fpinfo.pbfp;
        END; (* else use idfp as pbfp & pvfp; do not call FPrintType(baseT) here, else cycle not broken *)
      |  ST.procedure: (* used idfp as pbfp and pvfp *)
      |  ST.array, ST.dynarr: (* td read & fingerprinted by InSymbol *)
        baseT := type(ST.Array).of; FPrintType(baseT); OPM.FPrint(fpinfo.pbfp, baseT.pvfp); fpinfo.pvfp := fpinfo.pbfp;
      |  ST.record: (* td read & fingerprinted by InSymbol *)
        baseT := type(ST.Record).ancestor;
        IF baseT # NIL THEN
          FPrintType(baseT); OPM.FPrint(fpinfo.pbfp, baseT.pvfp); OPM.FPrint(fpinfo.pvfp, baseT.size);
        END;
        OPM.FPrint(fpinfo.pvfp, type.size); OPM.FPrint(fpinfo.pvfp, type(ST.Record).align);
        OPM.FPrint(fpinfo.pvfp, type(ST.Record).nofmeth);
        nofhdfld := 0; FPrintFlds(type(ST.Record), 0, TRUE, fpinfo.pbfp, fpinfo.pvfp);
        IF nofhdfld > OPM.MaxHdFld THEN OPM.err(-1); END;
        ST.ProcessScope(type(ST.Record).scope, FPrintTProcs, fpinfo);
        OPM.FPrint(fpinfo.pvfp, fpinfo.pbfp); typeS := type.sym;
        IF (typeS = NIL) OR (typeS.name^ = "") THEN fpinfo.pbfp := fpinfo.pvfp; END;
      ELSE (* nop *)
      END;
      type.pbfp := fpinfo.pbfp;
      type.pvfp := fpinfo.pvfp;
    END;
  END FPrintType;

  PROCEDURE FPrintSymbol*(sym : ST.Symbol);
    VAR f : SHORTINT; fprint : LONGINT; i, m : INTEGER; rval : REAL; ext : ST.ConstExt; sc : ST.SymbolConst;
  BEGIN
    IF ~(ST.idfpdone IN sym.flags) THEN
      fprint := OPM.DefaultFP;
      INCL(sym.flags, ST.idfpdone);
      OPM.FPrint(fprint, sym.kind);
      CASE sym.kind OF
      |  ST.const:
        sc := sym(ST.SymbolConst); f := sc.type.form; OPM.FPrint(fprint, f);
        CASE f OF
        |  ST.bool, ST.char, ST.sint, ST.int, ST.lint: OPM.FPrint(fprint, sc.val.i0);
        |  ST.set: OPM.FPrintSet(fprint, sc.val.set);
        |  ST.real: rval := SHORT(sc.val.real); OPM.FPrintReal(fprint, rval);
        |  ST.lreal: OPM.FPrintLReal(fprint, sc.val.real);
        |  ST.string: FPrintName(fprint, sc.val.ext^);
        |  ST.nil: (* nothing *)
        ELSE OPM.err(-1);
        END;
      |  ST.var:
        OPM.FPrint(fprint, sym.vis); FPrintType(sym.type); OPM.FPrint(fprint, sym.type.pbfp);
      |  ST.recdesc, ST.darrdesc, ST.arrdesc:
        OPM.FPrint(fprint, sym.vis); FPrintType(sym.type); OPM.FPrint(fprint, sym.type.pbfp);
      |  ST.xproc, ST.lproc, ST.iproc:
        FPrintSignature(fprint, sym.type(ST.Procedure));
      |  ST.cproc:
        FPrintSignature(fprint, sym.type(ST.Procedure));
        ext := sym(ST.SymbolCodeProc).code;
        m := ORD(ext[0]); i := 1;
        WHILE i <= m DO OPM.FPrint(fprint, ORD(ext[i])); INC(i); END;
      |  ST.type:
        FPrintType(sym.type); OPM.FPrint(fprint, sym.type.pbfp);
      END;
      sym.fprint := fprint;
    END;
  END FPrintSymbol;

  PROCEDURE FPrintErr(sym : ST.Symbol; errno : INTEGER);
  BEGIN
    IF sym.mnolev # 0 THEN OPM.SetObjModule(ST.GlbMod[-sym.mnolev].name^); OPM.SetObjName(sym.name^);
    ELSE OPM.SetObjModule(""); OPM.SetObjName(sym.name^);
    END;
    IF errno = EL.FprintInconsistent THEN
      IF OPM.noerr THEN OPM.err(errno); END;
    ELSIF errno = EL.FprintNew THEN
      IF ~symNew & ~symExtended & ~OPM.optExtSF THEN OPM.err(errno); END;
      symExtended := TRUE;
    ELSE
      IF ~symNew & ~OPM.optNewSF THEN OPM.err(errno); END;
      symNew := TRUE;
    END;
  END FPrintErr;

  PROCEDURE InName() : ST.SymbolName; (* length prefixed (0X not included in prefix length) *)
    VAR i : INTEGER; ch : CHAR; l : LONGINT; name : ST.SymbolName;
  BEGIN OPM.SymRInt(l);
    NEW(name, l + 1);
    i := 0; WHILE i < l DO OPM.SymRCh(ch); name[i] := ch; INC(i); END;
    name[i] := 0X;
    RETURN name;
  END InName;

  PROCEDURE InSymbolName(sym : ST.Symbol);
    VAR name : ST.SymbolName;
  BEGIN name := InName(); ST.SetSymbolName(sym, name^);
  END InSymbolName;

  PROCEDURE InMod(VAR mno : SHORTINT);
    VAR head : ST.ModuleScope; name : ST.SymbolName; mn : LONGINT; i : SHORTINT;
  BEGIN
    OPM.SymRInt(mn);
    IF mn = 0 THEN mno := impContext.glbmno[0];
    ELSE
      IF mn = sftMNAME THEN
        name := InName();
        IF (name^ = ST.SelfName) & ~impContext.self THEN OPM.err(EL.RecursiveImport); END;
        i := 0; WHILE (i < ST.nofGmod) & (name^ # ST.GlbMod[i].name^) DO INC(i); END;

        IF i < ST.nofGmod THEN mno := i; (* already present *)
        ELSE
          head := ST.NewModuleScopeSym(); ST.SetSymbolName(head, name^); mno := ST.nofGmod; head.mnolev := -mno;
          IF ST.nofGmod < OPM.MaxImports THEN ST.GlbMod[mno] := head; INC(ST.nofGmod);
          ELSE OPM.err(EL.TooManyImports);
          END;
        END;
        impContext.glbmno[impContext.nofm] := mno; INC(impContext.nofm);
      ELSE mno := impContext.glbmno[-mn];
      END;
    END;
  END InMod;

  PROCEDURE InConstant(f : LONGINT; conval : ST.Const);
    VAR ch : CHAR; i : INTEGER; ext : ST.ConstExt; rval : REAL; cname : ST.SymbolName;
  BEGIN
    CASE f OF
    |  ST.bool, ST.byte, ST.char: OPM.SymRInt(conval.i0);
    |  ST.sint, ST.int, ST.lint: OPM.SymRInt(conval.i0);
    |  ST.set: OPM.SymRSet(conval.set);
    |  ST.real: OPM.SymRReal(rval); conval.real := rval; conval.i1 := OPM.ConstNotAlloc;
    |  ST.lreal: OPM.SymRLReal(conval.real); conval.i1 := OPM.ConstNotAlloc;
    |  ST.string:
      ext := ST.NewConstExt(); conval.ext := ext; cname := InName(); COPY(cname^, ext^);
      i := 0; REPEAT INC(i); UNTIL cname[i - 1] = 0X;
      conval.i0 := i; (* number of characters in constant; including 0X *) conval.i1 := OPM.ConstNotAlloc;
    |  ST.nil: conval.i0 := OPM.NilVal;
    END;
  END InConstant;

  PROCEDURE MakeType() : ST.Type;
    VAR tag : LONGINT; typ : ST.Type;
  BEGIN
    OPM.SymRInt(tag);
    CASE tag OF
    |  tstType: typ := ST.NewBasicType(); ASSERT(FALSE); (* these should be output as reference *)
    |  tstArray: typ := ST.NewArrayType(ST.array);
    |  tstDynArray: typ := ST.NewArrayType(ST.dynarr);
    |  tstPointer: typ := ST.NewPointerType();
    |  tstRecord: typ := ST.NewRecordType();
    |  tstProcedure: typ := ST.NewProcedureType();
    END;
    RETURN typ;
  END MakeType;

  PROCEDURE MakeSymbol(kind : SHORTINT; described : ST.Type) : ST.Symbol;
    VAR tag : LONGINT; sym : ST.Symbol;
  BEGIN
    OPM.SymRInt(tag);
    CASE tag OF
    |  sstSymbol: sym := ST.NewBasicSym(kind);
    |  sstConst: ASSERT(FALSE, 142); (* 1999.01.23: should never happen (must know type at this point) *)
    |  sstScope: ASSERT(FALSE, 143); (* 1999.01.06: should never happen.  What is the proper scope size to create? *)
    |  sstRecordTD: sym := ST.NewRecordTD(described);
    |  sstDynArrTD: sym := ST.NewDynArrayTD(described);
    |  sstArrTD: sym := ST.NewArrayTD(described);
    |  sstProcedure: sym := ST.NewProcedureSym();
    |  sstCode: ASSERT(FALSE, 141); (* code procedures can only be global, and handled by InSymbol *)
    END;
    (* all imported symbols have the mnolev field set to their owning imported module number *)
    (* this makes it easy to determine if a symbol OR a field is imported & exportR *)
    sym.mnolev := -SHORT(impContext.nofm);
    RETURN sym;
  END MakeSymbol;

  PROCEDURE ReadTag(VAR t : INTEGER);
    VAR x : LONGINT;
  BEGIN  OPM.SymRInt(x); ASSERT(x > -impContext.nofr); ASSERT(x < sftLast); t := SHORT(x);
  END ReadTag;

  PROCEDURE OutTypeTag(type : ST.Type);
  BEGIN
    CASE type.form OF
    |  ST.undef, ST.bool, ST.byte, ST.char, ST.sint, ST.int, ST.lint, ST.real, ST.lreal, ST.set, ST.string, ST.nil, ST.void: OPM.SymWInt(tstType);
    |  ST.pointer: OPM.SymWInt(tstPointer);
    |  ST.procedure: OPM.SymWInt(tstProcedure);
    |  ST.array: OPM.SymWInt(tstArray);
    |  ST.dynarr: OPM.SymWInt(tstDynArray);
    |  ST.record: OPM.SymWInt(tstRecord);
    END;
  END OutTypeTag;

  PROCEDURE OutSymbolTag(sym : ST.Symbol);
  BEGIN
    CASE sym.kind OF
    |  ST.anon, ST.var, ST.par, ST.varpar, ST.field, ST.type: OPM.SymWInt(sstSymbol);
    |  ST.const: OPM.SymWInt(sstConst); ASSERT(FALSE, 130); (* should never happen *)
    |  ST.xproc, ST.iproc, ST.tproc: OPM.SymWInt(sstProcedure);
    |  ST.cproc: OPM.SymWInt(sstCode);
    |  ST.scope: OPM.SymWInt(sstScope); ASSERT(FALSE, 131);  (* exported scopes are not supported *)
    |  ST.darrdesc: OPM.SymWInt(sstDynArrTD);
    |  ST.arrdesc: OPM.SymWInt(sstArrTD);
    |  ST.recdesc: OPM.SymWInt(sstRecordTD);
    END;
  END OutSymbolTag;

  PROCEDURE InSignature(mno : SHORTINT; VAR proc : ST.Type);
    VAR dummy : ST.SymbolScope; sym : ST.Symbol; tag : INTEGER; kind : SHORTINT;
      type : ST.Procedure; name : ST.SymbolName;
  BEGIN type := proc(ST.Procedure);
    ST.OpenProcedureScope(mno, NIL); InType(type.result); ReadTag(tag);
    WHILE tag # sftEND DO
      IF tag = sftVALPAR THEN kind := ST.par ELSE kind := ST.varpar; END;
      sym := MakeSymbol(kind, NIL); InType(sym.type); OPM.SymRInt(sym.adr); OPM.SymRSet(sym.flags); name := InName();
      ST.Insert(name^, sym); ReadTag(tag);
    END;
    type.parms := ST.FirstScopeVar(ST.topScope); dummy := ST.CloseScope();
  END InSignature;

  PROCEDURE InFld(VAR fld : ST.Symbol);
    VAR tag : INTEGER;
  BEGIN
    tag := impContext.nextTag;
    IF tag <= sftRFLD (* {sftRFLD, sftFLD} *) THEN fld := MakeSymbol(ST.field, NIL);
      IF tag = sftRFLD THEN fld.vis := ST.exportR;
      ELSE fld.vis := ST.export;
      END;
      InType(fld.type); OPM.SymRSet(fld.flags);
    ELSE (* {sftHDPTR, sftHDPRO} *) fld := ST.NewBasicSym(ST.field); INCL(fld.flags, ST.invisible);
      IF tag = sftHDPTR THEN fld.type := ST.sysptrtyp;
      ELSE ASSERT(tag = sftHDPRO); fld.type := ST.undftyp;
      END;
    END;
    InSymbolName(fld); OPM.SymRInt(fld.adr);
    ASSERT(fld.mnolev < 0);
  END InFld;

  PROCEDURE InTProc(mno : SHORTINT; VAR sym : ST.Symbol);
    VAR tproc : ST.SymbolProc;
  BEGIN tproc := ST.NewProcedureSym(); sym := tproc; sym.mnolev := -mno;
    IF impContext.nextTag = sftTPRO THEN
      InSignature(mno, tproc.type); OPM.SymRSet(tproc.flags); tproc.vis := ST.export;
    ELSE ASSERT(impContext.nextTag = sftHDTPRO); (* hidden tproc *) INCL(sym.flags, ST.invisible);
    END;
    InSymbolName(tproc); OPM.SymRInt(tproc.methno);
  END InTProc;

  PROCEDURE InTypeDescriptor(type : ST.Type; mno : SHORTINT);
    VAR sym, old : ST.Symbol; td : ST.SymbolTypeDesc; tdnum : LONGINT;
  BEGIN
    ReadTag(impContext.nextTag);
    IF impContext.nextTag = sftTD THEN
      sym := MakeSymbol(ST.anon, type); td := sym(ST.SymbolTypeDesc);
      OPM.SymRInt(tdnum); td.tdnum := SHORT(SHORT(tdnum));
      OPM.SymRSet(td.flags); InSymbolName(td); td.type := ST.linttyp; (* type must match creation of TD in SKLST *)
      td.vis := ST.hidden; td.mnolev := -mno;
      ASSERT(mno >= 0, 150); ASSERT(mno <= ST.nofGmod, 151);
      ST.InsertImport(ST.GlbMod[mno], td, old);
    ELSE (* sftNOTD *) td := NIL;
    END;
    IF type.form IN {ST.array, ST.dynarr} THEN type(ST.Array).td := td;
    ELSE type(ST.Record).td := td;
    END;
  END InTypeDescriptor;
  
  PROCEDURE ReadType(mno : SHORTINT; VAR t : ST.Type);
    VAR tag : INTEGER; i : LONGINT; r : ST.Record; ancestor : ST.Type; fld, dummy : ST.Symbol;
  BEGIN ReadTag(tag);
    IF tag = sftSYS THEN OPM.SymRInt(i); t.sysflag := SHORT(i); ReadTag(tag); END;
    CASE tag OF
    |  sftPTR: InType(t(ST.Pointer).to); t.size := OPM.PointerSize;
    |  sftARR, sftDARR:
      InType(t(ST.Array).of); OPM.SymRInt(t(ST.Array).n); OPM.SymRInt(t(ST.Array).offset); OPM.SymRInt(t.size);
      InTypeDescriptor(t, mno);
    |  sftREC:
      r := t(ST.Record); r.scope := ST.NewRecordScopeSym();
      InType(ancestor);
      (* if there were a compiler-default baseType, this could be avoided *)
      IF ancestor = ST.niltyp THEN r.ancestor := NIL; r.extlev := 0;
      ELSE r.ancestor := ancestor(ST.Record); r.extlev := r.ancestor.extlev + 1;
      END;
      OPM.SymRInt(r.size); OPM.SymRInt(r.align); OPM.SymRInt(r.nofmeth);
      InTypeDescriptor(t, mno);
      ReadTag(impContext.nextTag);
      WHILE (impContext.nextTag >= sftFLD) & (impContext.nextTag <= sftHDPRO) DO
        (* setting mno to nesting levels gets confusing w/ local nested records! *)
        tag := impContext.nextTag; InFld(fld); ST.InsertImport(r.scope, fld, dummy);
        ReadTag(impContext.nextTag);
      END;
      WHILE impContext.nextTag # sftEND DO InTProc(mno, fld); ST.InsertImport(r.scope, fld, dummy); ReadTag(impContext.nextTag); END;
    |  sftPRO: t.size := OPM.ProcSize; InSignature(mno, t);
    END;
  END ReadType;
  
  PROCEDURE InType(VAR type : ST.Type);
    VAR mno : SHORTINT; ref, tag : INTEGER; name : ST.SymbolName; t : ST.Type; obj, old : ST.Symbol; flags : SET;
  BEGIN ReadTag(tag);
    IF tag # sftSTRUCT THEN type := impContext.ref[-tag];
    ELSE
      ref := impContext.nofr; INC(impContext.nofr);
      IF ref < impContext.minr THEN impContext.minr := ref; END;
      InMod(mno); OPM.SymRSet(flags); name := InName(); t := MakeType(); (* t <=> newly created type *)
      obj := ST.NewBasicSym(ST.type);
      IF name^ = "" THEN (* anonymous symbol *)
        IF impContext.self THEN old := NIL; (* do not insert type desc anchor here; in CGL (?) *)
        ELSE ST.SetSymbolName(obj, "@"); ST.InsertImport(ST.GlbMod[mno], obj, old);
        END;
        ST.SetSymbolName(obj, "");
        type := t;
      ELSE ST.SetSymbolName(obj, name^); ST.InsertImport(ST.GlbMod[mno], obj, old);
        IF old # NIL THEN (* recalc fingerprints to compare with old *)
          FPrintSymbol(old); impContext.pvfp[ref] := old.type.pvfp;
          IF impContext.self THEN type := t; (* do not overwrite existing type *)
          ELSE type := old.type; EXCL(type.flags, ST.typfpdone); EXCL(type.flags, ST.idfpdone);
          END;
        ELSE type := t; (* no existing symbol; output type <=> newly created type *)
        END;
      END;
      impContext.ref[ref] := type; impContext.old[ref] := old;
      t.ref := ref + nofTypeMax; (* ref >= nofTypeMax <=> not exported; used for 'cannot create new symF' *)
      t.mno := mno; INCL(t.flags, ST.allocated); t.sym := obj; obj.type := t; obj.mnolev := -mno;
      t.flags := flags; ReadType(mno, t);

      IF ref = impContext.minr THEN
        WHILE ref < impContext.nofr DO
          t := impContext.ref[ref]; FPrintType(t);
          obj := t.sym; (* obj.type.sym = obj, else obj.fprint differs (alias) *)
          ASSERT(obj.name # NIL, 135);
          IF obj.name^ # "" THEN FPrintSymbol(obj); END;
          old := impContext.old[ref];
          IF old # NIL THEN t.sym := old; (* restore old symbol *)
            IF impContext.self THEN
              IF old.mnolev < 0 THEN
                IF old.history # ST.inconsistent THEN
                  IF old.fprint # obj.fprint THEN old.history := ST.pbmodified;
                  ELSIF impContext.pvfp[ref] # t.pvfp THEN old.history := ST.pvmodified;
                  END;
                (* else remains inconsistent *)
                END;
              ELSIF old.fprint # obj.fprint THEN old.history := ST.pbmodified;
              ELSIF impContext.pvfp[ref] # t.pvfp THEN old.history := ST.pvmodified;
              ELSIF old.vis = ST.internal THEN old.history := ST.same;
              ELSE old.history := ST.inserted;
              END;
            ELSE (* check private; delay arror until really used *)
              IF impContext.pvfp[ref] # t.pvfp THEN old.history := ST.inconsistent; END;
              IF old.fprint # obj.fprint THEN FPrintErr(old, EL.FprintInconsistent); END;
            END;
          ELSIF impContext.self THEN obj.history := ST.removed;
          ELSE obj.history := ST.same;
          END;
          INC(ref);
        END;
        impContext.minr := nofTypeMax;
      END;
    END;
  END InType;

  PROCEDURE InSymbol(mno : SHORTINT; VAR sym : ST.Symbol);
    VAR
      kind : SHORTINT; tag, i, s : INTEGER; ch : CHAR;  flags : SET;
      obj, old : ST.Symbol; ext : ST.ConstExt; sc : ST.SymbolCodeProc; type : ST.Type;
  BEGIN tag := impContext.nextTag;
    CASE tag OF
    |  sftTYPE:
      OPM.SymRSet(flags); InType(type); obj := type.sym; obj.flags := flags;
      IF ~impContext.self THEN obj.vis := ST.export; (* name visible; fprint already done *) END;
    |  sftALIAS:
      obj := ST.NewBasicSym(ST.type); OPM.SymRSet(obj.flags); InType(obj.type); obj.vis := ST.export; InSymbolName(obj);
    |  sftRVAR, sftVAR:
      obj := MakeSymbol(ST.var, NIL); InType(obj.type); OPM.SymRSet(obj.flags); InSymbolName(obj);
      IF tag = sftRVAR THEN obj.vis := ST.exportR; ELSE obj.vis := ST.export; END;
    |  sftPRO: ASSERT(FALSE); (* procedure type, not symbol *)
    |  sftXPRO, sftIPRO:
      IF tag = sftXPRO THEN kind := ST.xproc; ELSE kind := ST.iproc; END;
      obj := ST.NewProcedureSym(); obj.type := ST.NewProcedureType(); InSignature(mno, obj.type);
      OPM.SymRSet(obj.flags); InSymbolName(obj); obj.kind := kind; obj.vis := ST.export;
      IF ST.modinit IN obj.flags THEN INCL(obj.flags, ST.used); END; (* module init always used for Obj.Uses block *)
    |  sftCPRO:
      sc := ST.NewCodeProcSym(); obj := sc; sc.type := ST.NewProcedureType(); InSignature(mno, sc.type);
      OPM.SymRCh(ch); s := ORD(ch); ext := sc.code;
      ext[0] := ch; i := 1; WHILE i <= s DO OPM.SymRCh(ext[i]); INC(i); END;
      OPM.SymRSet(obj.flags); InSymbolName(obj); obj.vis := ST.export;
    |  sftCONST:
      ReadTag(tag); obj := ST.NewConstSym(impContext.ref[tag]);
      InConstant(tag, obj(ST.SymbolConst).val); OPM.SymRSet(obj.flags); InSymbolName(obj);
      obj.vis := ST.export;
    END;
    obj.mnolev := -mno; FPrintSymbol(obj);

    ASSERT(~(obj.kind IN {ST.var}) OR (obj.type.sym # NIL ) & (obj.type.sym.name # NIL), 154);
    IF (obj.kind IN {ST.var}) & ((obj.type.sym = NIL) OR (obj.type.sym.name^ = "")) THEN
      (* global fprint to avoid structural type equiv for anon types *)
      OPM.FPrint(impContext.reffp, obj.type.ref - nofTypeMax);
    END;

    IF tag # sftTYPE THEN
      ST.InsertImport(ST.GlbMod[mno], obj, old);
      IF impContext.self THEN
        IF old # NIL THEN (* obj is from old symF, old is new declaration (just compiled) *)
          IF old.vis = ST.internal THEN old.history := ST.removed;
          ELSE
            FPrintSymbol(old); (* obj already done *)
            IF obj.fprint # old.fprint THEN old.history := ST.pbmodified;
            ELSIF obj.type.pvfp # old.type.pvfp THEN old.history := ST.pvmodified;
            ELSE old.history := ST.same;
            END;
          END;
        ELSE obj.history := ST.removed; (* OutObj not called if mnolev < 0 *)
        END;
      END; (* else old = NIL or file read twice; consistent; OutObj not called *)
    ELSE (* obj already inserted in InType *)
      IF impContext.self THEN (* obj.mnolev = 0 *)
        IF obj.vis = ST.internal THEN obj.history := ST.removed;
        ELSIF obj.history = ST.inserted THEN obj.history := ST.same;
        END;
      END; (* else OutObj not called when mnolev < 0 *)
    END;
    sym := obj;
  END InSymbol;

PROCEDURE Import*(VAR alias, name : ARRAY OF CHAR; VAR done : BOOLEAN);
  VAR
    sym : ST.Symbol;
    mno : SHORTINT;
    module : ST.SymbolProc;

  PROCEDURE ModuleSymbol(mno : SHORTINT) : ST.SymbolProc;
    VAR
      m : ST.SymbolProc;
  BEGIN
    m := ST.NewProcedureSym();
    m.kind := ST.xproc;
    INCL(m.flags, ST.modinit);
    m.mnolev := -mno;
    m.vis := ST.export;
    m.scope := ST.GlbMod[mno];
    RETURN m;
  END ModuleSymbol;

BEGIN
  IF name = "SYSTEM" THEN
    ST.SYSimported := TRUE;
    module := ModuleSymbol(0);
    INCL(module.flags, ST.intrinsic);
    ST.ImportSYSTEM(module.scope);
    ST.Insert(alias, module);
    done := TRUE;
  ELSE (* Import a real symbol file. *)
    impContext.nofr := FirstRef;
    impContext.minr := nofTypeMax;
    impContext.nofm := 0;
    impContext.self := alias = SelfImportAlias;
    impContext.reffp := OPM.DefaultFP;
    OPM.OldSym(name, done);
    IF done THEN
      InMod(mno);
      ReadTag(impContext.nextTag);
      WHILE ~OPM.eofSF DO
        InSymbol(mno, sym);
        ReadTag(impContext.nextTag);
      END;

      module := ModuleSymbol(mno);
      (* Imported global module points to module symbol;
       *  symbol never entered in scope. *)
      ST.SetModuleSymbol(ST.GlbMod[mno], module);
      ST.Insert(alias, module);
      OPM.CloseOldSym;
    ELSE
      OPM.CloseOldSym;
      IF impContext.self THEN (* Attempting import of symbol file for
                               * 'first time compilation of module. *)
        OPM.optNewSF := TRUE;
        OPM.optExtSF := TRUE;
        SymPresent := FALSE;
      ELSE
        OPM.err(EL.CannotFindSymfile);
      END;
    END;
  END;
END Import;

(* Returns the number of characters in the name + 1 (for 0X). *)
PROCEDURE NameLength(name : ARRAY OF CHAR) : INTEGER;
  VAR
    i : INTEGER;
    ch : CHAR;
BEGIN
  i := 0;
  REPEAT
    ch := name[i];
    INC(i);
  UNTIL ch = 0X;
  ASSERT(i <= LEN(name));
  RETURN i;
END NameLength;

PROCEDURE OutName(name : ARRAY OF CHAR); (* length prefixed *)
  VAR i : INTEGER; ch : CHAR;
BEGIN
  i := NameLength(name);
  OPM.SymWInt(i - 1); (* 0X character not included in count *)
  i := 0;
  ch := name[0];
  WHILE ch # 0X DO
    OPM.SymWCh(ch);
    INC(i);
    ch := name[i];
  END;
END OutName;

PROCEDURE OutSymbolName(sym : ST.Symbol);
BEGIN OutName(sym.name^);
END OutSymbolName;

 PROCEDURE OutHiddenSymbolName(sym : ST.Symbol);
   VAR
     name : ST.SymbolName;
     i : INTEGER;
     ch : CHAR;
 BEGIN
   IF ST.invisible IN sym.flags THEN
     ASSERT(sym.name[0] = OPM.HDNamePrefix, 131);
     OutSymbolName(sym);
   ELSE
     i := NameLength(sym.name^);
     NEW(name, i + 1);          (* Need space for 'HDNamePrefix'. *)
     name[0] := OPM.HDNamePrefix;
     ASSERT(sym.name[i - 1] = 0X);
     REPEAT
       ch := sym.name[i - 1];
       name[i] := ch;
       DEC(i);
     UNTIL i = 0;
     OutName(name^);
   END;
 END OutHiddenSymbolName;

  PROCEDURE OutMod(mno : INTEGER);
  BEGIN
    IF expContext.locmno[mno] < 0 THEN (* new module *)
      OPM.SymWInt(sftMNAME); expContext.locmno[mno] := expContext.nofm;
      INC(expContext.nofm); OutSymbolName(ST.GlbMod[mno]);
    ELSE OPM.SymWInt(-expContext.locmno[mno]);
    END;
  END OutMod;

  PROCEDURE OutSignature(proc : ST.Procedure);
    VAR par : ST.Symbol;
  BEGIN OutType(proc.result);
    par := ST.FirstParm(proc);
    WHILE par # NIL DO
      IF par.kind = ST.par THEN OPM.SymWInt(sftVALPAR); ELSE OPM.SymWInt(sftVARPAR); END;
      OutSymbolTag(par); OutType(par.type); OPM.SymWInt(par.adr);
      OPM.SymWSet(par.flags * ST.symPersistentFlags); OutSymbolName(par);
      par := ST.NextParm(par);
    END;
    OPM.SymWInt(sftEND);
  END OutSignature;

  PROCEDURE OutHdFld(type : ST.Type; typesym : ST.Symbol; adr : LONGINT);
    VAR base : ST.Type; i, j, n : LONGINT;
  BEGIN
    IF type.form = ST.record THEN OutFlds(type(ST.Record), adr, FALSE);
    ELSIF type.form = ST.array THEN
      base := type(ST.Array).of; n := type(ST.Array).n;
      WHILE base.form = ST.array DO n := n * base(ST.Array).n; base := base(ST.Array).of; END;
      IF base.form IN {ST.pointer, ST.record} THEN
        j := nofhdfld; OutHdFld(base, typesym, adr);
        IF j # nofhdfld THEN
          i := 1;
          WHILE (i < n) & (nofhdfld <= OPM.MaxHdFld) DO
            INC(adr, base.size); OutHdFld(base, typesym, adr); INC(i);
          END;
        END;
      END;
    ELSIF type.form = ST.pointer THEN OPM.SymWInt(sftHDPTR); OutHiddenSymbolName(typesym); OPM.SymWInt(adr); INC(nofhdfld);
    ELSIF type.form = ST.procedure THEN OPM.SymWInt(sftHDPRO); OutHiddenSymbolName(typesym); OPM.SymWInt(adr); INC(nofhdfld);
    END;
  END OutHdFld;

  PROCEDURE OutFlds(rec : ST.Record; adr : LONGINT; visible : BOOLEAN);
    VAR fld : ST.Symbol;
  BEGIN
    fld := ST.FirstField(rec);
    WHILE fld # NIL DO
      IF (fld.vis IN {ST.export, ST.exportR}) & visible THEN
        IF fld.vis = ST.exportR THEN OPM.SymWInt(sftRFLD); ELSE OPM.SymWInt(sftFLD); END;
        OutSymbolTag(fld); OutType(fld.type); OPM.SymWSet(fld.flags * ST.symPersistentFlags);
        OutSymbolName(fld); OPM.SymWInt(fld.adr);
      ELSE OutHdFld(fld.type, fld, fld.adr + adr);
      END;
      fld := ST.NextField(fld);
    END;
  END OutFlds;

  PROCEDURE OutTProcs(VAR info : ST.ProcessScopeInfo);
    VAR field : ST.Symbol;
  BEGIN field := info.sym;
    IF field.kind = ST.tproc THEN
      IF (info(OutTProcInfo).owner.ancestor # NIL) & (field.vis = ST.internal) THEN (* overriding method *) OPM.err(EL.ExportOverride); END;
      IF field.vis IN {ST.export, ST.exportR} THEN (* hidden tprocs too *)
        IF field.vis IN {ST.export, ST.exportR} THEN
          OPM.SymWInt(sftTPRO); OutSignature(field.type(ST.Procedure));
          OPM.SymWSet(field.flags * ST.symPersistentFlags); OutSymbolName(field);
          OPM.SymWInt(field(ST.SymbolProc).methno);
        ELSE OPM.SymWInt(sftHDTPRO); OutHiddenSymbolName(field); OPM.SymWInt(field(ST.SymbolProc).methno);
        END;
      END;
    END;
  END OutTProcs;

  PROCEDURE OutTypeDescriptor(sym : ST.Symbol);
  BEGIN
    IF sym # NIL THEN OPM.SymWInt(sftTD);
      OutSymbolTag(sym); OPM.SymWInt(sym(ST.SymbolTypeDesc).tdnum);
      OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);
    ELSE OPM.SymWInt(sftNOTD);
    END;
  END OutTypeDescriptor;

  PROCEDURE OutType(type : ST.Type);
    VAR typesym : ST.Symbol; rec : ST.Record; tbpinfo : OutTProcInfo;
  BEGIN
    IF type.ref < expContext.ref THEN OPM.SymWInt(-type.ref);
    ELSE
      OPM.SymWInt(sftSTRUCT); type.ref := expContext.ref; INC(expContext.ref);
      IF expContext.ref > nofTypeMax THEN OPM.err(EL.TooManyExpStruct); expContext.ref := FirstRef;
      ELSE
        OutMod(type.mno); typesym := type.sym;
        OPM.SymWSet(type.flags * ST.typPersistentFlags);
        IF (typesym # NIL) & (typesym.name^ # "") THEN OutSymbolName(typesym);
          CASE typesym.history OF
          |  ST.pbmodified: FPrintErr(typesym, EL.FprintRedefinedPublic);
          |  ST.pvmodified: FPrintErr(typesym, EL.FprintRedefinedPrivate);
          |  ST.inconsistent: FPrintErr(typesym, EL.FprintInconsistent);
          ELSE (* else checked in ObjSym or correct indirect export *)
          END;
        ELSE OPM.SymWCh(0X); (* anonymous, never inconsistent; pvfp influences client fp *)
        END;
        OutTypeTag(type);
        IF type.sysflag # OPM.DefaultSysFlag THEN OPM.SymWInt(sftSYS); OPM.SymWInt(type.sysflag); END;
        CASE type.form OF
        |  ST.pointer: OPM.SymWInt(sftPTR); OutType(type(ST.Pointer).to);
        |  ST.procedure: OPM.SymWInt(sftPRO); OutSignature(type(ST.Procedure));
        |  ST.array, ST.dynarr:
          IF type.form = ST.array THEN OPM.SymWInt(sftARR); ELSE OPM.SymWInt(sftDARR); END;
          OutType(type(ST.Array).of); OPM.SymWInt(type(ST.Array).n);
          OPM.SymWInt(type(ST.Array).offset); OPM.SymWInt(type.size);
          OutTypeDescriptor(type(ST.Array).td);
        |  ST.record:
          rec := type(ST.Record);
          OPM.SymWInt(sftREC);
          IF rec.ancestor = NIL THEN OutType(ST.niltyp); ELSE OutType(rec.ancestor); END;
          OPM.SymWInt(rec.size); OPM.SymWInt(rec.align); OPM.SymWInt(rec.nofmeth);
          OutTypeDescriptor(type(ST.Record).td);
          nofhdfld := 0; OutFlds(rec, 0, TRUE);
          IF nofhdfld > OPM.MaxHdFld THEN OPM.err(EL.TooManyRecords); END;
          tbpinfo.owner := rec; ST.ProcessScope(rec.scope, OutTProcs, tbpinfo); OPM.SymWInt(sftEND);
        END;
      END;
    END;
  END OutType;

  PROCEDURE OutConstant(sym : ST.SymbolConst);
    VAR f : SHORTINT; rval : REAL;
  BEGIN
    f := sym.type.form; OPM.SymWInt(f);
    CASE f OF
    |  ST.bool, ST.byte, ST.char, ST.sint, ST.int, ST.lint: OPM.SymWInt(sym.val.i0);
    |  ST.real: rval := SHORT(sym.val.real); OPM.SymWReal(rval);
    |  ST.lreal: OPM.SymWLReal(sym.val.real);
    |  ST.set: OPM.SymWSet(sym.val.set);
    |  ST.string: OutName(sym.val.ext^);
    |  ST.nil: (* nothing *)
    ELSE OPM.err(EL.IllegalUse);
    END;
  END OutConstant;

  PROCEDURE OutSymbol(sym : ST.Symbol);
    VAR code : ST.ConstExt; i, j : INTEGER;
  BEGIN
    IF sym.history = ST.removed THEN FPrintErr(sym, EL.FprintDeleted);
    ELSIF (sym.vis IN {ST.export, ST.exportR}) & (sym.mnolev = 0) & ~(ST.intrinsic IN sym.flags) THEN
      (* compiler-owned symbols do not get exported; imported xprocs not reexported  *)
      CASE sym.history OF
      |  ST.inserted: FPrintErr(sym, EL.FprintNew);
      |  ST.same: (* ok *)
      |  ST.pbmodified: FPrintErr(sym, EL.FprintRedefinedPublic);
      |  ST.pvmodified: FPrintErr(sym, EL.FprintRedefinedPrivate);
      END;
      
      CASE sym.kind OF
      |  ST.var:
        IF sym.vis = ST.export THEN OPM.SymWInt(sftVAR); ELSE OPM.SymWInt(sftRVAR); END;
        OutSymbolTag(sym); OutType(sym.type); OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);
        IF (sym.type.sym = NIL) OR (sym.type.sym.name^ = "") THEN OPM.FPrint(expContext.reffp, sym.type.ref); (* avoid structural equiv *) END;
      |  ST.const:
        OPM.SymWInt(sftCONST);
        OutConstant(sym(ST.SymbolConst)); OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);
      |  ST.xproc:
        OPM.SymWInt(sftXPRO); OutSignature(sym.type(ST.Procedure));
        OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);
      |  ST.cproc:
        OPM.SymWInt(sftCPRO); OutSignature(sym.type(ST.Procedure)); code := sym(ST.SymbolCodeProc).code;
        j := ORD(code[0]); OPM.SymWInt(j); i := 1; WHILE i <= j DO OPM.SymWCh(code[i]); INC(i); END;
        OutSymbolName(sym);
      |  ST.iproc:
        OPM.SymWInt(sftIPRO); OutSignature(sym.type(ST.Procedure));
        OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);
      |  ST.type:
        IF sym.type.sym = sym THEN
          OPM.SymWInt(sftTYPE); OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutType(sym.type);
        ELSE
          OPM.SymWInt(sftALIAS); OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutType(sym.type); OutSymbolName(sym);
        END;
      |  ST.scope: OutSymbolName(sym); ASSERT(FALSE); (* exported scopes are not supported *)
      END;
    END;
  END OutSymbol;

  PROCEDURE OutScope(VAR info : ST.ProcessScopeInfo);
  BEGIN OutSymbol(info.sym);
  END OutScope;

  PROCEDURE Export*(self : ARRAY OF CHAR; VAR newsf, extsf : BOOLEAN);
    VAR i : INTEGER; nofmod : SHORTINT; done : BOOLEAN; selfName : OPS.Name; selfSym : ST.Symbol; info : ST.ProcessScopeInfo;
  BEGIN
    symExtended := FALSE; symNew := FALSE; nofmod := ST.nofGmod; COPY(SelfImportAlias, selfName);
    Import(selfName, self, done);
    selfSym := ST.Find(SelfImportAlias);
    (* export @self => fingerprint errors; set vis to internal so it it not exported in the object file or symbol file *)
    IF selfSym # NIL THEN selfSym.vis := ST.internal; END;

    ST.nofGmod := nofmod; OPM.NewSym(self);
    IF OPM.noerr THEN
      expContext.reffp := OPM.DefaultFP; expContext.ref := FirstRef;
      expContext.nofm := 1; expContext.locmno[0] := 0;
      i := 1; WHILE i <  LEN(expContext.locmno) DO expContext.locmno[i] := -1; INC(i); END;
      OPM.SymWInt(sftMNAME); OutName(self);
      ST.ProcessScope(ST.topScope, OutScope, info);
      extsf := SymPresent & symExtended; newsf := ~SymPresent OR symNew;
      IF OPM.noerr & SymPresent & (impContext.reffp # expContext.reffp) THEN newsf := TRUE;
        IF ~OPM.optExtSF THEN OPM.err(EL.CannotGenSym); END;
      END;
      OPM.optNewSF := FALSE; symNew := FALSE;
      IF OPM.noerr THEN OPM.RegisterNewSym; ELSE OPM.DiscardNewSym; END;
    END;
  END Export;

  PROCEDURE ModuleBegin*;
  BEGIN SymPresent := TRUE; NEW(impContext.ref); NEW(impContext.old);
    impContext.ref[ST.undef]    := ST.undftyp;
    impContext.ref[ST.bool]      := ST.booltyp;
    impContext.ref[ST.byte]      := ST.bytetyp;
    impContext.ref[ST.char]      := ST.chartyp;
    impContext.ref[ST.sint]      := ST.sinttyp;
    impContext.ref[ST.int]      := ST.inttyp;
    impContext.ref[ST.lint]      := ST.linttyp;
    impContext.ref[ST.real]      := ST.realtyp;
    impContext.ref[ST.lreal]    := ST.lrltyp;
    impContext.ref[ST.set]      := ST.settyp;
    impContext.ref[ST.string]    := ST.stringtyp;
    impContext.ref[ST.nil]      := ST.niltyp;
    impContext.ref[ST.void]      := ST.notyp;
    impContext.ref[ST.pointer]  := ST.sysptrtyp;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN impContext.ref := NIL; impContext.old := NIL;
  END ModuleEnd;

BEGIN
  ASSERT(ST.pbused IN ST.FPrintSet);
  ASSERT(ST.pvused IN ST.FPrintSet);
  ASSERT(ST.typfpdone IN ST.FPrintSet);
  ASSERT(ST.idfpdone IN ST.FPrintSet);
END SKLIE.

(* Symbol File Format: see documentation *)
      |  ST.darrdesc, ST.arrdesc, ST.recdesc:
        (* obsolete: TD writing handled by record output *)
        IF sym.kind = ST.darrdesc THEN i := sftDARRTD;
        ELSIF sym.kind = ST.arrdesc THEN i := sftARRTD;
        ELSE i := sftRECTD;
        END;
        OPM.SymWInt(i);
        OutType(sym(ST.SymbolTypeDesc).described); OutSymbolTag(sym); OPM.SymWInt(sym(ST.SymbolTypeDesc).tdnum);
        OPM.SymWSet(sym.flags * ST.symPersistentFlags); OutSymbolName(sym);

