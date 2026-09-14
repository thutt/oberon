MODULE O3Symtab; (* Symbol Table Hash Table *)
(* XXX document: SYSTEM is always given level 0.
 * If it is given another level, the GlbMod array needs to be modified so
 * range errors do not occur when things like fingerprinting access the
 * array based on the declaration level of the symbol.
 *)

  IMPORT
    MDep := O3MachineDep, (* machine dependent functionality *)
    Config := O3Config,
    Scanner:= O3Scanner;

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

  CONST (* Fingerprinting Flags; used in Type & Symbol *)
    pbused*    = 0;
    pvused*    = 1;
    typfpdone* = 2;
    idfpdone*  = 3;
    idfpresv0  = 4;
    idfpresv1  = 5; (* reserved fingerprint slots *)

  CONST
    typFingerprintFlags = {00..05};  (* Flags which are reserved for the
                                      * fingerprinting mechanism.
                                      * See:
                                      *   'Fingerprinting Flags'
                                      *   symFingerprintFlags). *)
    typCommonFlags = {06..17};       (* Flags which are shared amongst all
                                      * Type extensions. *)
    typSpecificFlags = {18..27};     (* Each Type extension may use these
                                      * flags w/o conflicting with other
                                      * Types. *)
    typGenericFlags = {28..31};      (* Flags which can be used generically
                                      * outside this module. *)
    typPersistentFlags* = (typCommonFlags +
                           typSpecificFlags +
                           typGenericFlags); (* flags which will be written to Sym *)

  CONST (* Symbol type flags *)
    allocated* = 6;  (* indicates if a type has been sized,
                      * fields allocated offsets & methods counted *)

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

  TYPE
    Array* = POINTER TO ArrayDesc;
    ArrayDesc* = RECORD (TypeDesc)
      n* : LONGINT;  (* form = array => n = elems; form IN {openarr, dynarr} => n = dims (0 based) *)
      of* : Type;
      td* : SymbolTypeDesc; (* type descriptor *)
      offset* : LONGINT;  (* form = array => 0;
                           * form = dynarr => offset of LEN() in descriptor;
                           * form = openarr = offset of LEN() on stack
                           *)
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
      td* : SymbolTypeDesc;  (* type descriptor & vmt *)
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
    ConstExt* = POINTER TO Scanner.String;
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
    cproc*      = 9;   (* Code PROCEDURE *)
    iproc*      = 10;  (* Interrupt PROCEDURE *)
    tproc*      = 11;
    field*      = 12;
    type*       = 13;
    module*     = 14;  (* Can only be a SymbolScope. *)
    scope*      = 15;
    darrdesc*   = 16;
    arrdesc*    = 17;  (* Array descriptor for
                        * 'pointer to static array' only. *)
    recdesc*    = 18;
    nofSymbols* = 19;

  CONST (* symbol visibility *)
    hidden* = 0; (* compiler generated symbols; exported explicitly *)
    internal* = 1; export* = 2; exportR* = 3;

  CONST (* fingerprint history *)
    inserted* = 1; same* = 2; pbmodified* = 3; pvmodified* = 4; removed* = 5; inconsistent* = 6;

  CONST
    symFingerprintFlags* = {0..5};   (* Flags which are reserved for the
                                      * fingerprinting mechanism
                                      * See:
                                      *   'Fingerprinting Flags'
                                      *   typFingerprintFlags. *)
    symCommonFlags*      = {06..17}; (* Flags which are shared amongst
                                      * all Symbol extensions *)
    symSpecificFlags*    = {18..27}; (* Each Symbol extension may use these
                                      * flags w/o conflicting with
                                      * other Symbols. *)
    symGenericFlags*     = {28..31}; (* Can be used by other modules freely. *)

  CONST (* common flags *)
    leaf*      = 6; (* Internal visibility, address not taken. *)
    used*      = 7; (* Indicates a symbol has been looked up
                     * in the symbol table. *)
    invisible* = 8; (* symbol is imported but not visible to the importing unit
                     * (hidden pointers, procedures & methods). *)

  CONST
    (* leaf & used status are not persistent *)
    symPersistentFlags* = (symCommonFlags - {leaf, used, invisible}) +
                          symSpecificFlags +
                          symGenericFlags; (* Flags which will be written
                                            * to '.Sym'. *)

  TYPE
    SymbolName* = POINTER TO ARRAY OF CHAR;

    SymbolDesc* = RECORD
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

      owner : SymbolScope; (* inv: module scope (global) -> owner = NIL *)

      link : Symbol;    (* used for linking symbols together in a list *)
      hash : Symbol; (* generally used for linking symbols together in the hash table *)
      bedata* : BEData;
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
      inv: imported modules will be owned by the importing module
      inv: imported record scopes will be owned by the owning module
      inv: SYSTEM unit will have no owner
      inv: (first = NIL) OR defined(first^) & (first <-> first variable declared in scope)
      inv: (last = NIL) OR defined(last^) & (last <-> most recent variable declared in scope)
    *)
    SymbolScopeDesc* = RECORD (SymbolDesc)
      table : HashTable;
      first, last : Symbol;
      dsize* : LONGINT;      (* data size for this scope *)
      (* hash: owner of this scope *)
    END;

    SymbolModuleScope* = POINTER TO SymbolModuleScopeDesc;
    SymbolModuleScopeDesc* = RECORD (SymbolScopeDesc)
      module : Symbol;  (* symbol which represents the initialization code *)
    END;

  CONST (* SymbolTypeDesc flags *)
    tdinit* = 18; (* Type descriptor already appears on the init-td list. *)

  TYPE
    SymbolTypeDescDesc* = RECORD (SymbolDesc)
      tdnum* : INTEGER;  (* TD number *)
      described* : Type;
    END;

    SymbolRecordTD* = POINTER TO SymbolRecordTDDesc;
    SymbolRecordTDDesc* = RECORD (SymbolTypeDescDesc)
    END;

    SymbolArrayTD* = POINTER TO SymbolArrayTDDesc;
    SymbolArrayTDDesc* = RECORD (SymbolTypeDescDesc)
    END;

  CONST (* procedure flags *)
    body*    = 18;
    redef*   = 19;
    modinit* = 20; (* Procedure symbol is actually module init code. *)
    (* intrinsic:
     *
     * Affects symbol export qualities.
     * A symbol with this flag set is owned by the compiler and not a true
     * symbol in the sense of code generation and address assignment.  A symbol
     * with this flag should not be written to the symbol file or the export
     * block of the object file.
     *)
    intrinsic* = 21; (* Compiler-owned symbol; has no real address
                      * (eg: SYSTEM init code) and must not be exported. *)

  TYPE
    SymbolProc* = POINTER TO SymbolProcDesc;
    SymbolProcDesc* = RECORD (SymbolDesc)
      parsize*, varsize*, methno* : LONGINT;
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
    finalizefn* = 34; (* Finalization function. *)
    bitrfn*     = 35; (* Bit reset. *)
    bitsfn*     = 36; (* Bit set. *)
    ccfn*       = 37;
    SPlast*     = 38;


  CONST (* Procedure Flags. In source with PROCEDURE [cc] notation. *)
    ccCCall*   = 1; (* C calling convention;
                     * parms are right to left;
                     * caller pops stack *)
    ccStdCall* = 2; (* SYSTEM.STDCALL procedure modifier;
                     * parms are right to left;
                     * callee pops *)

  TYPE
    SymbolStdProc* = POINTER TO SymbolStdProcDesc;
    SymbolStdProcDesc* = RECORD (SymbolDesc)
      procno* : SHORTINT; (* standard procedure number *)
    END;

  CONST (* code procedure information *)
    MaxCodeProcLen* = Scanner.MaxStrLen;

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

  CONST
    FPUTempName = '$$FPU'; (* generated floating point temp *)

  TYPE
    TypeMetric* = POINTER TO TypeMetricDesc;
    BoolMetric* = POINTER TO BoolMetricDesc;
    OrdMetric* = POINTER TO OrdMetricDesc;
    RealMetric* = POINTER TO RealMetricDesc;
    LRealMetric* = POINTER TO LRealMetricDesc;

    TypeMetricDesc* = RECORD
      size* : LONGINT;
      align* : SHORTINT;
    END;

    BoolMetricDesc* = RECORD (TypeMetricDesc)
      min*, max* : BOOLEAN;
    END;

    OrdMetricDesc* = RECORD (TypeMetricDesc)
      min*, max* : LONGINT;
    END;

    RealMetricDesc* = RECORD (TypeMetricDesc)
      min*, max* : REAL;
    END;

    LRealMetricDesc* = RECORD (TypeMetricDesc)
      min*, max* : LONGREAL;
    END;

  TYPE (** Machine Information *)
    MachineInfo* = RECORD
      m* : ARRAY nofTypes OF TypeMetric;
    END;

  VAR
    GlbMod* : POINTER TO ARRAY OF SymbolModuleScope;
    SelfName* : Scanner.Name;
    topScope* : SymbolScope;
    SYSimported* : BOOLEAN;
    nofGmod* : SHORTINT;

  VAR (* types *)
    metrics- : POINTER TO ARRAY nofTypes OF TypeMetric;
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
    sysptrtyp-: Type;

  VAR
    nofTD : INTEGER;
    sysScope : SymbolScope;
    universe : SymbolScope;
    NullString : SymbolName;
    nofGenString, nofGenTD, nofGenVar : INTEGER;

  PROCEDURE ^ Insert*(name : ARRAY OF CHAR; sym : Symbol; VAR duplicate : BOOLEAN);
  PROCEDURE ^ InsertScope*(scope : SymbolScope; name : ARRAY OF CHAR; sym : Symbol; VAR duplicate : BOOLEAN);
  PROCEDURE ^ FindInOpenScopes*(scope : SymbolScope; name : ARRAY OF CHAR) : Symbol;
  PROCEDURE ^ FindInThisScope*(scope : SymbolScope; name : ARRAY OF CHAR) : Symbol;

  PROCEDURE ^ Find*(name : ARRAY OF CHAR) : Symbol;
  PROCEDURE ^ InitBasicSymbol(s : Symbol; k : SHORTINT);
  PROCEDURE ^ GetTD*(owner : Symbol; type : Type) : SymbolTypeDesc;

  (** Utility *)

  PROCEDURE Hash*(name : ARRAY OF CHAR) : LONGINT;
  BEGIN
    RETURN MDep.Hash(name);
  END Hash;

  PROCEDURE ProcessScope*(scope : SymbolScope;
                          proc : ProcessScopeProc;
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

  (* TRUE => x is extension of b *)
  PROCEDURE Extends*(x, b: Type) : BOOLEAN;
  BEGIN
    IF (b.form = pointer) & (x.form = pointer) THEN
      b := b(Pointer).to; x := x(Pointer).to
    END ;

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

  PROCEDURE GetTempFPU*() : Symbol;
    VAR
      sym : Symbol;
  BEGIN
    sym := Find(FPUTempName);
    ASSERT(sym # NIL);
    RETURN sym;
  END GetTempFPU;

  PROCEDURE MakeTempFPU*;
    VAR
      s : Symbol;
      dup : BOOLEAN;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, var);
    s.type := lrltyp; (* to force it to be eight bytes *)
    Insert(FPUTempName, s, dup);
    ASSERT(~dup);
  END MakeTempFPU;

  (* MakeGeneratedName: generate a unique symbol name
   * pre : owner # NIL -> defined(owner^) & owner name is used in generated name
   * pre :    (described = NIL)
   *       OR (described.name = NIL) -> owner & described are not used
   *                                    generated name comprised of '.' + prefix + number
   *                                    ASCIIZ(prefix)
   * pre :   (described # NIL)
   *       & (described.name = NIL) -> prefix ignored
   *
   * pre : nofGenNames <-> number of generated names
   * post: result # NIL & defined(result^)
   * post: nofGenNames <- old nofGenNames + 1
   *
   * Creates unique generated name and places it into the
   * currently open scope.  The name is formed from the
   * 'owner' and 'described' symbols, or from the prefix and an
   * integer count.
   * All names are prefixed with '.' to ensure no collision with user-space names.
   *)
  PROCEDURE MakeGeneratedName*(owner, described : Symbol;
                               prefix           : ARRAY OF CHAR;
                           VAR nofGenNames      : INTEGER) : SymbolName;
    VAR
      name, symName : SymbolName;
      i : LONGINT;
      j : LONGINT;
      len : LONGINT;
      ownerLen : LONGINT;
      ch : CHAR;
      number : Scanner.Name;

    (* pre: undefined(dest) *)
    (* pre: undefined(l) *)
    (* post: ASCIIZ(dest) *)
    (* post: (El: 0 <= i < LEN(dest): dest[i] = 0X & (l <- i + LEN(prefix) - )) *)
    PROCEDURE NextNumber(VAR dest : Scanner.Name; VAR l : LONGINT);
      VAR
        temp : Scanner.Name;
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
    IF (described = NIL) OR (described.name = NIL) THEN
      NextNumber(number, len);
      NEW(name, len + 1); (* include room for '.' *)
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
      IF (owner # NIL) THEN
        ownerLen := LEN(owner.name^) + 1;
      ELSE
        ownerLen := 0;
      END;

      len := ownerLen + LEN(described.name^);
      NEW(name, len + 1); (* include room for '.' *)
      name[0] := '.';

      i := 1;
      IF ownerLen > 0 THEN
        symName := owner.name; ASSERT(symName # NIL);
        j := 0;
        REPEAT
          ch := symName[j];
          name[i] := ch;
          INC(i);
          INC(j);
        UNTIL ch = 0X;
        name[i - 1] := '-';
      END;

      symName := described.name;
      j := 0;
      REPEAT
        ch := symName[j];
        name[i] := ch;
        INC(i);
        INC(j);
      UNTIL ch = 0X;
    END;
    RETURN name;
  END MakeGeneratedName;

  PROCEDURE IntTypeOf*(v : LONGINT) : Type;
    VAR
      t : Type;
  BEGIN
    IF (v >= metrics[sint](OrdMetric).min) &
       (v <= metrics[sint](OrdMetric).max) THEN
      t := sinttyp;
    ELSIF (v >= metrics[int](OrdMetric).min) &
          (v <= metrics[int](OrdMetric).max) THEN
      t := inttyp;
    ELSIF (v >= metrics[lint](OrdMetric).min) &
          (v <= metrics[lint](OrdMetric).max) THEN
    (*bootstrap/cross*)
      t := linttyp;
    ELSE
      t := undftyp;
      (* A bootstrapping compiler may return a valid type in this situation;
       * undftype should be returned to signal an error.
       *)
    END;
    RETURN t;
  END IntTypeOf;

  PROCEDURE NewConstExt*() : ConstExt;
    VAR
      x : ConstExt;
  BEGIN
    NEW(x);
    RETURN x;
  END NewConstExt;

  (** Type Initialization *)

  PROCEDURE InitBasicType(t : Type; f : SHORTINT);
  BEGIN
    t.form := f;
    t.mno := 0;
    t.flags := {};
    t.ref := Config.MaxExportedTypes;
    t.sysflag :=  Config.DefaultSysFlag;

    (* inv: t.size = metrics[undef].size -> size has not been calculated; see TypeAllocate.Size() *)
    t.size := metrics[undef].size;
    t.pos := 0;
    t.idfp := Config.DefaultFP;
    t.pvfp := Config.DefaultFP;
    t.pbfp := Config.DefaultFP;
    t.sym := NIL;
    t.bedata := NIL;
  END InitBasicType;

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

  PROCEDURE NewStaticArray*(elem : Type; len : LONGINT) : Array;
    VAR
      t : Array;
  BEGIN
    t := NewArrayType(array);
    t.n := len;
    t.of := elem;
    t.td := GetTD(topScope, t);
    t.offset := 0;
    RETURN t;
  END NewStaticArray;

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
    t.nofmeth := MIN(LONGINT); (* methods not counted yet *)
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
    t.size := metrics[procedure].size;
    t.parms := NIL;
    t.result := notyp;
    RETURN t;
  END NewProcedureType;

  (*** Symbol Constructors ***)

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
    s.adr := Config.UndefAdr;
    s.fprint := Config.DefaultFP;
    s.link := NIL;
    s.hash := NIL;
    s.name := NIL;
    s.bedata := NIL;
  END InitBasicSymbol;

  PROCEDURE InitTD(kind : SHORTINT; td : SymbolTypeDesc; described : Type);
    VAR
      symname : Scanner.Name;
  BEGIN
    InitBasicSymbol(td, kind);
    td.type := linttyp;
    td.described := described;
    td.vis := hidden;
    td.tdnum := nofTD;
    INC(nofTD);
  END InitTD;

  PROCEDURE InitProcedureSym(s : SymbolProc; k : SHORTINT);
  BEGIN
    InitBasicSymbol(s, k);
    s.type := NewProcedureType();
    s.methno := Config.UndefAdr;
    s.scope := NIL;
  END InitProcedureSym;

  (** Symbol Constructors *)

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

  PROCEDURE InitScopeSym(s : SymbolScope; owner : Symbol; len : LONGINT);
  BEGIN
    InitBasicSymbol(s, scope);
    NEW(s.table, len);
    s.first := NIL;
    s.last := NIL;
    s.dsize := metrics[undef].size;

    WHILE len > 0 DO
      DEC(len);
      s.table[len] := NIL;
    END;
    s.hash := owner;
  END InitScopeSym;

  PROCEDURE NewModuleScopeSym*(owner : Symbol) : SymbolModuleScope;
    VAR
      s : SymbolModuleScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, owner, ScopeLenModule);
    RETURN s;
  END NewModuleScopeSym;

  PROCEDURE NewRecordScopeSym*(owner : Symbol) : SymbolScope;
    VAR
      s : SymbolScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, owner, ScopeLenRecord);
    RETURN s;
  END NewRecordScopeSym;

  PROCEDURE NewProcedureScopeSym*(owner : Symbol) : SymbolScope;
    VAR
      s : SymbolScope;
  BEGIN
    NEW(s);
    InitScopeSym(s, owner, ScopeLenProcedure);
    RETURN s;
  END NewProcedureScopeSym;

  PROCEDURE NewTempVar*(type : Type) : Symbol;
    VAR
      s : Symbol;
      name : SymbolName;
      dup : BOOLEAN;
  BEGIN
    NEW(s);
    InitBasicSymbol(s, var);
    s.type := type;
    name := MakeGeneratedName(NIL, NIL, 'var_', nofGenVar);
    Insert(name^, s, dup);
    ASSERT(~dup);
    RETURN s;
  END NewTempVar;

  PROCEDURE NewRecordTD*(desc : Type) : SymbolRecordTD;
    VAR
      s : SymbolRecordTD;
  BEGIN
    NEW(s);
    InitTD(recdesc, s, desc);
    RETURN s;
  END NewRecordTD;

  PROCEDURE NewDynArrayTD*(desc : Type) : SymbolArrayTD;
    VAR
      s : SymbolArrayTD;
  BEGIN
    NEW(s);
    InitTD(darrdesc, s, desc);
    RETURN s;
  END NewDynArrayTD;

  PROCEDURE NewArrayTD*(desc : Type) : SymbolArrayTD;
    VAR
      s : SymbolArrayTD;
  BEGIN
    NEW(s);
    InitTD(arrdesc, s, desc);
    RETURN s;
  END NewArrayTD;

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

  (** Symbol Utility *)

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

  (** Type Utility *)

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
  PROCEDURE GetTD*(owner : Symbol; type : Type) : SymbolTypeDesc;
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
        dup : BOOLEAN;
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
          elemtd := GetTD(owner, element);
        END;
      END;
      td.described := describedType;
      descName := MakeGeneratedName(owner, describedType.sym, 'td_', nofGenTD);
      InsertScope(GlobalScope(), descName^, td, dup);
      ASSERT(~dup, 252);
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

  (** Initialization Helpers *)

  PROCEDURE EnterTyp(name : Scanner.Name;
                     form : SHORTINT;
                     size : LONGINT;
                     VAR res : Type);
    VAR
      sym : Symbol;
      typ : Type;
      dup : BOOLEAN;
  BEGIN
    sym := NewBasicSym(type);
    Insert(name, sym, dup);
    ASSERT(~dup);
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

  PROCEDURE EnterPtrTyp(name : Scanner.Name;
                        form : SHORTINT;
                        size : LONGINT;
                        VAR res : Type);
    VAR
      sym : Symbol;
      typ : Pointer;
      dup : BOOLEAN;
  BEGIN
    sym := NewBasicSym(type);
    Insert(name, sym, dup);
    ASSERT(~dup);
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

  PROCEDURE EnterProc(name : Scanner.Name; procno: SHORTINT; result : Type);
    VAR
      sym : Symbol;
      dup : BOOLEAN;
  BEGIN
    sym := NewStdProcSym(procno, result);
    sym.mnolev := IntrinsicLevel;
    Insert(name, sym, dup);
    ASSERT(~dup);
    sym.vis := export;
  END EnterProc;

  PROCEDURE EnterIntConst(name : Scanner.Name; val : SHORTINT) : Symbol;
    VAR
      sym : SymbolConst;
      dup : BOOLEAN;
  BEGIN
    sym := NewConstSym(IntTypeOf(val));
    Insert(name, sym, dup);
    ASSERT(~dup);
    sym.mnolev := IntrinsicLevel;
    sym.val.i0 := val;
    sym.vis := export;
    RETURN sym;
  END EnterIntConst;

  PROCEDURE EnterBoolConst(name : Scanner.Name; val : BOOLEAN);
    VAR
      sym : SymbolConst;
      dup : BOOLEAN;
  BEGIN
    sym := NewConstSym(booltyp);
    Insert(name, sym, dup);
    ASSERT(~dup);
    sym.mnolev := IntrinsicLevel;
    sym.val.bool := val;
  END EnterBoolConst;

  PROCEDURE MakeIntrinsicType(VAR t : Type; form : SHORTINT);
  BEGIN
    t := NewBasicType();
    t.form := form;
    t.flags := {allocated, idfpdone, typfpdone};
    t.size := metrics[byte].size;
    t.ref := form;
    t.idfp := form;
    t.pbfp := form;
    t.pvfp := form;
    t.sym := NewBasicSym(anon);
  END MakeIntrinsicType;

  PROCEDURE MakeStringConst*(str : Scanner.String;
                             len : LONGINT) : SymbolConst;
    VAR
      s : SymbolConst;
      name : SymbolName;
      dup : BOOLEAN;
  BEGIN
    s := NewConstSym(stringtyp);
    s.val.ext := NewConstExt();
    s.val.i0 := len;
    COPY(str, s.val.ext^);
    name := MakeGeneratedName(NIL, NIL, 'str_', nofGenString);
    Insert(name^, s, dup); ASSERT(~dup);
    s.mnolev := 0;
    RETURN s;
  END MakeStringConst;

  (** Insert *)

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
                         sym : Symbol;
                         VAR duplicate : BOOLEAN);
    VAR
      hash : LONGINT;
      len : LONGINT;
  BEGIN
    duplicate := FALSE;
    len := LEN(scope.table^);
    hash := Hash(name) MOD len;
    IF FindInThisScope(scope, name) # NIL THEN
      duplicate := TRUE; (* multiple definition *)
    END;

    (* Duplicate symbols will set the 'duplicate' parm, but
     * will still be entered into the symbol table so that
     * anything relying on 'Insert' actually inserting the
     * symbol into the current symbol list will function properly
     *)
    INCL(sym.flags, leaf);
    SetSymbolName(sym, name);
    IF sym.mnolev = UndefMnolev THEN
      sym.mnolev := scope.mnolev;
    END;
    InsertHash(scope, sym);
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

  (* post: duplicate = true -> multiple definition *)
  (* post: duplicate = false -> first definition *)
  PROCEDURE Insert*(name : ARRAY OF CHAR;
                    sym : Symbol;
                    VAR duplicate : BOOLEAN);
  BEGIN
    InsertScope(topScope, name, sym, duplicate);
  END Insert;

  (** Scope Handling *)

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

  PROCEDURE OpenScopeRecord*(owner : Symbol);
    VAR
      s : SymbolScope;
  BEGIN
    s := NewRecordScopeSym(owner);
    OpenScope(s, 0, NIL);
  END OpenScopeRecord;

  PROCEDURE OpenScopeProcedure*(level : SHORTINT; owner : SymbolProc);
    VAR
      s : SymbolScope;
  BEGIN
    s := NewProcedureScopeSym(owner);
    OpenScope(s, level, owner);
  END OpenScopeProcedure;

  PROCEDURE OpenScopeModule*(level : SHORTINT; owner : Symbol);
    VAR
      s : SymbolModuleScope;
  BEGIN
    s := NewModuleScopeSym(owner);
    OpenScope(s, level, owner);
  END OpenScopeModule;

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

  (* returns the symbol which owns the definition of the imput *)
  (* variables: module or procedure *)
  (* fields: record type *)
  (* type descriptors : themselvs *)
  PROCEDURE SymbolOwner*(sym : Symbol) : Symbol;
    VAR
      owner : Symbol;
  BEGIN
    owner :=  ScopeOwner(sym.owner);
    IF owner = NIL THEN (* global symbol *)
      RETURN GlbMod[0].module;
    ELSE
      RETURN owner;
    END;
  END SymbolOwner;

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
    IF sym # NIL THEN
      INCL(sym.flags, used);
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
      td := GetTD(module, sym.type);  (* Ensure type descriptors for
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
    ASSERT(methodcounted IN rec.flags, 190);
    WHILE rec # NIL DO
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

  PROCEDURE SetModuleName*(name : ARRAY OF CHAR);
  BEGIN
    COPY(name, SelfName);
    SetSymbolName(topScope, name);
  END SetModuleName;

  (* retrieve full procedure name, format is: (Object).proc or proc *)
  PROCEDURE GetFullProcedureName*(proc : SymbolProc; VAR name : Scanner.FullName);
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

  (* TRUE => sym is a module identifier;
   * FALSE => sym is not a module identifier
   * pre: sym # NIL
   *)
  PROCEDURE IsModule*(sym : Symbol) : BOOLEAN;
  BEGIN
    RETURN (sym.kind = xproc) & (modinit IN sym.flags);
  END IsModule;

  PROCEDURE SetModuleSymbol*(mod : SymbolModuleScope; sym : SymbolProc);
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

  (* Given an object designating a procedure, a type-bound procedure,
   * or the module, return the module the declaration is part of.
   * Use function 'SymbolTable.Module' for arbitrary objects.
  *)
  PROCEDURE ModuleOf*(sym: Symbol): Symbol;
    VAR
      scope : SymbolScope;
  BEGIN
    scope := sym.owner;
    WHILE (scope.link # NIL) DO
      scope := scope.link(SymbolScope);
    END;
    RETURN scope(SymbolModuleScope).module;
  END ModuleOf;

  PROCEDURE SymtabInit;
    VAR
      cdecl : Symbol;
      stdcall : Symbol;
      s : SymbolScope;
  BEGIN
    MakeIntrinsicType(undftyp, undef);
    MakeIntrinsicType(notyp, void);
    MakeIntrinsicType(stringtyp, string);
    MakeIntrinsicType(niltyp, nil);
    niltyp.size := metrics[pointer].size;
    topScope := NIL;
    OpenScopeModule(0, NIL);

    (*initialization of module SYSTEM*)
    EnterTyp("BYTE", byte, metrics[byte].size, bytetyp);
    EnterPtrTyp("PTR",  pointer, metrics[pointer].size, sysptrtyp);
    EnterProc("ADR", adrfn, linttyp);
    EnterProc("CC", ccfn, booltyp);
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

    cdecl := EnterIntConst("C", ccCCall);
    stdcall := EnterIntConst("STDCALL", ccStdCall);

    sysScope := topScope;
    sysScope.kind := module;
    universe := CloseScope();
    OpenScopeModule(0, NIL);
    universe := topScope;

    EnterTyp("BOOLEAN", bool, metrics[bool].size, booltyp);
    EnterTyp("CHAR", char, metrics[char].size, chartyp);
    EnterTyp("SHORTINT", sint, metrics[sint].size, sinttyp);
    EnterTyp("INTEGER", int, metrics[int].size, inttyp);
    EnterTyp("LONGINT",  lint, metrics[lint].size, linttyp);
    EnterTyp("REAL", real, metrics[real].size, realtyp);
    EnterTyp("LONGREAL", lreal, metrics[lreal].size, lrltyp);
    EnterTyp("SET", set, metrics[set].size, settyp);

    (* init things which need a real type which are in the SYSTEM unit *)
    cdecl.type := inttyp;
    stdcall.type := inttyp;

    EnterBoolConst("FALSE", FALSE);
    EnterBoolConst("TRUE",  TRUE);
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

  PROCEDURE CreateTypeMetrics; (* 32-bit type metrics *)
    CONST
      ByteSize = 1;      (* SYSTEM.BYTE *)
      CharSize = 1;      (* CHAR *)
      BoolSize = 1;      (* BOOLEAN *)
      SetSize = 4;      (* SET *)
      SIntSize = 1;      (* SHORTINT *)
      IntSize = 2;      (* INTEGER *)
      LIntSize = 4;      (* LONGINT *)
      RealSize = 4;      (* REAL *)
      LRealSize = 8;      (* LONGREAL *)
      ProcSize = 4;      (* PROCEDURE type *)
      PointerSize = 4;      (* POINTER type *)

      MinSInt = -80H;
      MinInt = -8000H;
      MinLInt =  80000000H;  (* -2147483648*)
      MinRealPat = 0FF7FFFFFH;  (* most  negative, 32-bit pattern *)
      MinLRealPatL = 0FFFFFFFFH;  (* most  negative, lower 32-bit pattern *)
      MinLRealPatH = 0FFEFFFFFH;  (* most  negative, higher 32-bit pattern *)

      MaxSInt = 7FH;
      MaxInt = 7FFFH;
      MaxLInt = 7FFFFFFFH;    (*2147483647*)
      MaxSet = 31;            (* 31 is minimum value allowed *)
      MaxRealPat = 7F7FFFFFH;    (* most positive, 32-bit pattern *)
      MaxLRealPatL = 0FFFFFFFFH;    (* most positive, lower 32-bit pattern *)
      MaxLRealPatH = 7FEFFFFFH;    (* most positive, higher 32-bit pattern *)

    VAR
      MinReal, MaxReal : REAL;
      MinLReal, MaxLReal : LONGREAL;

    PROCEDURE Generic(form, align : SHORTINT; size : LONGINT);
      VAR
        gen : TypeMetric;
    BEGIN
      NEW(gen);
      gen.size := size;
      gen.align := align;
      metrics[form] := gen;
    END Generic;

    PROCEDURE Bool(form : SHORTINT; size : LONGINT);
      VAR
        b : BoolMetric;
    BEGIN
      NEW(b);
      b.size := size;
      b.align := 1;
      b.min := FALSE;
      b.max := TRUE;
      metrics[form] := b;
    END Bool;

    PROCEDURE Ord(form, align : SHORTINT; size : LONGINT; min, max : LONGINT);
      VAR
        ord : OrdMetric;
    BEGIN
      NEW(ord);
      ord.size := size;
      ord.align := align;
      ord.min := min;
      ord.max := max;
      metrics[form] := ord;
    END Ord;

    PROCEDURE Real(form : SHORTINT; size : LONGINT; min, max : REAL);
      VAR
        real : RealMetric;
    BEGIN
      NEW(real);
      real.size := size;
      real.align := 4;
      real.min := min;
      real.max := max;
      metrics[form] := real;
    END Real;

    PROCEDURE LReal(form : SHORTINT; size : LONGINT; min, max : LONGREAL);
      VAR
        real : LRealMetric;
    BEGIN
      NEW(real);
      real.size := size;
      real.align := 8;
      real.min := min;
      real.max := max;
      metrics[form] := real;
    END LReal;

    PROCEDURE SetRealValues; (* XXX maybe this should be moved out of
                              * Symtab to remove the dependence on SYSTEM *)
    END SetRealValues;

  BEGIN
    MDep.SetRealValues(MinReal, MinRealPat,
                       MaxReal, MaxRealPat,
                       MinLReal, MinLRealPatL, MinLRealPatH,
                       MaxLReal, MaxLRealPatL, MaxLRealPatH);

    NEW(metrics);
    (* undef size must be unrepresentable since it indicates the size is not calculated *)
    Generic(undef, 0, MIN(LONGINT));
    Bool(bool, BoolSize);
    Ord(byte, ByteSize, ByteSize, 0, 0FFH);
    Ord(char, CharSize, CharSize, 0, 0FFH);
    Ord(sint, SIntSize, SIntSize, MinSInt, MaxSInt);
    Ord(int, IntSize, IntSize, MinInt, MaxInt);
    Ord(lint, LIntSize, LIntSize, MinLInt, MaxLInt);
    Real(real, RealSize, MinReal, MaxReal);
    LReal(lreal, LRealSize, MinLReal, MaxLReal);
    Ord(set, SetSize, SetSize, 0, MaxSet);
    (* string is intrinsic *)
    Generic(nil, 4, PointerSize);
    Generic(void, 0, 0);
    Generic(pointer, PointerSize, PointerSize);
    Generic(procedure, ProcSize, ProcSize);
    metrics[array] := NIL;
    metrics[openarr] := NIL;
    metrics[dynarr] := NIL;
    metrics[record] := NIL;
  END CreateTypeMetrics;

  PROCEDURE NILGlobalPointers;
    VAR
      i : INTEGER;
  BEGIN
    topScope := NIL;
    NullString := NIL;
    GlbMod := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin(sourceinfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    nofGenString := 0;
    nofGenTD := 0;
    nofGenVar := 0;
    nofTD := 0;
    topScope := universe;
    SYSimported := FALSE;
    SelfName[0] := 0X;
    NEW(NullString, 1);
    NullString[0] := 0X;
    NEW(GlbMod, MaxImports); RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(sourceinfo : Config.SourceInfo) : BOOLEAN;
    VAR s : SymbolScope;
  BEGIN s := CloseScope(); NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;

  PROCEDURE Init;
  BEGIN
    (* Sanity checks for flags *)
    ASSERT(leaf IN symCommonFlags, 130);
    ASSERT(body IN symSpecificFlags, 131);
    ASSERT(modinit IN symSpecificFlags, 132);
    ASSERT(intrinsic IN symSpecificFlags, 133);
    ASSERT(redef IN symSpecificFlags, 134);
    ASSERT(~(allocated IN FPrintSet), 135);
    ASSERT(nofTypes <= MAX(SET), 137);
    ASSERT(nofSymbols <= MAX(SET), 138);

    (* enusre that arithmetic on these entities uses masking logic instead of IDIV *)
    ASSERT(ScopeLenRecord MOD 2 = 0, 139);
    ASSERT(ScopeLenProcedure MOD 2 = 0, 140);
    ASSERT(ScopeLenModule MOD 2 = 0, 141);
    Config.ControlModule(ModuleBegin, ModuleEnd);
    CreateTypeMetrics;
    SymtabInit;
  END Init;

BEGIN Init;
END O3Symtab.
