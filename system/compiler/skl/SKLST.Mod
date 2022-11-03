MODULE SKLST; (* Symbol Table Hash Table *)
(* XXX document: SYSTEM is always given level 0.
 * If it is given another level, the GlbMod array needs to be modified so
 * range errors do not occur when things like fingerprinting access the
 * array based on the declaration level of the symbol.
 *)

IMPORT
  OPM:=SKLMD,
  OPS:=SKLOS,
  EL:=SKLERR;

  TYPE
    BEData* = POINTER TO BEDataDesc; (* back-end data record *)
    BEDataDesc* = RECORD END;

  CONST
    MaxImports* = 31;

  CONST
    IntrinsicLevel = 0; (* declaration level of standard identifiers *)
    UndefMnolev = MIN(SHORTINT); (* Used so that if the mnolev is
                                  * initialized outside this module, do not reset
                                  * it here when inserting. *)

  CONST (* type structure *)
    undef*     = 0; (* Indicates an error occurred during declaration; used for continuation. *)
    bool*      = 1;
    byte*      = 2;
    char*      = 3;
    sint*      = 4;
    int*       = 5;
    lint*      = 6;
    real*      = 7;
    lreal*     = 8;
    set*       = 9;
    string*    = 10;
    nil*       = 11;
    void*      = 12;
    pointer*   = 13;
    procedure* = 14;
    array*     = 15;
    openarr*   = 16;
    dynarr*    = 17;
    record*    = 18;
    nofTypes*  = 19;

    IntSet* = {sint..lint};
    RealSet* = {real, lreal};
    NumSet* = IntSet + RealSet;
    BasicSet* = {bool, byte, char, sint, int, lint, real,
                 lreal, set, nil, pointer, procedure}; (* Types that can fit into a register. *)
    ReturnSet* = BasicSet; (* allowed in a RETURN statement *)
    ArraySet* = {array, openarr, dynarr};
    AggregateSet* = {array, openarr, dynarr, record}; (* aggregate collections; things
                                                       * passed by-reference *)

  CONST
    FPrintSet* = {0..3}; (* flags reserved for fingerprinting *)

  CONST (* fingerprinting flags; used in Type & Symbol *)
    pbused* = 0;
    pvused* = 1;
    typfpdone* = 2;
    idfpdone* = 3;
    idfpresv0 = 4;
    idfpresv1 = 5; (* reserved fingerprint slots *)

  CONST
    (* type flags XXX document changes to type flags 97.01.01
      00..03 reserved for fingerprinting
      04..15 reserved for common Type use
      16..27 for Type specific use
      28..31 generic use (can be used outside of this module)
    *)
    typFingerprintFlags = {00..05};  (* flags which are reserved for the
                                      * fingerprinting mechanism (see
                                      * symFingerprintFlags) *)
    typCommonFlags = {06..17};       (* flags which are shared amongst all Type
                                      * extensions *)
    typSpecificFlags = {18..27};     (* each Type extension may use these
                                      * flags w/o conflicting with other
                                      * Types *)
    typGenericFlags = {28..31};      (* flags which can be used generically
                                      * outside this module *)
    typPersistentFlags* = (typCommonFlags +
                           typSpecificFlags +
                           typGenericFlags); (* flags which will be written to Sym *)

  CONST (* Symbol type flags *)
    allocated* = 4;
    method* = 5;

  TYPE
    Symbol* = POINTER TO SymbolDesc;
    SymbolScope* = POINTER TO SymbolScopeDesc;  (* scope, module *)
    SymbolTypeDesc* = POINTER TO SymbolTypeDescDesc;
    Type* = POINTER TO TypeDesc;
    TypeDesc* = RECORD
      form*, mno* : SHORTINT;
      flags* : SET;
      ref* : INTEGER;
      sysflag* : INTEGER;
      size*, pos*, idfp*, pbfp*, pvfp* : LONGINT;
      sym* : Symbol;
      bedata* : BEData;
    END;

  CONST
    typDynArrParm* = 16; (* dynamic array type a parameter, not heap-based; size calculated diferently *)

  TYPE
    Array* = POINTER TO ArrayDesc;
    ArrayDesc* = RECORD (TypeDesc)
      n* : LONGINT;  (* form = array => n = elems; form IN {openarr, dynarr} => n = dims (0 based) *)
      of* : Type;
      td* : SymbolTypeDesc; (* type descriptor (use GetTD to read) *)
      offset* : LONGINT;  (* form = array => 0;
                           * form = dynarr => offset of LEN() in descriptor;
                           * form = openarr = offset of LEN() on stack
                           *)
    END;

    ArrayInfoDesc* = RECORD
      form : SHORTINT;
      nofdim : LONGINT;
      eltype : Type;
    END;

    Pointer* = POINTER TO PointerDesc;
    PointerDesc* = RECORD (TypeDesc)
      to* : Type;
    END;

  CONST
    methodcounted* = 16;    (* methodcounted IN flags => methods are numbered
                             * for VMT slot assignment. *)

  TYPE
    Record* = POINTER TO RecordDesc;
    RecordDesc* = RECORD (TypeDesc)
      ancestor* : Record;
      scope* : SymbolScope;
      td* : SymbolTypeDesc;  (* type descriptor & vmt (use GetTD to read) *)
      nofmeth* : LONGINT; (* nofmeth < 0 -> methods have not been counted *)
      align* : LONGINT;
      extlev* : SHORTINT;
    END;

    Procedure* = POINTER TO ProcedureDesc;
    ProcedureDesc* = RECORD (TypeDesc)
      parms* : Symbol;
      result* : Type;
    END;

  TYPE (* constant *)
    ConstExt* = POINTER TO OPS.String;
    Const* = POINTER TO ConstValDesc;
    ConstValDesc* = RECORD
      type* : Type;
      ext* : ConstExt;
      i0* : LONGINT; (* character value, integer value; lo bound of range, string length (including 0X) *)
      i1* : LONGINT; (* hi bound of range; address for constant *)
      bool* : BOOLEAN; (* boolean constants *)
      set* : SET;
      real* : LONGREAL;
    END;

  CONST (**** symbol kinds ****)
    anon*       = 0;
    var*        = 1;
    par*        = 2;
    varpar*     = 3;
    const*      = 4;
    stdproc*    = 5;
    fwdproc*    = 6;
    lproc*      = 7;
    xproc*      = 8;
    cproc*      = 9;            (* code procedure *)
    iproc*      = 10;           (* interrupt procedure *)
    tproc*      = 11;
    field*      = 12;
    type*       = 13;
    module*     = 14; (* can only be a SymbolScope *)
    scope*      = 15;
    darrdesc*   = 16;
    arrdesc*    = 17; (* array descriptor for 'pointer to static array' only *)
    recdesc*    = 18;
    nofSymbols* = 19;

  CONST (* symbol visibility *)
    hidden* = 0; (* compiler generated symbols; exported explicitly *)
    internal* = 1; export* = 2; exportR* = 3;

  CONST (* fingerprint history *)
    inserted* = 1; same* = 2; pbmodified* = 3; pvmodified* = 4; removed* = 5; inconsistent* = 6;

  (* symbol flags  XXX document change in the flag ranges
      [00..03] reserved for fingerprinting
      [04..15] <=> basic symbol usage
      [16..27] <=> specific symbol usage
  *)
  CONST
    symCommonFlags*   = {04..15};
    symSpecificFlags* = {16..27};
    symGenericFlags*  = {28..31}; (* can be used by other units freely *)

  CONST (* common flags *)
    leaf* = 6; (* internal visibility, address not taken *)
    used* = 7; (* indicates a symbol has been looked up in the symbol table *)
    invisible* = 8; (* symbol is imported but not visible to the importing unit (hidden pointers, procedures & methods) *)

  CONST
    (* leaf & used status are not persistent *)
    symPersistentFlags* = (symCommonFlags - {leaf, used, invisible}) +
                          symSpecificFlags +
                          symGenericFlags; (* flags which will be written to Sym *)

  TYPE
    SymbolName* = POINTER TO ARRAY OF CHAR;

    SymtabEntryDesc = RECORD
      (* owner: The scope owning a Symbol.  The owner is not necessarily
       *        a scope.  It can be a record, or a procedure, for example.
       *)
      owner : Symbol;
      link : Symbol;    (* Links symbols in scope together in a list. *)
      hash : Symbol;    (* Links symbols together in the hash table. *)
    END;

    SymbolDesc* = RECORD (SymtabEntryDesc)
      kind* : SHORTINT;
      mnolev* : SHORTINT;      (* inv: mnolev <= 0 => module number = -mnolev;
                                * inv: mnolev > 0 => nesting level
                                *)
      vis*, history* : SHORTINT;
      flags* : SET;
      type* : Type;
      ref*  : INTEGER;
      adr*, fprint* : LONGINT;
      name- : SymbolName;

      (* XXX document:
       * During ObjFile Uses block writing, the adr field is set to
       * the index of the Using record for the symbol.
       * This is so external fixups can get their external address,
       * since it isn't stored in the symbol file *)
    END;

    SymbolConst* = POINTER TO SymbolConstDesc;
    SymbolConstDesc* = RECORD (SymbolDesc)
      val* : Const;
    END;

  CONST (* SymbolScope array sizes *)
    ScopeLenRecord = 8;
    ScopeLenProcedure = 8;
    ScopeLenModule = 16;

  TYPE
    HashTable = POINTER TO ARRAY OF Symbol;

    (* SymbolScopeDesc: a symbol table scope

      A scope must maintain the declaration order of symbols.
      A scope must reference its owner.
      A scope must reference its enclosing scope.

      inv: (link # NIL) & (link(SymbolScope) <-> enclosing scope)
      inv: (hash = NIL) OR (hash <-> owner of the scope) (owner = procedure, for example)
      inv: (first = NIL) OR defined(first^) & (first <-> first variable declared in scope)
      inv: (last = NIL) OR defined(last^) & (last <-> most recent variable declared in scope)
    *)
    SymbolScopeDesc* = RECORD (SymbolDesc)
      table : HashTable;
      first, last : Symbol;
      dsize* : LONGINT;      (* data size for this scope *)
    END;

    ModuleScope* = POINTER TO ModuleScopeDesc;
    ModuleScopeDesc* = RECORD (SymbolScopeDesc)
      module : Symbol;  (* symbol which represents the initialization code *)
    END;

  CONST (* SymbolTypeDesc flags *)
    tdinit* = 16; (* type descriptor already appears on the init-td list *)

  TYPE
    SymbolTypeDescDesc* = RECORD (SymbolDesc)
      tdnum* : INTEGER;  (* TD number *)
      described* : Type;
    END;

    RecordTD* = POINTER TO RecordTDDesc;
    RecordTDDesc* = RECORD (SymbolTypeDescDesc)
    END;

    ArrayTD* = POINTER TO ArrayTDDesc;
    ArrayTDDesc* = RECORD (SymbolTypeDescDesc)
    END;

  CONST (* procedure flags *)
    body*    = 16;
    redef*   = 17;
    modinit* = 18; (* XXX document; indicates a procedure symbol is actually module init code *)
    (* XXX document intrinsic flag:
      affects symbol export qualities.  A symbol with this flag set is owned by the compiler and not a true symbol in the
      sense of code generation and address assignment.  A symbol w/ this flag should not be written to the symbol
      file or the export block of the object file
    *)
    intrinsic* = 19; (* compiler-owned symbol;
                      * has no real address (eg: SYSTEM init code)
                      * should not be exported *)

  TYPE
    SymbolProc* = POINTER TO SymbolProcDesc;
    SymbolProcDesc* = RECORD (SymbolDesc)
      parsize*, varsize* : LONGINT;
      methno* : LONGINT;
      scope* : SymbolScope;
    END;

  CONST (* standard proc types *)
    SPbegin*    = 0;
    absfn*      = 0;
    capfn*      = 1;
    oddfn*      = 2;
    adrfn*      = 3;
    ashfn*      = 4;
    lshfn*      = 5;
    rotfn*      = 6;
    lenfn*      = 7;
    bitfn*      = 8;
    newfn*      = 9;
    getfn*      = 10;
    putfn*      = 11;
    getrfn*     = 12;
    putrfn*     = 13;
    valfn*      = 14;
    sysnewfn*   = 15;
    movefn*     = 16;
    haltfn*     = 17;
    assertfn*   = 18;
    ordfn*      = 19;
    entierfn*   = 20;
    minfn*      = 21;
    maxfn*      = 22;
    chrfn*      = 23;
    shortfn*    = 24;
    longfn*     = 25;
    sizefn*     = 26;
    incfn*      = 27;
    decfn*      = 28;
    inclfn*     = 29;
    exclfn*     = 30;
    copyfn*     = 31;
    memrfn*     = 32;
    memwfn*     = 33;
    finalizefn* = 34; (* 97.07.05: not documented yet XXX *)
    bitrfn*     = 35; (* Reset Bit. 97.07.05: not documented yet
                       * XXX: operates on DWORD only *)
    bitsfn*     = 36; (* Set Bit.  97.07.05: not documented yet
                       * XXX: operates on DWORD only *)
    SPlast*     = 37;

  TYPE
    SymbolStdProc* = POINTER TO SymbolStdProcDesc;
    SymbolStdProcDesc* = RECORD (SymbolDesc)
      procno* : SHORTINT; (* standard procedure number *)
    END;

  CONST (* code procedure information *)
    MaxCodeProcLen* = OPS.MaxStrLen;

  TYPE
    SymbolCodeProc* = POINTER TO SymbolCodeProcDesc;
    SymbolCodeProcDesc* = RECORD (SymbolProcDesc)
      code* : ConstExt;
    END;

  TYPE (* ProcessScopeInfo; used for passing extra information during scope traversal *)
    ProcessScopeInfo* = RECORD
      sym- : Symbol;
    END;
    ProcessScopeProc* = PROCEDURE (VAR info : ProcessScopeInfo);

  VAR
    GlbMod* : ARRAY MaxImports OF ModuleScope;
    SelfName* : OPS.Name;
    topScope* : SymbolScope;
    SYSimported* : BOOLEAN;
    nofGmod* : SHORTINT;

  VAR (* types *)
    undftyp- : Type;
    bytetyp- : Type;
    booltyp- : Type;
    chartyp- : Type;
    sinttyp- : Type;
    inttyp- : Type;
    linttyp- : Type;
    realtyp- : Type;
    lrltyp- : Type;
    settyp- : Type;
    stringtyp- : Type;
    niltyp- : Type;
    notyp- : Type;
    sysptrtyp- : Type;
    proctyp-: Type;

  VAR
    nofTD : INTEGER;
    sysScope : SymbolScope;
    universe : SymbolScope;
    NullString : SymbolName;
    nofGenString, nofGenTD, nofGenVar : INTEGER;

  PROCEDURE ^ Insert*(name : ARRAY OF CHAR; sym : Symbol);
  PROCEDURE ^ InsertScope*(scope : SymbolScope; name : ARRAY OF CHAR; sym : Symbol);
  PROCEDURE ^ FindInOpenScopes*(scope : SymbolScope; name : ARRAY OF CHAR) : Symbol;
  PROCEDURE ^ FindInThisScope*(scope : SymbolScope; name : ARRAY OF CHAR) : Symbol;

  PROCEDURE Hash*(name : ARRAY OF CHAR) : LONGINT;
  BEGIN
    RETURN OPM.Hash(name);
  END Hash;

  PROCEDURE ReverseSymbolList*(VAR head : Symbol);
    VAR
      p, l, h : Symbol;
  BEGIN
    IF head # NIL THEN
      h := head;
      p := h;
      l := h.link;
      p.link := NIL;

      WHILE l # NIL DO
        h := l;
        l := l.link;
        h.link := p;
        p := h;
      END;
      head := h;
    END;
  END ReverseSymbolList;

  (* if stdcall allowed on methods, make sure 'self' is passed corretly *)
  (*
   * 97.09.17: Parameters and local variables being stored on the same
   * list makes the implementation of SYSTEM.STDCALL a bit more challenging.
   * Simply reversing the list has the affect of the procedure seeming
   * to have no parameters. Until the symbol table is redesigned to have two
   * lists (parameters & locals) for procedure types, the compiler is stuck
   * with this special reversal routine.
   *)
  PROCEDURE ReverseParmList*(proc: Procedure);
    VAR
      f, c, p, q : Symbol;
  BEGIN
    f := NIL;
    p := NIL;
    c := proc.parms;
    WHILE (c # NIL) & (c.kind IN {par, varpar}) DO
      IF f = NIL THEN
        f := c;
      END;
      q := c.link;
      c.link := p;
      p := c;
      c := q;
    END;
    f.link := c;
    proc.parms := p;
  END ReverseParmList;

  PROCEDURE MakeGeneratedName(described : Symbol;
                              prefix : ARRAY OF CHAR;
                              VAR nofGenNames : INTEGER) : SymbolName;
    VAR
      name, symName : SymbolName;
      i : LONGINT;
      j : LONGINT;
      len : LONGINT;
      ch : CHAR;
      number : OPS.Name;

    (* pre: undefined(dest) *)
    (* pre: undefined(l) *)
    (* post: ASCIIZ(dest) *)
    (* post: (El: 0 <= i < LEN(dest): dest[i] = 0X & (l <- i + LEN(prefix) - )) *)
    PROCEDURE NextNumber(VAR dest : OPS.Name; VAR l : LONGINT);
      VAR
        temp : OPS.Name;
        len, i, j, val : INTEGER;
        ch : CHAR;
    BEGIN
      val := nofGenNames;
      INC(nofGenNames);
      i := 0;
      REPEAT
        ch := CHR(val MOD 10 + ORD('0'));
        val := val DIV 10;
        temp[i] := ch;
        INC(i);
      UNTIL (val <= 0) OR (i >= LEN(temp) - 1);

      dest[i] := 0X;
      len := i;
      j := 0;
      REPEAT
        DEC(i);
        dest[j] := temp[i];
        INC(j);
      UNTIL i = 0;
      l := len + LEN(prefix);
    END NextNumber;

  BEGIN
    IF described = NIL THEN
      NextNumber(number, len);
      NEW(name, 1 (* '.' *) + LEN(prefix) (* includes 0X *) + len);
      name[0] := '.';
      i := -1;
      REPEAT
        INC(i);
        ch := prefix[i];
        name[1 + i] := ch;
      UNTIL ch = 0X;

      j := 0;
      REPEAT
        ch := number[j];
        name[i + 1] := ch;
        INC(i);
        INC(j);
      UNTIL ch = 0X;
    ELSE
      len := LEN(described.name^);
      NEW(name, 1 (* '.' *) + LEN(prefix) (* includes 0X *) + len);
      name[0] := '.';
      symName := described.name;
      i := 0;
      REPEAT
        ch := symName[i];
        name[1 + i] := ch;
        INC(i);
      UNTIL ch = 0X;
    END;
    RETURN name;
  END MakeGeneratedName;

  PROCEDURE IntTypeOf*(v : LONGINT) : Type;
    VAR
      t : Type;
  BEGIN
    IF (v >= OPM.MinSInt) & (v <= OPM.MaxSInt) THEN
      t := sinttyp;
    ELSIF (v >= OPM.MinInt) & (v <= OPM.MaxInt) THEN
      t := inttyp;
    ELSIF (v >= OPM.MinLInt) & (v <= OPM.MaxLInt) (*bootstrap/cross*) THEN
      t := linttyp;
    ELSE
      OPM.err(EL.NumberTooLarge);
      t := linttyp; (* only possible on bootstrapping compilers *)
    END;
    RETURN t;
  END IntTypeOf;

  PROCEDURE InitBasicType(t : Type; f : SHORTINT);
  BEGIN
    t.form := f;
    t.mno := 0;
    t.flags := {};
    t.ref := OPM.nofTypeMax;
    t.sysflag := OPM.DefaultSysFlag;
    t.size := OPM.UndefSize;
    t.pos := 0;
    t.idfp := OPM.DefaultFP;
    t.pvfp := OPM.DefaultFP;
    t.pbfp := OPM.DefaultFP;
    t.sym := NIL;
  END InitBasicType;

  PROCEDURE InitBasicSymbol(s : Symbol; k : SHORTINT);
    VAR
      i : INTEGER;
  BEGIN
    s.kind := k;
    s.mnolev := UndefMnolev;
    s.vis := internal;
    s.history := inserted;
    s.flags := {};
    s.type := undftyp;
    s.ref := 0;
    s.adr := OPM.UndefAdr;
    s.fprint := OPM.DefaultFP;
    s.link := NIL;
    s.hash := NIL;
    s.name := NIL;
  END InitBasicSymbol;

  (*** Type Constructors ***)

  PROCEDURE NewBasicType*() : Type;
    VAR
      t : Type;
  BEGIN
    NEW(t);
    InitBasicType(t, undef);
    RETURN t;
  END NewBasicType;

  PROCEDURE NewArrayType*(f : SHORTINT) : Array;
    VAR
      t : Array;
  BEGIN
    NEW(t);
    InitBasicType(t, f);
    t.n := 0;
    t.of := undftyp;
    t.td := NIL;
    t.offset := 0;
    RETURN t;
  END NewArrayType;

  PROCEDURE NewPointerType*() : Pointer;
    VAR
      t : Pointer;
  BEGIN
    NEW(t);
    InitBasicType(t, pointer);
    t.to := undftyp;
    RETURN t;
  END NewPointerType;

  PROCEDURE NewRecordType*() : Record;
    VAR
      t : Record;
  BEGIN
    NEW(t);
    InitBasicType(t, record);
    t.ancestor := NIL;
    t.scope := NIL;
    t.td := NIL;
    t.nofmeth := -1; (* methods not counted yet *)
    t.align := 0;
    t.extlev := 0;
    RETURN t;
  END NewRecordType;

  PROCEDURE NewProcedureType*() : Procedure;
    VAR
      t : Procedure;
  BEGIN
    NEW(t);
    InitBasicType(t, procedure);
    t.size := OPM.ProcSize;
    t.parms := NIL;
    t.result := notyp;
    RETURN t;
  END NewProcedureType;

  (*** Symbol Constructors ***)

  PROCEDURE NewConstExt*() : ConstExt;
    VAR
      x : ConstExt;
  BEGIN
    NEW(x);
    RETURN x;
  END NewConstExt;

  PROCEDURE SetSymbolName*(sym : Symbol; name : ARRAY OF CHAR);
    VAR
      l : LONGINT;
      ch : CHAR;
  BEGIN
    IF name[0] = 0X THEN
      sym.name := NullString;
    ELSE
      ASSERT(sym.name = NIL); (* can only set unset names *)
      l := LEN(name);
      (* inv: i includes 0X terminator *)
      NEW(sym.name, l);
      COPY(name, sym.name^);
    END;
  END SetSymbolName;

  PROCEDURE NewConst*(type : Type) : Const;
    VAR
      x : Const;
  BEGIN
    NEW(x);
    x.type := type;
    x.ext := NIL;
    x.i0 := 0;
    x.i1 := 0;
    x.set := {};
    x.real := 0.0;
    RETURN x;
  END NewConst;

  PROCEDURE NewBasicSym*(kind : SHORTINT) : Symbol;
    VAR
      s : Symbol;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, kind);
    RETURN s;
  END NewBasicSym;

  PROCEDURE NewConstSym*(t : Type) : SymbolConst;
    VAR
      s : SymbolConst;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, const);
    s.val := NewConst(t);
    s.type := t;
    RETURN s;
  END NewConstSym;

  PROCEDURE InitScopeSym(s : SymbolScope; len : LONGINT);
  BEGIN
    InitBasicSymbol(s, scope);
    OPM.GetCurrentSourcePos(s.adr);
    NEW(s.table, len);
    s.first := NIL;
    s.last := NIL;
    s.dsize := OPM.UndefSize;
    WHILE len > 0 DO
      DEC(len);
      s.table[len] := NIL;
    END;
  END InitScopeSym;

  PROCEDURE NewModuleScopeSym*() : ModuleScope;
    VAR
      s : ModuleScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, ScopeLenModule);
    RETURN s;
  END NewModuleScopeSym;

  PROCEDURE NewRecordScopeSym*() : SymbolScope;
    VAR
      s : SymbolScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, ScopeLenRecord);
    RETURN s;
  END NewRecordScopeSym;

  PROCEDURE NewProcedureScopeSym*() : SymbolScope;
    VAR
      s : SymbolScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, ScopeLenProcedure);
    RETURN s;
  END NewProcedureScopeSym;

  PROCEDURE NewTempVar*(type : Type) : Symbol;
    VAR
      s : Symbol;
      name : SymbolName;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, var);
    s.type := type;
    name := MakeGeneratedName(NIL, 'var_', nofGenVar);
    Insert(name^, s);
    RETURN s;
  END NewTempVar;

  PROCEDURE InitTD(kind : SHORTINT; td : SymbolTypeDesc; described : Type);
    VAR
      symname : OPS.Name;
  BEGIN
    InitBasicSymbol(td, kind);
    td.type := linttyp;
    td.described := described;
    td.vis := hidden;
    td.tdnum := nofTD;
    INC(nofTD);
  END InitTD;

  PROCEDURE NewRecordTD*(desc : Type) : RecordTD;
    VAR
      s : RecordTD;
  BEGIN
    NEW(s);
    InitTD(recdesc, s, desc);
    RETURN s;
  END NewRecordTD;

  PROCEDURE NewDynArrayTD*(desc : Type) : ArrayTD;
    VAR
      s : ArrayTD;
  BEGIN
    NEW(s);
    InitTD(darrdesc, s, desc);
    RETURN s;
  END NewDynArrayTD;

  PROCEDURE NewArrayTD*(desc : Type) : ArrayTD;
    VAR
      s : ArrayTD;
  BEGIN
    NEW(s);
    InitTD(arrdesc, s, desc);
    RETURN s;
  END NewArrayTD;

  PROCEDURE SetTD*(type : Type; td : SymbolTypeDesc);
    VAR
      tf : SHORTINT;
  BEGIN
    tf := type.form;
    IF tf = record THEN
      type(Record).td := td;
    ELSE (* tf IN {array, dynarr} *)
      type(Array).td := td;
    END;
  END SetTD;

  (* post: result = TRUE => type has a TD; FALSE => no TD associated *)
  PROCEDURE HasTD*(type : Type) : BOOLEAN;
  BEGIN
    (* named global exported static arrays are given type descriptors
     * because an importing module can declare a pointer to that array
     * type -- at which point a TD is required.  It's best to err on
     * the side of not needing a TD and creating one rather than needing
     * one and creating it in many different modules.
     *)
    RETURN ((type.form = record) OR
            (type.form = pointer) &
            (type(Pointer).to.form IN {record, dynarr, array}) OR
            (type.form = array) &
            (type.mno = 0) &
            (type.sym # NIL) &
            (type.sym.vis # internal) &
            (type.sym.mnolev = 0));
  END HasTD;

  (* returns: NIL => no TD associated with type;
   * ~NIL => type descriptor symbol
   * Works with records, pointer to records & pointer to dynarr.
  *)
  PROCEDURE GetTD*(type : Type) : SymbolTypeDesc;
    VAR
      tf : SHORTINT;
      to : Type;
      td : SymbolTypeDesc;

    PROCEDURE GlobalScope() : SymbolScope;
      VAR
        scope : SymbolScope;
    BEGIN
      scope := topScope;
      WHILE scope.link # universe DO
        scope := scope.link(SymbolScope);
      END;
      RETURN scope;
    END GlobalScope;

    PROCEDURE NewTypeDesc(describedType : Type) : SymbolTypeDesc;
      VAR
        f : SHORTINT;
        elemtd, td : SymbolTypeDesc;
        element : Type;
        descName : SymbolName;
    BEGIN
      ASSERT(describedType # NIL, 250);
      IF describedType.form = pointer THEN
        describedType := describedType(Pointer).to;
      END;
      ASSERT(describedType.form IN {record, dynarr, array}, 251);

      CASE describedType.form OF
      | record:
        td := NewRecordTD(describedType);
        describedType(Record).td := td;

      | array, dynarr:
        IF describedType.form = array THEN
          td := NewArrayTD(describedType);
        ELSE
          td := NewDynArrayTD(describedType);
        END;

        describedType(Array).td := td;
        element := describedType;

        WHILE element.form IN {array, dynarr} DO
          element := element(Array).of;
        END;
        IF HasTD(element) THEN (* element type also needs a type descriptor *)
          elemtd := GetTD(element);
        END;
      END;
      td.described := describedType;
      descName := MakeGeneratedName(describedType.sym, 'td_', nofGenTD);
      InsertScope(GlobalScope(), descName^, td);
      RETURN td;
    END NewTypeDesc;

  BEGIN
    IF HasTD(type) THEN
      CASE type.form OF
      | record:
        td := type(Record).td;

      | array:
        td := type(Array).td;

      | pointer:
        to := type(Pointer).to;
        tf := to.form;
        CASE tf OF
        | record:
          td := to(Record).td;

        | array, dynarr:
          td := to(Array).td;
        END;
        IF td = NIL THEN
          ASSERT(type.mno = 0, 141);
          td := NewTypeDesc(to);
        END;
      END;

      IF td = NIL THEN
        ASSERT(type.form IN {record, array}, 1042);
        ASSERT(type.mno = 0, 1043);
        td := NewTypeDesc(type);
      END;

      (* inv: td # NIL *)
      INCL(td.flags, used); (* Getting a type descriptor implicitly uses it;
                             * even if it is just created. *)
      RETURN td;
    ELSE
      RETURN NIL;
    END;
  END GetTD;

  PROCEDURE UseTD*(type : Type); (* 98.02.25: obsolete since 'GetTD' now
                                  * will implicitly use the returned TD *)
    VAR
      td : SymbolTypeDesc;
  BEGIN
    td := GetTD(type);
    INCL(td.flags, used);
  END UseTD;

  PROCEDURE NewStdProcSym(form : SHORTINT; result : Type) : SymbolStdProc;
    VAR
      s : SymbolStdProc;
    type : Procedure;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, stdproc);
    s.procno := form;
    type := NewProcedureType();
    type.result := result;
    s.type := type;
    RETURN s;
  END NewStdProcSym;

  PROCEDURE InitProcedureSym(s : SymbolProc; k : SHORTINT);
  BEGIN
    InitBasicSymbol(s, k);
    s.parsize := OPM.UndefSize;
    s.type := NewProcedureType();
    s.varsize := OPM.UndefSize;
    s.methno := OPM.UndefTDAdr;
    s.scope := NIL;
  END InitProcedureSym;

  PROCEDURE NewProcedureSym*() : SymbolProc;
    VAR
      s : SymbolProc;
  BEGIN
    NEW(s);
    InitProcedureSym(s, lproc);
    RETURN s;
  END NewProcedureSym;

  PROCEDURE NewCodeProcSym*() : SymbolCodeProc;
    VAR
      s : SymbolCodeProc;
  BEGIN
    NEW(s);
    InitProcedureSym(s, cproc);
    s.code := NewConstExt();
    RETURN s;
  END NewCodeProcSym;

  PROCEDURE NewTypeBoundProcSym*() : SymbolProc;
    VAR
      s : SymbolProc;
  BEGIN
    NEW(s);
    InitProcedureSym(s, tproc);
    RETURN s;
  END NewTypeBoundProcSym;

  (*** Initialization Helpers ***)
  PROCEDURE EnterTyp(name : OPS.Name;
                     form : SHORTINT;
                     size : INTEGER;
                     VAR res : Type);
    VAR
      sym : Symbol;
      typ : Type;
  BEGIN
    sym := NewBasicSym(type);
    Insert(name, sym);
    sym.vis := exportR;
    typ := NewBasicType();
    typ.form := form;
    typ.ref := form;
    typ.size := size;
    typ.mno := IntrinsicLevel;
    sym.type := typ;
    typ.sym := sym;
    res := typ;
    sym.mnolev := IntrinsicLevel;
    typ.flags := {allocated, idfpdone, typfpdone};
  END EnterTyp;

  PROCEDURE EnterPtrTyp(name : OPS.Name;
                        form : SHORTINT;
                        size : INTEGER;
                        VAR res : Type);
    VAR
      sym : Symbol;
      typ : Pointer;
  BEGIN
    sym := NewBasicSym(type);
    Insert(name, sym);
    sym.vis := exportR;
    typ := NewPointerType();
    typ.form := form;
    typ.ref := form;
    typ.to := notyp;
    typ.size := size;
    typ.mno := IntrinsicLevel;
    sym.type := typ;
    typ.sym := sym;
    res := typ;
    sym.mnolev := IntrinsicLevel;
    INCL(typ.flags, idfpdone);
    INCL(typ.flags, typfpdone);
  END EnterPtrTyp;

  PROCEDURE EnterProc(name : OPS.Name; procno: SHORTINT; result : Type);
    VAR
      sym : Symbol;
  BEGIN
    sym := NewStdProcSym(procno, result);
    sym.mnolev := IntrinsicLevel;
    Insert(name, sym);
    sym.vis := export;
  END EnterProc;

  PROCEDURE EnterIntConst(name : OPS.Name; val : SHORTINT) : Symbol;
    VAR
      sym : SymbolConst;
  BEGIN
    sym := NewConstSym(IntTypeOf(val));
    Insert(name, sym);
    sym.mnolev := IntrinsicLevel;
    sym.val.i0 := val;
    sym.vis := export;
    RETURN sym;
  END EnterIntConst;

  PROCEDURE EnterBoolConst(name : OPS.Name; val : SHORTINT);
    VAR
      sym : SymbolConst;
  BEGIN
    sym := NewConstSym(booltyp);
    Insert(name, sym);
    sym.mnolev := IntrinsicLevel;
    sym.val.i0 := val;
  END EnterBoolConst;

  PROCEDURE InsertHash(scope : SymbolScope; sym : Symbol);
    VAR
      hash, len : LONGINT;
      curr, prev : Symbol;
  BEGIN
    len := LEN(scope.table^);
    hash := Hash(sym.name^) MOD len;

    (* Insert in alphabetical order.
     *
     * The symbols are kept in alphabetical order so that scope
     * traversal has a deterministic order of symbols.  This is
     * important because fingerprint is order-dependent; traversing
     * the set of symbols in a scope in a different order will most
     * likely yeild a different fingerprint, resulting in error
     * FprintRedefinedPublic (125), or FprintRedefinedPrivate (126).
     *
     * By ensuring that the scope is in alphabetical order
     * ProcessScope() will always produce the same result when
     * fingerprinting the self-import module when writing the symbol
     * file.
     *)
    prev := NIL;
    curr := scope.table[hash];
    WHILE (curr # NIL) & (sym.name^ > curr.name^) DO
      prev := curr;
      curr := curr.hash;
    END;

    IF prev = NIL THEN          (* Insert at beginning of list. *)
      sym.hash  := scope.table[hash];
      scope.table[hash] := sym;
    ELSE                        (* Insert into list. *)
      sym.hash  := curr;
      prev.hash := sym;
    END;

    (* Link variables in the scope in declaration order. *)
    IF scope.first = NIL THEN
      scope.first := sym;
      scope.last := sym;
    ELSE
      scope.last.link := sym;
      scope.last := sym;
    END;
    sym.owner := scope;
  END InsertHash;

  PROCEDURE InsertScope*(scope : SymbolScope;
                         name : ARRAY OF CHAR;
                         sym : Symbol);
  BEGIN
    IF FindInThisScope(scope, name) = NIL THEN
      INCL(sym.flags, leaf);
      SetSymbolName(sym, name);
      IF sym.mnolev = UndefMnolev THEN
        sym.mnolev := scope.mnolev;
      END;
      InsertHash(scope, sym);
    ELSE
      OPM.err(EL.MultipleDefinition);
    END;
  END InsertScope;

  (* InsertImport: attempts to insert 'sym' into 'scope'
   * If 'sym' is not found in scope, it is inserted.
   * If 'sym' already exists in 'scope' then it is not inserted
   * and the original symbol is returned in 'old'.
   *
   * Symbols inserted in this fashion are kept in declaration order.
   * This should not be a problem because they are all dealing with
   * imported symbols and as such are not important to the current
   * compilation.
   *)
  PROCEDURE InsertImport*(scope : SymbolScope;
                          sym : Symbol;
                          VAR old : Symbol);
    VAR
      hash, len : LONGINT;
  BEGIN
    old := FindInThisScope(scope, sym.name^);
    IF old = NIL THEN
      InsertHash(scope, sym);
    END;
  END InsertImport;

  PROCEDURE Insert*(name : ARRAY OF CHAR; sym : Symbol);
  BEGIN
    InsertScope(topScope, name, sym);
  END Insert;

  PROCEDURE OpenScope(s : SymbolScope; level: SHORTINT; owner: Symbol);
  BEGIN
    s.mnolev := level;
    s.link := topScope;
    topScope := s;
    s.hash := owner;
    IF (owner # NIL) & (owner.kind IN {fwdproc..tproc}) THEN
      owner(SymbolProc).scope := s;
    END;
  END OpenScope;

  PROCEDURE OpenRecordScope*;
    VAR
      s : SymbolScope;
  BEGIN
    s := NewRecordScopeSym();
    OpenScope(s, 0, NIL);
  END OpenRecordScope;

  PROCEDURE OpenProcedureScope*(level : SHORTINT; owner : SymbolProc);
    VAR
      s : SymbolScope;
  BEGIN
    s := NewProcedureScopeSym();
    OpenScope(s, level, owner);
  END OpenProcedureScope;

  PROCEDURE OpenModuleScope*(level : SHORTINT; owner : Symbol);
    VAR
      s : ModuleScope;
  BEGIN
    s := NewModuleScopeSym();
    OpenScope(s, level, owner);
  END OpenModuleScope;

  PROCEDURE HashStats(s : SymbolScope);
    VAR
      len, i, empty, symbols : LONGINT;
      sym : Symbol;
  BEGIN
    len := LEN(s.table^);
    empty := 0;
    symbols := 0;
    i := 0;
    WHILE i < len DO
      sym := s.table[i];
      IF sym # NIL THEN
        WHILE sym # NIL DO
          INC(symbols);
          sym := sym.hash;
        END;
      ELSE INC(empty);
      END;
      INC(i);
    END;
    OPM.LogWStr('hash len=');
    OPM.LogWHex(len);
    OPM.LogWStr(' empty slots=');
    OPM.LogWHex(empty);
    OPM.LogWStr(' symbols=');
    OPM.LogWHex(symbols);
    IF (s.hash # NIL) & (s.hash.name # NIL) THEN
      OPM.LogWStr(' owner=');
      OPM.LogWStr(s.hash.name^);
    END;
    OPM.LogWLn;
  END HashStats;

  PROCEDURE CloseScope*() : SymbolScope;
    VAR
      s : SymbolScope;
  BEGIN
    s := topScope;
    IF topScope.link = NIL THEN
      topScope := NIL;
    ELSE
      topScope := topScope.link(SymbolScope);
    END;
    IF OPM.OptHashStats IN OPM.options THEN
      HashStats(s);
    END;
    RETURN s;
  END CloseScope;

  PROCEDURE ReopenScope*(scope : SymbolScope; owner : Symbol);
  BEGIN
    scope.link := topScope;
    scope.hash := owner;
    topScope := scope;
  END ReopenScope;

  PROCEDURE ScopeOwner*(scope : SymbolScope) : Symbol;
  BEGIN
    IF scope # NIL THEN
      RETURN scope.hash;
    ELSE
      RETURN NIL;
    END;
  END ScopeOwner;

  PROCEDURE PreviousScope*(scope : SymbolScope) : SymbolScope;
  BEGIN
    IF (scope # NIL) & (scope.link # NIL) THEN
      RETURN scope.link(SymbolScope);
    ELSE
      RETURN NIL;
    END;
  END PreviousScope;

  (** List Handling *)

  PROCEDURE FirstScopeVar*(scope : SymbolScope) : Symbol;
  BEGIN
    IF scope # NIL THEN
      RETURN scope.first;
    ELSE
      RETURN NIL;
    END;
  END FirstScopeVar;

  PROCEDURE FirstParm*(proctype : Procedure) : Symbol;
    VAR
      parm : Symbol;
  BEGIN
    parm := proctype.parms;
    ASSERT((parm = NIL) OR (parm.kind IN {par, varpar}));
    RETURN parm;
  END FirstParm;

  PROCEDURE FirstLocalVar*(proc : SymbolProc) : Symbol;
    VAR
      sym : Symbol;
  BEGIN
    sym := proc.scope.first;
    WHILE (sym # NIL) & (sym.kind IN {par, varpar}) DO
      sym := sym.link;
    END;
    RETURN sym;
  END FirstLocalVar;

  PROCEDURE NextParm*(parm : Symbol) : Symbol;
  BEGIN
    IF (parm # NIL) &
       (parm.link # NIL) &
       (parm.link.kind IN {par, varpar}) THEN
      RETURN parm.link;
    ELSE
      RETURN NIL;
    END;
  END NextParm;

  PROCEDURE FirstField*(rec : Record) : Symbol;
  BEGIN
    RETURN rec.scope.first;
  END FirstField;

  PROCEDURE NextField*(f : Symbol) : Symbol;
  BEGIN
    IF (f # NIL) & (f.link # NIL) & (f.link.kind = field) THEN
      RETURN f.link;
    ELSE
      RETURN NIL;
    END;
  END NextField;

  PROCEDURE NextSymbol*(sym : Symbol) : Symbol;
  BEGIN
    IF (sym # NIL) & (sym.link # NIL) THEN
      RETURN sym.link;
    ELSE
      RETURN NIL;
    END;
  END NextSymbol;

  PROCEDURE LinkSymbol*(cur, next : Symbol);
  BEGIN
    cur.link := next;
  END LinkSymbol;

  (** Symbol Lookup *)

  PROCEDURE FindInThisScope*(scope : SymbolScope;
                             name : ARRAY OF CHAR) : Symbol;
    VAR
      sym : Symbol;
      hash, len : LONGINT;
  BEGIN
    len := LEN(scope.table^);
    hash := Hash(name) MOD len;
    sym := scope.table[hash];

    WHILE (sym # NIL) & (sym.name^ # name) DO
      sym := sym.hash;
    END;
    RETURN sym;
  END FindInThisScope;

  PROCEDURE FindInOpenScopes*(scope : SymbolScope;
                              name : ARRAY OF CHAR) : Symbol;
    VAR
      sym : Symbol;
  BEGIN
    REPEAT
      sym := FindInThisScope(scope, name);
      IF scope.link # NIL THEN
        scope := scope.link(SymbolScope);
      ELSE
        scope := NIL;
      END;
    UNTIL (sym # NIL) OR (scope = NIL);
    ASSERT((scope = NIL) OR (sym # NIL)); (* If scopes have not run out,
                                           * a symbol must have been found.
                                           *)
    RETURN sym;
  END FindInOpenScopes;

  (* FindField:
   * looks for a field of name 'name' in the 'rec' and its ancestors
   * pre: ASCIIZ(name)
   * pre: (rec = NIL) OR defined(rec^)
   * post: result = NIL -> no field found
   * post: result # NIL -> defined(result^)
   *)
  PROCEDURE FindField*(name : ARRAY OF CHAR; rec : Record) : Symbol;
    VAR
      sym : Symbol;
  BEGIN
    IF rec # NIL THEN
      REPEAT
        sym := FindInThisScope(rec.scope, name);
        rec := rec.ancestor;
      UNTIL (rec = NIL) OR (sym # NIL);

      (* If scopes have not run out, a symbol must have been found. *)
      ASSERT((rec = NIL) OR (sym # NIL));
      RETURN sym;
    ELSE
      RETURN NIL;
    END;
  END FindField;

  PROCEDURE Find*(name : ARRAY OF CHAR) : Symbol;
  BEGIN
    RETURN FindInOpenScopes(topScope, name);
  END Find;

  PROCEDURE FindImport*(module : SymbolProc; name : ARRAY OF CHAR) : Symbol;
    VAR
      sym : Symbol;
      td : SymbolTypeDesc;
  BEGIN
    sym := FindInThisScope(module.scope, name);
    IF (sym # NIL) & (sym.vis IN {export, exportR}) THEN
      INCL(sym.flags, used);
      td := GetTD(sym.type);          (* Ensure type descriptors for
                                       * types also get imported. *)
      RETURN sym;
    ELSE
      RETURN NIL;
    END;
  END FindImport;

  PROCEDURE FindMethodByNumber*(rec : Record; methno : LONGINT) : Symbol;
    VAR
      meth : Symbol;
      i, len : LONGINT;
  BEGIN
    ASSERT(rec # NIL, 1098);
    ASSERT(methodcounted IN rec.flags, 190);
    WHILE rec # NIL DO
      ASSERT(rec.scope # NIL, 1099);
      ASSERT(rec.scope.table # NIL, 1100);
      i := 0;
      len := LEN(rec.scope.table^);
      WHILE i < len DO
        meth := rec.scope.table[i];
        WHILE meth # NIL DO
          IF (meth.kind = tproc) & (meth(SymbolProc).methno = methno) THEN
            RETURN meth;
          END;
          meth := meth.hash;
        END;
        INC(i);
      END;
      rec := rec.ancestor;
    END;
    HALT(1024); (* The method number requested did not exist; fatal error. *)
  END FindMethodByNumber;

  (* TRUE => x is extension of b *)
  PROCEDURE Extends*(x, b: Type) : BOOLEAN;
  BEGIN
    IF (b.form = pointer) & (x.form = pointer) THEN
      b := b(Pointer).to;
      x := x(Pointer).to
    END;
    IF (b.form = record) & (x.form = record) THEN
      WHILE (x # b) & (x # NIL) DO
        x := x(Record).ancestor;
      END;
    END ;
    RETURN x = b
  END Extends;

  PROCEDURE ImportSYSTEM*(VAR mod : SymbolScope);
  BEGIN
    mod := sysScope;
  END ImportSYSTEM;

  PROCEDURE SetModuleName*(name : ARRAY OF CHAR);
  BEGIN
    COPY(name, SelfName);
    SetSymbolName(topScope, name);
  END SetModuleName;

  PROCEDURE MakeIntrinsicType(VAR t : Type; form : SHORTINT);
  BEGIN
    t := NewBasicType();
    t.form := form;
    t.flags := {allocated, idfpdone, typfpdone};
    t.size := OPM.ByteSize;
    t.ref := form;
    t.idfp := form;
    t.pbfp := form;
    t.pvfp := form;
    t.sym := NewBasicSym(anon);
  END MakeIntrinsicType;

  PROCEDURE MakeStringConst*(VAR str : OPS.String; len : LONGINT) : SymbolConst;
    VAR
      s : SymbolConst;
      name : SymbolName;
  BEGIN
    s := NewConstSym(stringtyp);
    s.val.ext := NewConstExt();
    s.val.i0 := len;
    COPY(str, s.val.ext^);
    name := MakeGeneratedName(NIL, 'str_', nofGenString);
    Insert(name^, s);
    s.mnolev := 0;
    RETURN s;
  END MakeStringConst;

  PROCEDURE GetArrayInfo*(arr : Type; VAR info : ArrayInfoDesc);  (* 1998.11.16: obsolete *)
    VAR
      t : Type;
      nofdim : LONGINT;
      f : SHORTINT;
  BEGIN
    nofdim := 0;
    f := arr.form;
    ASSERT(f IN {dynarr, array});
    t := arr;
    WHILE t.form = f DO
      INC(nofdim);
      t := t(Array).of;
    END;
    info.form := f;
    info.nofdim := nofdim;
    info.eltype := t;
  END GetArrayInfo;

  (* retrieve full procedure name, format is: (Object).proc or proc *)
  PROCEDURE GetFullProcedureName*(proc : SymbolProc; VAR name : OPS.FullName);
    VAR
      i, j : INTEGER;
      ch : CHAR;
      sym : Symbol;
      symname : SymbolName;
  BEGIN
    IF proc.kind = tproc THEN
      sym := FirstScopeVar(proc.scope);
      sym := sym.type.sym;
      ASSERT(sym # NIL);
      name[0] := '(';
      symname := sym.name;
      i := 1;
      ch := symname[0];

      WHILE ch # 0X DO
        name[i] := ch;
        ch := symname[i];
        INC(i);
      END;

      name[i] := ')';
      INC(i);
      j := 0;
      symname := proc.name;
      ch := symname[0];

      WHILE (ch # 0X) & (i < LEN(name) - 1) DO
        name[i] := ch;
        INC(i);
        INC(j);
        ch := symname[j];
      END;
      name[i] := 0X;
    ELSE
      COPY(proc.name^, name);
    END;
  END GetFullProcedureName;

  (* Returns element type of array and dynamic arrays; element type
   * is when the type form is not the same as the input type form.
   *)
  PROCEDURE ElemType*(arr : Array) : Type;
    VAR
      of : Type;
      form : SHORTINT;
  BEGIN
    of := arr.of;
    form := arr.form;
    WHILE of.form = form DO
      of := of(Array).of;
    END;
    RETURN of;
  END ElemType;

  (* alignment of base type *)
  PROCEDURE Base*(type : Type) : LONGINT;
    VAR
      align : LONGINT;
  BEGIN
    WHILE type.form = array DO
      type := type(Array).of;
    END;
    IF type.form = record THEN
      RETURN type(Record).align;
    ELSE
      align := type.size;
      IF align > 4 THEN
        RETURN 4
      ELSE
        RETURN align;
      END;
    END;
  END Base;

  PROCEDURE ProcessScope*(scope    : SymbolScope;
                          proc     : ProcessScopeProc;
                          VAR info : ProcessScopeInfo);
    VAR
      i, len : LONGINT;
      sym : Symbol;
  BEGIN
    len := LEN(scope.table^);
    i := 0;
    WHILE i < len DO
      sym := scope.table[i];
      WHILE sym # NIL DO
        info.sym := sym;
        proc(info);
        sym := sym.hash;
      END;
      INC(i);
    END;
  END ProcessScope;

  PROCEDURE Size*(type : Type);
    VAR
      f : SHORTINT;
      elem, base : Type;
      arr : Array;
      rec : Record;
      fld : Symbol;
      offset, size, align, falign, offs : LONGINT;
  BEGIN
    IF (type # undftyp) & (type.size = OPM.UndefSize) THEN
      f := type.form;
      CASE f OF
      | record:
        rec := type(Record);
        base := rec.ancestor;
        IF base = NIL THEN
          offset := 0;
          align := 1;
        ELSE
          Size(base);
          offset := base.size;
          align := base(Record).align;
        END;
        fld := FirstScopeVar(rec.scope);

        WHILE (fld # NIL) & (fld.kind = field) DO
          base := fld.type;
          Size(base);
          size := base.size;
          falign := Base(base);
          OPM.Align(offset, falign);
          fld.adr := offset;
          INC(offset, size);
          IF falign > align THEN
            align := falign;
          END;
          fld := fld.link;
        END;
        rec.align := align;
        OPM.Align(offset, Base(rec));
        rec.size := offset;
        EXCL(rec.flags, methodcounted);

      | array, dynarr:
        arr := type(Array);
        base := arr.of;
        Size(base);
        IF f = array THEN
          arr.size := arr.n * base.size;
        ELSE
          IF base.form = dynarr THEN
            (* determine location of array bound offset *)
            IF typDynArrParm IN arr.flags THEN
              offs := 4;
            ELSE
              offs := -4;
            END;
            (* DOC: a section on calculating array bound offsets coupled with array layout *)
            arr.size := base.size + 4;
            arr.offset := base(Array).offset + offs; (* offset to next array bound  *)
          ELSIF typDynArrParm IN arr.flags THEN (* parameter dynarr *)
            arr.size := 8; (* data pointer + LEN(arr, 0) *)
            arr.offset := 4; (* LEN(arr, 0) offset *)
          ELSE (* heap dynarr *)
            elem := ElemType(arr);
            IF elem.form = array THEN
              elem := ElemType(elem(Array));
            END;
            IF elem.form IN {bool, byte, char, sint, int,
                             lint, real, lreal, set, procedure} THEN
              arr.size := OPM.DynArrSmpElemSize;
              arr.offset := OPM.DynArrSmpLen0Offs;
            ELSIF elem.form = pointer THEN
              arr.size := OPM.DynArrPtrElemSize;
              arr.offset := OPM.DynArrPtrLen0Offs;
            ELSE (* elem.form = record *)
              arr.size := OPM.DynArrRecElemSize;
              arr.offset := OPM.DynArrRecLen0Offs;
            END;
          END;
        END;

      | pointer:
        type.size := OPM.PointerSize;

      | procedure:
        type.size := OPM.ProcSize;
      END;
    END;
  END Size;

  (* TRUE => sym is a module identifier;
   * FALSE => sym is not a module identifier
   * pre: sym # NIL
   *)
  PROCEDURE IsModule*(sym : Symbol) : BOOLEAN;
  BEGIN
    RETURN (sym.kind = xproc) & (modinit IN sym.flags);
  END IsModule;

  PROCEDURE SetModuleSymbol*(mod : ModuleScope; sym : SymbolProc);
  BEGIN
    mod.module := sym;
  END SetModuleSymbol;

  (* Number of "open" dimensions of 'type'.
   * Zero if 'type' isn't an open array (or no array at all).
   *)
  PROCEDURE OpenDimensions*(type: Type): INTEGER;
  BEGIN
    IF ~(type.form IN {openarr, dynarr}) THEN
      RETURN 0;
    ELSE
      RETURN OpenDimensions(type(Array).of) + 1;
    END;
  END OpenDimensions;

  (* Number of dimensions of 'type'.
   * Zero if 'type' isn't an array, 1 if 'type'
   * is a one-dimensioned array (of fixed size or open), increasing by 1 for
   * every nested array type.
  *)
  PROCEDURE Dimensions*(type: Type): INTEGER;
  BEGIN
    IF ~(type.form IN {array, openarr, dynarr}) THEN
      RETURN 0;
    ELSE
      RETURN Dimensions(type(Array).of) + 1;
    END;
  END Dimensions;

  PROCEDURE NILGlobalPointers;
    VAR
      i : INTEGER;
  BEGIN
    topScope := NIL;
    NullString := NIL;
    i := 0;
    WHILE i < LEN(GlbMod) DO
      GlbMod[i] := NIL;
      INC(i);
    END;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin*;
  BEGIN
    NILGlobalPointers;
    nofGenString := 0;
    nofGenTD := 0;
    nofGenVar := 0;
    nofTD := 0;
    topScope := universe;
    OpenModuleScope(0, NIL);
    SYSimported := FALSE;
    SelfName[0] := 0X;
    topScope.name := NIL;
    GlbMod[0] := topScope(ModuleScope);
    nofGmod := 1;
    NEW(NullString, 1);
    NullString[0] := 0X;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
    VAR
      s : SymbolScope;
  BEGIN
    s := CloseScope();
    NILGlobalPointers;
  END ModuleEnd;

  PROCEDURE SymtabInit;
    VAR
      cdecl : Symbol;
      stdcall : Symbol;
  BEGIN
    MakeIntrinsicType(undftyp, undef);
    MakeIntrinsicType(notyp, void);
    MakeIntrinsicType(stringtyp, string);
    MakeIntrinsicType(niltyp, nil);
    niltyp.size := OPM.PointerSize;
    topScope := NIL;
    OpenModuleScope(0, NIL);

    (*initialization of module SYSTEM*)
    EnterTyp("BYTE", byte, OPM.ByteSize, bytetyp);
    EnterPtrTyp("PTR",  pointer, OPM.PointerSize, sysptrtyp);
    EnterProc("ADR", adrfn, linttyp);
    EnterProc("LSH", lshfn, linttyp);
    EnterProc("ROT", rotfn, linttyp);
    EnterProc("GET", getfn, notyp);
    EnterProc("PUT", putfn, notyp);
    EnterProc("GETREG", getrfn, notyp);
    EnterProc("PUTREG", putrfn, notyp);
    EnterProc("BIT", bitfn, booltyp);
    EnterProc("VAL", valfn, notyp); (* parsing must set up the proper type in lmstp.mod *)
    EnterProc("NEW", sysnewfn, notyp);
    EnterProc("MOVE", movefn, notyp);
    EnterProc("MEMR", memrfn, notyp);
    EnterProc("MEMW", memwfn, notyp);
    EnterProc("FINALIZE", finalizefn, notyp);
    EnterProc("BITR", bitrfn, notyp);
    EnterProc("BITS", bitsfn, notyp);

    cdecl := EnterIntConst("C", OPM.CCallVal);
    stdcall := EnterIntConst("STDCALL", OPM.StdCallVal);

    sysScope := topScope;
    sysScope.kind := module;
    universe := CloseScope();
    OpenModuleScope(0, NIL);
    universe := topScope;

    EnterTyp("BOOLEAN", bool, OPM.BoolSize, booltyp);
    EnterTyp("CHAR", char, OPM.CharSize, chartyp);
    EnterTyp("SHORTINT", sint, OPM.SIntSize, sinttyp);
    EnterTyp("INTEGER", int, OPM.IntSize, inttyp);
    EnterTyp("LONGINT",  lint, OPM.LIntSize, linttyp);
    EnterTyp("REAL", real, OPM.RealSize, realtyp);
    EnterTyp("LONGREAL", lreal, OPM.LRealSize, lrltyp);
    EnterTyp("SET", set, OPM.SetSize, settyp);

    (* init things which need a real type which are in the SYSTEM unit *)
    cdecl.type := inttyp;
    stdcall.type := inttyp;

    EnterBoolConst("FALSE", OPM.FalseVal);
    EnterBoolConst("TRUE",  OPM.TrueVal);
    EnterProc("HALT", haltfn, notyp);
    EnterProc("NEW", newfn, notyp);
    EnterProc("ABS", absfn, notyp); (* parsing must set up the real type in lmstp.mod *)
    EnterProc("CAP", capfn, chartyp);
    EnterProc("ORD", ordfn, notyp);
    EnterProc("ENTIER", entierfn, linttyp);
    EnterProc("ODD", oddfn, booltyp);
    EnterProc("MIN", minfn, notyp);
    EnterProc("MAX", maxfn, notyp);
    EnterProc("CHR", chrfn, chartyp);
    EnterProc("SHORT", shortfn, notyp);
    EnterProc("LONG", longfn, notyp);
    EnterProc("SIZE", sizefn, notyp);
    EnterProc("INC", incfn, notyp);
    EnterProc("DEC", decfn, notyp);
    EnterProc("INCL", inclfn, notyp);
    EnterProc("EXCL", exclfn, notyp);
    EnterProc("LEN", lenfn, linttyp);
    EnterProc("COPY", copyfn, notyp);
    EnterProc("ASH", ashfn, linttyp);
    EnterProc("ASSERT", assertfn, notyp);
  END SymtabInit;

BEGIN
  (* Sanity checks for flags *)
  ASSERT(leaf IN symCommonFlags, 130);
  ASSERT(body IN symSpecificFlags, 131);
  ASSERT(modinit IN symSpecificFlags, 132);
  ASSERT(intrinsic IN symSpecificFlags, 133);
  ASSERT(redef IN symSpecificFlags, 134);
  ASSERT(~(allocated IN FPrintSet), 135);
  ASSERT(~(method IN FPrintSet), 136);
  ASSERT(nofTypes <= MAX(SET), 137);
  ASSERT(nofSymbols <= MAX(SET), 138);

  (* enusre that arithmetic on these entities uses masking logic instead of IDIV *)
  ASSERT(ScopeLenRecord MOD 2 = 0, 139);
  ASSERT(ScopeLenProcedure MOD 2 = 0, 140);
  ASSERT(ScopeLenModule MOD 2 = 0, 141);
  SymtabInit;
END SKLST.
