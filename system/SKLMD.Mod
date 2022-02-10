MODULE SKLMD; (* Machine Description *)
  IMPORT SYSTEM, IO:=SKLCMDIO, FileDir;

  TYPE
    SourceInfo* = IO.SourceInfo;
    
  CONST
    (* basic type sizes *)
    ByteSize*        = 1;      (* SYSTEM.BYTE *)
    CharSize*        = 1;      (* CHAR *)
    BoolSize*        = 1;      (* BOOLEAN *)
    SetSize*        = 4;      (* SET *)
    SIntSize*        = 1;      (* SHORTINT *)
    IntSize*        = 2;      (* INTEGER *)
    LIntSize*        = 4;      (* LONGINT *)
    RealSize*        = 4;      (* REAL *)
    LRealSize*      = 8;      (* LONGREAL *)
    ProcSize*        = 4;      (* PROCEDURE type *)
    PointerSize*    = 4;      (* POINTER type *)
    (* inv: PointerSize = LIntSize (compiler & runtime system depend on this *)

    (* target machine minimum values of basic types expressed in host machine format: *)
    MinSInt*        = -80H;
    MinInt*          = -8000H;
    MinLInt*        =  80000000H;  (*NS32000: -2147483648*)
    MinRealPat      = 0FF7FFFFFH;  (* most  negative, 32-bit pattern *)
    MinLRealPatL    = 0FFFFFFFFH;  (* most  negative, lower 32-bit pattern *)
    MinLRealPatH    = 0FFEFFFFFH;  (* most  negative, higher 32-bit pattern *)
    
    (* target machine maximum values of basic types expressed in host machine format: *)
    MaxSInt*        = 7FH;
    MaxInt*          = 7FFFH;
    MaxLInt*        = 7FFFFFFFH;    (*NS32000: 2147483647*)
    MaxSet*          = 31;            (* >= 15, else bootstrap compiler cannot run (IN-tests) *)
    MaxRealPat      = 7F7FFFFFH;    (* most positive, 32-bit pattern *)
    MaxLRealPatL    = 0FFFFFFFFH;    (* most positive, lower 32-bit pattern *)
    MaxLRealPatH    = 7FEFFFFFH;    (* most positive, higher 32-bit pattern *)
    MaxIndex*        = MaxLInt;      (* maximal index value for array declaration: *)
    
    (* Scanner *)
    MaxHDig*        = 8;            (* maximal hexadecimal longint length *)
    MaxRExp*        = 38;            (* maximal real exponent *)
    MaxLExp*        = 308;          (* maximal longreal exponent *)
    
    (* HALT: inclusive range of parameter of standard procedure *)
    HaltAssert*      = 8;            (* anonymous ASSERT *)
    HaltRange*  = 12;          (* value out of range *)
    HaltArray*      = 13;            (* array bound failure *)
    HaltIGuard*      = 14;            (* implicit type guard failure *)
    HaltEGuard*      = 15;            (* explicit type guard failure *)
    HaltCase*        = 16;            (* ELSE-less CASE *)
    HaltFunc*        = 17;            (* function procedure w/o RETURN *)
    HaltWith*        = 18;            (* ELSE-less WITH *)
    HaltGuardCheck* = 19; (* NIL pointer used in type guard *)
    HaltPointerCheck* = 20; (* NIL pointer dereferenced *)
    MinHaltNr*      = 128;    (* value that is higher than the last Halt constant *)
    MaxHaltNr*      = 16384;  (* maximum value for a HALT or ASSERT instruction *)

    (* SYSTEM.GETREG & SYSTEM.PUTREG: inclusive range of register number of procedures *)
    MinRegNr*        = 0;
    MaxRegNr*        = 31;      (* SKL: FP and integer registers. *)
    
    (* maximal value of flag used to mark interface structures: *)
    MinSysFlag*      = 0;
    MaxSysFlag*      = 2;
    DefaultSysFlag*  = 0;

    MaxCC*          = 15;      (* XXX remove this.  It's a remnant of x86's SYSTEM.CC() *)

    ConstNotAlloc*  = MAX(LONGINT);
    
    (* initialization of tdadr field in StrDesc, must be different from any valid address: *)
    UndefReg*        = MAX(INTEGER);
    UndefAdr*        = MAX(LONGINT);
    UndefTDAdr*      = MAX(LONGINT);
    UndefSize*       = MAX(LONGINT);      (* default value to indicate uncalculated type size *)
    UndefTD*         = MAX(LONGINT);      (* indicates an undefined type descriptor number *)
      
    MaxCases*        = 128;    (* maximal number of cases in a case statement: *)
    MaxCaseRange*    = 512;    (* max range of a case (hi - lo ~ jump table size): *)
        
    HDNamePrefix*    = '@';      (* prefix for hidden names written to symbol file (to make them unique & inaccessible from source) *)
  
    NEWusingAdr*    = TRUE;    (* NEW, SYSTEM.NEW uses address of the variable? *)
  
    Eot*            = 0X;      (* character (< " ") returned by procedure Get, for end-of-text *)

    nofTypeMax*      = 200;    (* max exported types allowed in single module inv: < MAX(INTEGER) DIV 2  & <= RecMaxPtrs DIV 2 *)

  CONST
   (* (Multiple of) number of bytes actually allocated by the compiler for runtime structures;
      It is (multiple) size of a memory block and is used to calculate the allocation size of records for use in its
      type descriptor.  This TD field is used by the GC to determine the size of memory blocks
   *)
    AllocBlockSize* = 16;

  CONST (* Descriptor flags bits *)
    DescFlagsValidBit* = ASH(1, 30); (* Indicates valid flags byte and
                                      * not pointer offset.  See documentation for
                                      * Memory Layout and block tags.
                                      *)
    
    (* low-order 8 bits of 'descriptor flags' *)
    DescFlagsRecord* = 0; (* pointer to record *)
    
    DescFlagsDynArray0* = 1; (* pointer to array of simple or procedure type *)
    DescFlagsDynArray1* = 2; (* pointer to array of pointer type *)
    DescFlagsDynArray2* = 3; (* pointer to array of record *)
    
    DescFlagsDynArray3* = 4; (* pointer to array of static array of simple or procedure type *)
    DescFlagsDynArray4* = 5; (* pointer to array of static array of pointer type *)
    DescFlagsDynArray5* = 6; (* pointer to array of static array of record type *)
    
    DescFlagsStatArr0* = 7; (* pointer to static array of simple or procedure type *)
    DescFlagsStatArr1* = 8; (* pointer to static array of pointer type *)
    DescFlagsStatArr2* = 9; (* pointer to static array of record *)

  CONST (* (heap-based) Dynamic Array Info -- see compiler documentation for heap layout of these array types  *)
    (* Offsets in a descriptor for (heap-based) dynamic arrays where the 0-th bound is stored *)
    (* offsets to larger dimensions are stored at larger negative offsets; See ST.Size() *)
    (* see documentation for layout of a heap-allocated array *)
    DynArrSmpLen0Offs* = -8;  (* element: simple & procedure *)
    DynArrPtrLen0Offs* = -8;  (* element: pointer *)
    DynArrRecLen0Offs* = -8;  (* element: record *)
  
    (* (base) offsets of the 0-th element in dynamic arrays*)
    DynArrSmpElem0Offs* = 0;  (* element: simple & procedure *)
    DynArrPtrElem0Offs* = 0;  (* element: pointer *)
    DynArrRecElem0Offs* = 0;  (* element: record *)
  
    (* basic size of dynamic array types
      97.06.15:
      Since the allocation size of heap-based dynamic arrays is handled by the heap allocator (by using the
      information from the type descriptor), the size of a heap-based dynamic array is unused by the compiler.
      (They are unused because there is no way to access the size of a dynamically allocated array entity)
    *)
    DynArrSmpElemSize* = 0;
    DynArrPtrElemSize* = 0;
    DynArrRecElemSize* = 0;
    
  CONST (* RECORD type *)  
    (* be aware that on NT, making RecMaxPtrs larger than the 4K pagesize can result in a stack fault by accessing a stack page that is not yet loaded *)
    RecMaxPtrs*    = 512;      (* maximum pointers a record can have (changing this requires changes to TDs and the GC) *)
    RecMaxExtension*    = 7;        (* maximum level of record extension *) (* XXX remove this limitation from version 2 *)
    
    (* record type descriptor offsets *)
    RecFlags* = 0;
    RecTDTab* = 4; (* address of the extension table for the described type *)
    RecExtLev* = 8;
    RecSize* = 12;
    RecBlockSize* = 16;
    RecNumPtrs* = 20;
    RecName* = 24; (* pointer to name *)
    RecModule* = 28; (* module descriptor *)
    RecFinalize* = 32; (* finalization procedure if not NIL*)
    RecPtrTab* = 36; (* pointer offset table *)

    (* object file parametes *)
    MaxGlobalPointers*  = 100;
    MaxCommands* = 64; (* maximum exported commands in a module *)
    
    MaxIdLen*        = 24;      (* max length of an identifier *)

    (* Intrinsic constants used by the compiler *)    
    FalseVal*        = 0;      (* compiler-internal value of FALSE *)
    TrueVal*        = 1;      (* compiler-internal value of TRUE *)
    NilVal*          = 0;      (* compiler-internal value of constant NIL *)

                (* See MaxSysFlag *)
    CCallVal* = 1; (* C calling convention; parms are right to left; caller pops stack *)
    StdCallVal* = 2; (* SYSTEM.STDCALL procedure modifier; parms are right to left; callee pops *)

    InitialNodeRef*  = -1;      (* value used to initialize node reference counter *)

  CONST (* compiler code generation options *)
    CGInitTypeDescriptors*  = TRUE;  (* could also be done by module loader *)
    CGInitImportedUnits*    = FALSE; (* TRUE => compiler generates code to init imports; FALSE => loader inits imports *)
    CGInitPointersGlobal*    = TRUE;  (* could also be done by module loader *)
    CGInitPointersLocal* = TRUE; (* should be always enabled for GC *)

  CONST (* compiler options *)
    InxChk*          = IO.InxChk;      (* generate index checking code *)
    OvflChk*        = IO.OvflChk;      (* generate overflow-checks *)
    RanChk*          = IO.RanChk;      (* generate range checking *)
    TypChk*          = IO.TypChk;      (* generate implicit type-guards *)
    NewSF*          = IO.NewSF;      (* allow new symbol file *)
    ExtSF*          = IO.ExtSF;      (* allow extended symbol file *)
    PtrInit*        = IO.PtrInit;      (* generate initializated pointers *)
    Assert*          = IO.Assert;      (* do not generate assertions *)
    FindPC*          = IO.FindPC;      (* find address of runtime error *)
    OptPtrChk*    = IO.OptPtrChk; (* NIL pointer deref check (explicit & type guard) *)
    OptDumpNode* = IO.OptDumpNode; (* when enabled, dumps out the AST *)
    OptBanner* = IO.OptBanner ; (* OptBanner IN options => print banner & exit *)
    OptHashStats* = IO.OptHashStats; (* HashStats IN options => print hash table statistics *)
    DefaultOptions* = IO.DefaultOptions;
    
  CONST (* Symbol File Imports *)
    MaxImports*      = 31;

  CONST
    DefaultFP*      = 0;        (* default finger print seed *)
    MaxHdFld*        = 512;      (* max hidden fields in a single module *)

  VAR
    optNewSF*, optFindPC*, optExtSF* : BOOLEAN;

  VAR
    MinReal-, MaxReal-: REAL;
    MinLReal-, MaxLReal-: LONGREAL;
    noerr-: BOOLEAN;  (* no error found until now *)
    eofSF- : BOOLEAN;
    options- : SET;    (* command line compiler options *)

  CONST
    RefPointTag* = 097X;
    
  CONST
    SFext      = ".Sym";
    RFext      = ".Ref";
    OFext    = ".Obj";
    SFtag      = 0FBX;  (* SKL symbol file tag *)
    SFversion = "0";
    OFversion  = 11161967H; (* SKL 32-bit+ *)
    OFtag      = 0F8320000H;  (* SKL 32-bit object file tag *)

  VAR
    LRealPat: RECORD L, H: LONGINT END ;
    errpos*: LONGINT;  (* last position error in source file *)

  (* ------------------------- Scanner Input ------------------------- *)

  PROCEDURE Get*(VAR ch: CHAR);  (* read next character from source text, Eot if no more *)
  BEGIN IO.Get(ch);
  END Get;

  PROCEDURE GetCurrentSourcePos*(VAR pos : LONGINT);
  BEGIN IO.GetCurrentSourcePos(pos);
  END GetCurrentSourcePos;
  
  PROCEDURE OpenSource(FileInfo : SourceInfo);
  BEGIN IO.OpenSource(FileInfo, noerr);
  END OpenSource;

  PROCEDURE  CloseSource*(FileInfo : SourceInfo);
  BEGIN IO.CloseSource(FileInfo);
  END CloseSource;

  (* ------------------------- Log Output ------------------------- *)
  PROCEDURE LogWSet*(s : SET);
  BEGIN  IO.LogWSet(s);
  END LogWSet;

  PROCEDURE LogWBool*(b : BOOLEAN);
  BEGIN IO.LogWBool(b);
  END LogWBool;

  PROCEDURE LogW*(ch : CHAR);
  BEGIN IO.LogW(ch);
  END LogW;

  PROCEDURE LogWStr*(s : ARRAY OF CHAR);
  BEGIN IO.LogWStr(s);
  END LogWStr;

  PROCEDURE LogWNum*(x, digits : LONGINT);
  BEGIN IO.LogWNum(x, digits);
  END LogWNum;

  PROCEDURE LogWHex*(x : LONGINT);
  BEGIN IO.LogWHex(x);
  END LogWHex;

  PROCEDURE LogWPtr*(x : SYSTEM.PTR);
  BEGIN
    IF x = NIL THEN LogWStr("NIL");
    ELSE LogWHex(SYSTEM.VAL(LONGINT, x));
    END;
  END LogWPtr;

  PROCEDURE LogWReal*(x : REAL);
  BEGIN LogWHex(SYSTEM.VAL(LONGINT, x));
  END LogWReal;
  
  PROCEDURE LogWLReal*(x : LONGREAL);
    VAR lo, hi : LONGINT;
  BEGIN
    SYSTEM.GET(SYSTEM.ADR(x), lo); SYSTEM.GET(SYSTEM.ADR(x) + 4, hi);
    LogWHex(lo); LogW(' '); LogWHex(hi);
  END LogWLReal;
  
  PROCEDURE LogWLn*;
  BEGIN IO.LogWLn;
  END LogWLn;

  PROCEDURE err*(n: INTEGER);
  BEGIN IO.err(n, noerr);
  END err;
  
  
  PROCEDURE internal*(ch : CHAR; i : INTEGER);
    VAR curpos : LONGINT;
  BEGIN
    IO.GetCurrentSourcePos(curpos);
    IO.LogWLn;
    IO.LogWStr("internal error ");
    IO.LogW(ch);
    IO.LogWNum(i, 1);
    IO.LogWStr("  pos ");
    IO.LogWNum(curpos, 4);
    IO.LogWLn;
    HALT(135);
  END internal;

  PROCEDURE NotReached*(s : ARRAY OF CHAR);
  BEGIN
    LogWStr("Not reached: ");
    LogWStr(s);
    LogWLn;
    internal(':', 1117);
  END NotReached;


  PROCEDURE SetSourceTextPos*(pos : LONGINT);
  BEGIN IO.SetSourceTextPos(pos);
  END SetSourceTextPos;

  (* ------------------ Object / Reference File ------------------ *)

  PROCEDURE RefW*(ch: CHAR);
  BEGIN IO.RefW(ch);
  END RefW;

  PROCEDURE RefWNum*(i: LONGINT);
  BEGIN IO.RefWNum(i);
  END RefWNum;
  
  PROCEDURE ObjW*(ch: CHAR);
  BEGIN IO.ObjW(ch);
  END ObjW;

  PROCEDURE ObjWNum*(i: LONGINT);
  BEGIN IO.ObjWNum(i);
  END ObjWNum;

  PROCEDURE ObjWLInt*(i: LONGINT);
  BEGIN IO.ObjWLInt(i);
  END ObjWLInt;

  PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
  BEGIN IO.ObjWBytes(bytes, n);
  END ObjWBytes;

  PROCEDURE NewRefObj*(VAR modName: ARRAY OF CHAR);
  BEGIN IO.NewRefObj(modName, OFext, RFext, OFtag, OFversion, noerr);
  END NewRefObj;

  PROCEDURE DeleteRefObj*;
  BEGIN IO.DeleteRefObj;
  END DeleteRefObj;

  (* !! this should be changed to take a structure and then the structure size can change w/o changing this signature *)
  PROCEDURE RegisterRefObj*(nofexp, nofprv, nofdesc, nofcom, nofptr, nofhlp, noffix: LONGINT);
    VAR header : IO.ObjHeader;
  BEGIN
    header.nofexp := nofexp; header.nofprv := nofprv; header.nofdesc := nofdesc;
    header.nofcom := nofcom; header.nofptr := nofptr; header.nofhlp := nofhlp; header.noffix := noffix;
    IO.RegisterRefObj(header);
  END RegisterRefObj;

  PROCEDURE SetObjModule*(mod : ARRAY OF CHAR); (* pre: LEN(mod) <= LEN(objmod) *)
  BEGIN IO.SetObjModule(mod);
  END SetObjModule;

  PROCEDURE SetObjName*(name : ARRAY OF CHAR); (* pre: LEN(name) <= LEN(objname) *)
  BEGIN IO.SetObjName(name);
  END SetObjName;

  (* ------------------ Symbol File ------------------ *)

  PROCEDURE SymWCh*(ch : CHAR);
  BEGIN IO.SymWCh(ch);
  END SymWCh;

  PROCEDURE SymWInt*(i : LONGINT);
  BEGIN IO.SymWInt(i);
  END SymWInt;

  PROCEDURE SymWSet*(s : SET);
  BEGIN IO.SymWSet(s);
  END SymWSet;

  PROCEDURE SymWReal*(f : REAL);
  BEGIN IO.SymWReal(f);
  END SymWReal;

  PROCEDURE SymWLReal*(d : LONGREAL);
  BEGIN IO.SymWLReal(d);
  END SymWLReal;

  PROCEDURE RegisterNewSym*;
  BEGIN IO.RegisterNewSym;
  END RegisterNewSym;

  PROCEDURE DeleteNewSym*;
  BEGIN IO.DeleteNewSym;
  END DeleteNewSym;
  
  PROCEDURE DiscardNewSym*;
  BEGIN IO.DiscardNewSym;
  END DiscardNewSym;

  PROCEDURE NewSym*(modName : ARRAY OF CHAR);
  BEGIN IO.NewSym(modName, SFext, SFtag, SFversion, noerr);
  END NewSym;

  PROCEDURE SymRCh*(VAR x : CHAR);
  BEGIN IO.SymRCh(x, eofSF);
  END SymRCh;

  PROCEDURE SymRInt*(VAR x : LONGINT);
  BEGIN IO.SymRInt(x, eofSF);
  END SymRInt;

  PROCEDURE SymRSet*(VAR x : SET);
  BEGIN IO.SymRSet(x, eofSF);
  END SymRSet;

  PROCEDURE SymRReal*(VAR x : REAL);
  BEGIN IO.SymRReal(x, eofSF);
  END SymRReal;

  PROCEDURE SymRLReal*(VAR x : LONGREAL);
  BEGIN IO.SymRLReal(x, eofSF);
  END SymRLReal;

  PROCEDURE OldSym*(modName : ARRAY OF CHAR; VAR done : BOOLEAN);
  BEGIN IO.OldSym(modName, SFext, SFtag, SFversion, done);
  END OldSym;

  PROCEDURE CloseOldSym*;
  BEGIN IO.CloseOldSym;
  END CloseOldSym;

  PROCEDURE InitSourceInfoOptions*(VAR info : SourceInfo);
  BEGIN IO.InitSourceInfoOptions(info);
  END InitSourceInfoOptions;
  
  PROCEDURE GetSourceInfo*(VAR FileInfo : SourceInfo);
  BEGIN IO.GetSourceInfo(FileInfo, noerr);
  END GetSourceInfo;

  (* ------------------ Real / Longreal ------------------ *)
  PROCEDURE ConvertReal*(x : LONGREAL; long : BOOLEAN; VAR lo, hi : LONGINT);
    VAR r : REAL;
  BEGIN
    IF long THEN SYSTEM.GET(SYSTEM.ADR(x), lo); SYSTEM.GET(SYSTEM.ADR(x) + 4, hi);
    ELSE r := SHORT(x); lo := SYSTEM.VAL(LONGINT, r);
    END;
  END ConvertReal;

  (* ------------------ Fingerprinting ------------------ *)

  PROCEDURE FPrint*(VAR fp : LONGINT; val : LONGINT);
  BEGIN  fp := SYSTEM.ROT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, fp) / SYSTEM.VAL(SET, val)), 1);
  END FPrint;

  PROCEDURE  FPrintSet*(VAR fp : LONGINT; val : SET);
  BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, val))
  END FPrintSet;

  PROCEDURE  FPrintReal*(VAR fp : LONGINT; val : REAL);
  BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, val))
  END FPrintReal;

  PROCEDURE  FPrintLReal*(VAR fp : LONGINT; val : LONGREAL);
    VAR l, h: LONGINT;
  BEGIN SYSTEM.GET(SYSTEM.ADR(val), l); SYSTEM.GET(SYSTEM.ADR(val)+4, h); FPrint(fp, l); FPrint(fp, h)
  END FPrintLReal;

  (* ------------------ Address/Value alignment ------------------ *)

  PROCEDURE Align*(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    CASE align OF
    | 1: (* alignment always ok *)
    | 2: INC(offset, (-offset) MOD 2)
    | 4: INC(offset, (-offset) MOD 4)
    | 8: INC(offset, (-offset) MOD 8)
    END
  END Align;
  
  PROCEDURE NegAlign*(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    CASE align OF
    |  1: (* alignment always ok *)
    | 2: DEC(offset, offset MOD 2)
    | 4: DEC(offset, offset MOD 4)
    | 8: DEC(offset, offset MOD 8)
    END
  END NegAlign;

  (* Hashing; same as IE.FPrintId *)
  (* The tenet of the hash function is to return the largest hash value possible.  it will be mapped into a lower
  range by the client of the function.  This allows tables of varying size w/o impacting the function.
  *)
  PROCEDURE Hash*(name : ARRAY OF CHAR) : LONGINT;
    VAR i, val : LONGINT; ch : CHAR;

    PROCEDURE FPrint(VAR fp : LONGINT; val : LONGINT);
      VAR x : LONGINT;
    BEGIN IF ODD(val) THEN x := fp + val; ELSE x := fp - val; END;
      fp := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ROT(x, -1)) / SYSTEM.VAL(SET, val));
    END FPrint;

  BEGIN val := 0; i := 0; ch := name[0]; WHILE ch # 0X DO FPrint(val, ORD(ch)); INC(i); ch := name[i]; END; RETURN val;
  END Hash;


  PROCEDURE GetLRealHalves*(lr : LONGREAL; VAR lo, hi : LONGINT);
  BEGIN
    ASSERT(SIZE(LONGINT) + SIZE(LONGINT) = SIZE(LONGREAL));
    SYSTEM.MEMR(SYSTEM.ADR(lr), 0, lo);
    SYSTEM.MEMR(SYSTEM.ADR(lr), SIZE(LONGINT), hi);
  END GetLRealHalves;


  PROCEDURE ModuleBegin*(FileInfo : SourceInfo);
  BEGIN noerr := TRUE;
    IO.ModuleBegin(FileInfo);
    options := FileInfo.options;
    optNewSF := NewSF IN options;
    optFindPC :=FindPC IN options;
    optExtSF := optNewSF OR (ExtSF IN options);
    OpenSource(FileInfo);
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN IO.ModuleEnd;
  END ModuleEnd;

  PROCEDURE InitRealPatterns;
    VAR i : LONGINT;

    PROCEDURE SetLongReal(VAR lr : LONGREAL; lo, hi : LONGINT);
    BEGIN SYSTEM.MEMW(SYSTEM.ADR(lr), 0, lo); SYSTEM.MEMW(SYSTEM.ADR(lr), SIZE(LONGINT), hi);
    END SetLongReal;

  BEGIN
    i := MaxRealPat; MaxReal := SYSTEM.VAL(REAL, i); i := MinRealPat; MinReal := SYSTEM.VAL(REAL, i);
    SetLongReal(MinLReal, MinLRealPatL, MinLRealPatH); SetLongReal(MaxLReal, MaxLRealPatL, MaxLRealPatH);    
  END InitRealPatterns;

  (* returns number of characters in S, not including the 0X *)
  PROCEDURE Length*(s : ARRAY OF CHAR) : INTEGER;
    VAR i : INTEGER; ch : CHAR;
  BEGIN i := -1; REPEAT INC(i); ch := s[i]; UNTIL ch = 0X; RETURN i;
  END Length;

BEGIN InitRealPatterns; noerr := TRUE;
END SKLMD.

