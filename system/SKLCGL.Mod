MODULE SKLCGL; (* Code Generation (low-level) for Intel 80x86 *)
(* XXX ensure labellist and fixuplist are set to NIL at end of compilation *)
IMPORT
  SYSTEM,
  ST:=SKLST,
  OPS:=SKLOS,
  OPM:=SKLMD,
  EL:=SKLERR,
  IE:=SKLIE;

  CONST (* segment types *)
    segUndef* = -1;
    segCode* = 0;
    segConst* = 1;
    segCase* = 2;  (* case jump tables *)
    segData* = 3;
    segExport* = 4; (* exported entry points *)
    segCommand* = 5; (* exported commands *)
    segTypeDesc* = 6; (* raw type descriptor data *)
    segTDesc* = 7; (* segment of type descriptor pointers *)

  CONST (* alignment types *)
    AlignProc* = 4;
    AlignJmp* = 1;

  CONST (* parameterization *)
    MaxCode = 96000;
    MaxConst = 15000;
    MaxTypeDesc = 5000;
    MaxCase = 5000; (* 97.08.10: should be: OPM.MaxCaseRange * SIZE(LONGINT) and a new table should be allocated for each case *)
    MaxExport = 128;

  CONST (* SKL Instruction Opcode class (oc) & Opcode (opc) *)
    ocGENREG*  = 0;
    opcADD* = 0;
    opcSUB* = 1;
    opcMUL* = 2;
    opcDIV* = 3;
    opcMOD* = 4;
    opcCMP* = 5;
    opcABS* = 6;

    ocINTREG*    = 1;   (* <mnemonic> R0, R1, Rd *)
    opcAND*      = 0;
    opcASH*      = 1;
    opcBITSET*   = 2;
    opcCMPS*     = 3;
    opcLSH*      = 4;
    opcNOR*      = 5;
    opcOR*       = 6;
    opcROT*      = 7;
    opcXOR*      = 8;

    ocSIGNEXTEND* = 2;
    opcEXTB* = 0;
    opcEXTH* = 1;

    ocCONTROLREG* = 3;
    opcLCR* = 0;
    opcSCR* = 1;

    ocSYSREG*  = 4;
    opcDI*  = 0;
    opcEI*  = 1;
    opcLCC* = 2;

    ocMISC*         = 5;
    opcBREAK*    = 0;
    opcWAIT*     = 1;
    opcERET*     = 2;

    ocJRAL* = 6;

    ocBRANCH      = 7;
    opcJEQ*    = 0;
    opcJNE*    = 1;
    opcJLT*    = 2;
    opcJGE*    = 3;
    opcJLE*    = 4;
    opcJGT*    = 5;
    opcJLTU*   = 6;
    opcJGEU*   = 7;
    opcJLEU*   = 8;
    opcJGTU*   = 9;
    opcJ*      = 10;
    opcJAL*    = 11;

    comparisons* =  { opcJEQ, opcJNE,
                      opcJLT, opcJLE,
                      opcJGT, opcJGE,
                      opcJLTU, opcJGEU,
                      opcJLEU, opcJGTU };

    ocREGMEMIMM* = 8;
    opcLB*  = 0;
    opcLBU* = 1;
    opcLD*  = 2;
    opcLDI* = 3;
    opcLF*  = 4;
    opcLFI* = 5;
    opcLH*  = 6;
    opcLHU* = 7;
    opcLW*  = 8;
    opcLWI* = 9;
    opcSB*  = 10;
    opcSD*  = 11;
    opcSF*  = 12;
    opcSH*  = 13;
    opcSW*  = 14;
    opcLA*  = 15;

    ocBT*        = 9;
    opcBTRR*  = 0;                (* bt R0, R1, Rd *)
    opcBTCR*  = 1;                (* bt <const>, R1, Rd *)
    opcBTM*   = 2;                (* btm R0, (R1), Rd *)
    opcBTMI*  = 3;                (* btmi <const>, (R1), Rd *)
    opcBTMC*  = 4;                (* btmc R0, (R1), Rd *)
    opcBTMCI* = 5;                (* btmci <const>, (R1), Rd *)
    opcBTMS*  = 6;                (* btms R0, (R1), Rd *)
    opcBTMSI* = 7;                (* btmsi <const>, (R1), Rd *)

    ocSTACK*    = 10;
    opcENTER* = 0;
    opcLEAVE* = 1;
    opcPUSH*  = 2;
    opcPUSHF* = 3;
    opcPUSHD* = 4;
    opcPOP*   = 5;
    opcPOPF*  = 6;
    opcPOPD*  = 7;

    ocSET* = 11; (* Conditional set instructions; matches jump & coc *)
    opcSEQ*  = 0;
    opcSNE*  = 1;
    opcSLT*  = 2;
    opcSGE*  = 3;
    opcSLE*  = 4;
    opcSGT*  = 5;
    opcSLTU* = 6;
    opcSGEU* = 7;
    opcSLEU* = 8;
    opcSGTU* = 9;

    ocSYSTRAP* = 12; (* Systrap instructions *)
    opcTRAPASSERT* = OPM.HaltAssert;
    opcTRAPRANGE*  = OPM.HaltRange;
    opcTRAPARRAY*  = OPM.HaltArray; (* Array bound failure. *)
    opcTRAPIGUARD* = OPM.HaltIGuard;
    opcTRAPEGUARD* = OPM.HaltEGuard;
    opcTRAPCASE*   = OPM.HaltCase;
    opcTRAPFUNC*   = OPM.HaltFunc;
    opcTRAPWITH*   = OPM.HaltWith;
    OPCTRAPGUARD*  = OPM.HaltGuardCheck;
    opcTRAPNIL*    = OPM.HaltPointerCheck;
    (* 128 system traps are supported. *)

  CONST (* condition codes *)
    (* See procedure Inverted().  Condition/negated condition are related! *)

    (* Condition Code Flags:
       Z : Zero
       S : Sign
       O : Overflow
       C : Carry
    *)

    ccEQ*  = 0;  (* equal                     (ZF = 1) *)
    ccNE*  = 1;  (* not equal                 (ZF = 0) *)

    ccLT*  = 2;  (* less than                 (SF # OF) *)
    ccGE*  = 3;  (* greater or equal          (SF = OF) *)

    ccLE*  = 4;  (* less or equal             (ZF = 1) OR (SF # OF) *)
    ccGT*  = 5;  (* greater than              (ZF = 0) &  (SF = OF) *)

    ccLTU* = 6;  (* unsigned less than        (CF = 1) *)
    ccGEU* = 7;  (* unsigned greater or equal (CF = 0) *)

    ccLEU* = 8;  (* unsigned less or equal    (CF = 1 OR (ZF = 1) *)
    ccGTU* = 9;  (* unsigned greater than     (CF = 0) & (ZF = 0) *)

    ccAW* = 10; (* always; Used internally. *)
    ccNV* = 11; (* never; Used internally. *)

    ccSet* = {ccEQ,  ccNE,
              ccLT,  ccGE,
              ccLE,  ccGT,
              ccLTU, ccGEU,
              ccLEU, ccGTU,
              ccAW,  ccNV};

  CONST
    NumGReg = 32;               (* Number of integer registers. *)
    NumFReg = 32;               (* Number of REAL / LONGREAL registers. *)

  CONST
    (* DO NOT MODIFY THESE W/O CHECKING REGISTER ALLOCATION! *)

    MinRegister* = 0;
    MaxRegister* = 31;
    SFP* = 29;                  (* Stack Frame Pointer *)
    SP*  = 30;                  (* Stack Pointer *)

    RegSystem = {0,             (* R0: always zero *)
                 SFP,           (* Stack Frame pointer *)
                 SP,            (* Stack pointer *)
                 31};           (* JAL/JRAL return address *)
    RegWord* = {0..31} - RegSystem;
    IntCallerSaved = RegWord;      (* Registers, if used, that are saved
                                    * across procedure invocations. *)
    RealCallerSaved = {0..31};
    R1 = 1;                     (* R1 / F1 is the function return register. *)

  TYPE
    (* GRegInfo:
     *
     *   Use counts of general purpose registers.  0 means unused.
     *)
    GRegInfo = ARRAY NumGReg OF SHORTINT;
    FRegInfo = ARRAY NumFReg OF SHORTINT;

  TYPE (* floating point register info *)
    FRegAllocInfo = RECORD
      nofRef : SHORTINT; (* references to this register *)
      lev : SHORTINT; (* level on the stack *)
    END;

  TYPE (* register info; set of GRegInfo registers *)
    GRegSet* = SET;
    FRegSet* = SET;

  TYPE
    SavedRegInfo* = RECORD
      gReg     : GRegInfo;
      gRegFree : GRegSet;
      fReg     : FRegInfo;
      fRegFree : FRegSet;
    END;

  TYPE (* Labels *)
    Label* = POINTER TO LabelDesc;
    LabelDesc* = RECORD (* it would be nice to implement this as an
                         * open array instead of list 960830 *)
      next : Label;
      offs : LONGINT;
      seg : SHORTINT;
    END;

  TYPE (* branch info *)
    JccInfo = POINTER TO JccInfoDesc;
    JccInfoDesc = RECORD
      next : JccInfo;
      pc   : LONGINT; (* address where the jump offset begins *)
      lab  : Label;  (* destination address of the jump *)
      cc   : SHORTINT; (* condition code *)
      disp : SHORTINT; (* {1, 4} -- indicates current size of jump displacment *)
    END;


  CONST (* type decriptor offsets *)
    TBPOffset* = -4;  (* offset of TBP table in record TD *)

  CONST (* instruction flags *)
    ifScaled = 2; (* SIB byte *)
    ifMod = 3; (* mod-reg-r/m byte *)
    ifSegData = 4; (* segment relative addressing; used as RHS of instruction *)
    ifSegDisp = 5; (* segment relative addressing; used as LHS of instruction *)
    ifFreeTemps = 6; (* free temp registers after instruction output *)
    ifSymAddress = 7; (* address of (symbol) operand is to be used *)
    ifDatAddress = 8; (* address of (data) operand is to be used *)
    ifFlags = 9; (* number of instruction flags *)

  TYPE (* Instruction *)
    Systrap = RECORD
      halt  : SHORTINT;
      subcl : INTEGER;
    END;

    Instruction = RECORD
      opclass : SHORTINT;  (* bits: 31..26: opcode class. *)
      opc     : SHORTINT;  (* bits: 4..0  : opcode. *)
      Rd      : SHORTINT;  (* bits: 25..21: Destination register. *)
      R0      : SHORTINT;  (* bits: 20..16: Source register 0. *)
      R1      : SHORTINT;  (* bits: 15..11: Source register 1. *)
      bd      : SHORTINT;  (* bit : 10    : Rd bank *)
      b0      : SHORTINT;  (* bit : 9     : R0 bank *)
      b1      : SHORTINT;  (* bit : 8     : R1 bank *)
      scale   : SHORTINT;  (* bits: 7..6  : Scale factor *)
      jcc     : SHORTINT;  (* JCC conditional type. XXX needed? *)
      systrap : Systrap;   (* systrap info *)
      dataLo  : LONGINT;   (* 4 byte data following instruction *)
      dataHi  : LONGINT;   (* 4 byte data following dataLo (LONGREAL only) *)
      flags   : SET;
      sym     : ST.Symbol; (* Symbol referenced by instruction *)
      lab     : Label;     (* Label referenced by instruction *)
    END;

  CONST (* Item modes *)
    (* Variable, parameter passed by value (and dynamic arrays).
     *
     *   mode  : { Ivar, Ipar }
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : n/a
     *   td    : n/a
     *   reg   : n/a
     *   inxreg: n/a
     *   adr   : Address of described variable
     *   offset: n/a
     *   flags : { various }
     *   val   : Not used.
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : Symbol described.
     *
     *   Can change into Ivarx with the addition of an 'inxreg' register.
     *)
    Ivar*      = 00;   (* Variable.  *)
    Ipar*      = 01;   (* Procedure argument. *)


  CONST
    (* Parameter passed by address.
     *
     *   mode  : Ivarpar
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : n/a
     *   td    : n/a
     *   reg   : n/a
     *   inxreg: n/a
     *   adr   : Stack address of described variable
     *   offset: n/a
     *   flags : { various }
     *   val   : Not used.
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : Symbol described.
     *)
    Ivarpar*   = 02;   (* var parameter *)


  CONST
    (* Constant value.
     *
     *   mode  : Iconst
     *   mnolev: n/a
     *   cc    : n/a
     *   td    : n/a
     *   reg   : n/a
     *   inxreg: n/a
     *   adr   : n/a
     *   offset: n/a
     *   flags : { various }
     *   val   : constant value
     *   type  : Type of constant.
     *   jump  : n/a
     *   sym   : n/a.
     *)
    Iconst*    = 03;   (* constant *)


  CONST
    Ilproc*    = 04;   (* local procedure *)


  CONST
    Ixproc*    = 05;   (* global, exported, procedure *)


  CONST
    Icproc*    = 06;   (* code procedure *)


  CONST
    Iiproc*    = 07;   (* interrupt procedure *)


  CONST
    Itproc*    = 08;   (* type bound procedure (used for initializing TD only) *)


  CONST
    Imethod*   = 09;   (* method *)


  CONST
    (* Indexed variable or parameter.
     *
     *   This describes a variable being indexed with a register.
     *
     *   mode  : Ivarx
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : n/a
     *   td    : n/a
     *   reg   : n/a
     *   inxreg: Index register number.
     *   adr   : Address of described variable.
     *   offset: n/a
     *   flags : { various }
     *   val   : Not used.
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : Symbol described.
     *)
    Ivarx*     = 10;   (* indexed variable *)


  CONST
    Iind*      = 11;   (* indirect *)


  CONST
    Iindx*     = 12;   (* indirect indexed (unused in SKL) *)


  CONST
    (* Enregistered Value.
     *
     *   mode  : Ireg
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : n/a
     *   td    : n/a
     *   inxreg: n/a
     *   reg   : Register number.
     *   adr   : n/a
     *   offset: n/a
     *   flags : { various }
     *   val   : n/a
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : n/a
     *)
    Ireg*      = 13;   (* register *)


  CONST
    Iregi*     = 14;   (* register indirect *)


  CONST
    (* Register Indirect, indexed
     *
     *   mode  : Ireg
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : n/a
     *   td    : n/a
     *   reg   : Register number.
     *   inxreg: Index register.
     *   adr   : n/a
     *   offset: Post-indirection offset.  (XXX check validity)
     *   flags : { various }
     *   val   : Not used.
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : n/a
     *)
    Iregix*    = 15;   (* register, indirect indexed *)


  CONST
    (* Condition Code
     *
     *   mode  : Icoc
     *   mnolev: global: mnolev <= 0, local: mnolev > 0.
     *   cc    : Condition code.
     *   td    : n/a
     *   reg   : Register holding condition code flags.
     *   inxreg: n/a
     *   adr   : n/a
     *   offset: n/a
     *   flags : { various }
     *   val   : Not used.
     *   type  : Type of symbol.
     *   jump  : n/a
     *   sym   : n/a
     *)
    Icoc*      = 16;   (* condition code *)


  CONST
    Iadr*      = 17;   (* address-of (global symbols only) *)


  CONST
    Imodes*    = 18;   (* must be <= MAX(SET) *)

  CONST (* Item flags XXX these should have a prefix *)
    super* = 0;  (* super call *)
    common* = 1; (* common designator; n := n op expr *)

  TYPE
    TDTarget* = RECORD
      mode* : SHORTINT; (* {-1, Iregi} (Item Modes) *)
      reg*  : LONGINT;  (* Register holding TD address *)
    END;

  TYPE
    CondJump* = RECORD
      true*  : Label;
      false* : Label;
    END;

  TYPE (* Item *)
    Item* = RECORD
      mode*     : SHORTINT; (* Item Modes *)
      mnolev*   : SHORTINT; (* module (< 0) / lexical scoping (> 0) *)
      cc*       : SHORTINT; (* Condition code. *)
      td*       : TDTarget; (* Type Descriptor *)
      reg*      : LONGINT;  (* Register or method number. *)
      methno*   : LONGINT;  (* Method number *)
      inxreg*   : LONGINT;  (* Index Register *)
      adr*      : LONGINT;  (* Address (combine with offset) *)
      offset*   : LONGINT;  (* Post-indirection offset. *)
      flags*    : SET;
      val*      : ST.ConstValDesc;
      type*     : ST.Type;
      jump*     : CondJump;
      sym*      : ST.Symbol;
    END;

  CONST (* Fixup modes *)
    FixAbs* = 0; (* absolute address of fixup-to item *)
    FixRel* = 1; (* relative address of fixup-to item;
                  * rel = next instruction addres - fixup-to address *)
    FixBlk* = 2; (* allocation block size; dependent upon Heap management implementation *)

  (*
    inv: mode IN {FixAbs, FixRel} & lab = NIL & sym = NIL => invalid
    inv: mode IN {FixAbs, FixRel} & lab # NIL & sym # NIL => invalid
    inv: mode IN {FixAbs, FixRel} & lab = NIL             => fixup target is symbol
    inv: mode IN {FixAbs, FixRel} & sym = NIL             => fixup target is targ0
    inv: mode IN {FixBlk}                                 => lab = NIL; sym = NIL; doffs = record size

    Two possible ways of ordering fixups are readily apparent.
     1) order in a simple linked list
     2) order all fixups which have the same fixup target as a group
        (i.e. all reference to M0.var in a group)

     1 is selected for simplicity

     If a fixup is being made to an imported symbol, the adr field
     gets transformed into an index into the Use block. This index
     will be used to find the actual runtime address of the symbol to
     which the fixup is being made.  (This is done because external
     symbols do not have valid addresses, as they are resolved at load
     time) XXX document this new fixup scheme. 97.01.01

     FixBlk fixups are used only for record type descriptors `record
     block size' fixups.  They are meant to decouple the compiler from
     the physical heap allocator used (except that blocks are
     allocated (at a minimum) on 16-byte boundaries.

 *)
  TYPE (* Fixup info *)
    Fixup* = POINTER TO FixupDesc;
    FixupDesc* = RECORD
      next : Fixup;
      lab : Label;
      sym : ST.Symbol;
      toffs : LONGINT; (* (target offs) in segment where fixup is applied *)
      doffs : LONGINT; (* (destination offs) in segment to which fixup refers *)
      segment : SHORTINT; (* to which the fixup is applied *)
      mode : SHORTINT; (* type of fixup *)
    END;

  TYPE
    FixupHelperLocation = POINTER TO FixupHelperLocDesc;
    FixupHelperLocDesc* = RECORD
      next : FixupHelperLocation;
      offs : LONGINT;
    END;

    FixupHelper = POINTER TO FixupHelperDesc;
    FixupHelperDesc = RECORD
      next : FixupHelper;
      loc : FixupHelperLocation;
      module, function : OPS.Name;
    END;

  CONST (* Object File tags *)
    Econst    = 1X;
    Etype     = 2X;
    Evar      = 3X;
    Exproc    = 4X;
    Eiproc    = 4X;
    Ecproc    = 5X;
    Estruc    = 6X;
    Erectd    = 8X;
    Edarraytd = 9X;
    Earraytd  = 0AX;

    Uconst   = 1X;
    Utype    = 2X;
    Uvar     = 3X;
    Uxproc   = 4X;
    Uiproc   = 4X;
    Ucproc   = 5X;
    Upbstruc = 6X;
    Upvstruc = 7X;
    Urectd   = 8X;
    Udarrtd  = 9X;
    Uarrtd   = 0AX;

    Trec    = 1X;
    Tdarray = 2X;
    Tarray  = 3X;

  TYPE
    ObjScopeInfo = RECORD (ST.ProcessScopeInfo)
      nofexp, nofprv, nofdesc, nofcom : INTEGER;
      nofptr, nofhlp, noffix : INTEGER; (* written to Obj file as LONGINT *)
      PtrTab : ARRAY OPM.MaxGlobalPointers + 1 OF LONGINT;
      ComTab : ARRAY OPM.MaxCommands OF ST.Symbol;
      useIndex : LONGINT; (* Used to set address of external-used
                           * symbols for fixup resolution during object
                           * loading. *)
    END;

  TYPE (* used for finding new methods when outputting the object file *)
    MethodScopeInfo = RECORD (ST.ProcessScopeInfo)
      nofnewmeth : INTEGER;
      tab : ARRAY 256 OF ST.SymbolProc;
    END;

  TYPE
    ObjStr = POINTER TO ObjStrDesc;
    ObjStrDesc = RECORD
      next : ObjStr;
      i : LONGINT;
      str : ST.SymbolName;
    END;

  CONST
    LProcParmOffset* = 12; (* Offset in stack of last pushed parameter --
                            * local procedures.  A static link is present on local
                            * procedures. *)
    XProcParmOffset* = 8;  (* Offset in stack of last pushed parameter for
                            * global procedures *)

  VAR
    pc-         : LONGINT;
    constx-     : LONGINT;
    typedescx-  : LONGINT;
    casex-      : LONGINT;
    exportx-    : LONGINT;
    level*      : SHORTINT;  (* nesting level *)
    CaseTab     : POINTER TO ARRAY MaxCase OF BOOLEAN; (* index with casex *)
    CodeTab     : POINTER TO ARRAY MaxCode OF SYSTEM.BYTE; (* index with pc *)
    ConstTab    : POINTER TO ARRAY MaxConst OF SYSTEM.BYTE; (* index with constx *)
    TypeDescTab : POINTER TO ARRAY MaxTypeDesc OF SYSTEM.BYTE; (* index with typedescx *)

    (* Since ExportTab is only fixups, it can be totally created by the loader,
     * but the compiler creates it in place for now.
     *)
    ExportTab : ARRAY MaxExport OF LONGINT; (* exported procedure entry points *)
    LabelList : Label;
    FixupList : Fixup;
    FixupHelperList : FixupHelper;
    JccFixupList : JccInfo;
    GReg : GRegInfo;
    GRegTemp-, GRegFree- : GRegSet;
    FReg : FRegInfo;
    FRegFree : FRegSet;

  VAR
    (* XXX
     *
     *  TypeOfGReg is unused, but if this variable not present in x86
     *  version of SKL, the offsets for the data in the module
     *  initialization function are very large negative numbers, and
     *  this causes a SEGV in the x86 system.  It is a codegen defect
     *  in the x86 code generator.
     *)
    TypeOfGReg : ARRAY 24 OF ST.Type;
    ObjectStrings : ObjStr;

    (* Segment in which corresponding global symbol type resides
     * used for only allocating physical (not pseudo (i.e. type descriptors))
     * variables into the data segment
     *)
    AllocSeg- : ARRAY ST.nofSymbols OF SHORTINT;


  PROCEDURE ^ PutOpBytes(opsize : INTEGER; opc : LONGINT);
  PROCEDURE ^ PutByte*(op : SYSTEM.BYTE);
  PROCEDURE ^ PutStack*(opc : SHORTINT; VAR x : Item);
  PROCEDURE ^ PutGenReg*(opc : SHORTINT; VAR r0, r1, dest : Item);
  PROCEDURE ^ Jmp*(VAR lab : Label);


  (* InitItem: Initialize all elements of Item to invalid values.
   * Invalid values are used to guarantee that the fields are
   *  initialized properly before use. *)
  PROCEDURE InitItem*(VAR x : Item);
  BEGIN
    x.mode       := -1;
    x.td.mode    := -1;
    x.mnolev     := 0;
    x.cc         := -1;
    x.reg        := OPM.UndefReg;
    x.adr        := OPM.UndefAdr;
    x.offset     := OPM.UndefAdr;
    x.inxreg     := -1;
    x.td.reg     := -1;
    x.flags      := {};
    x.type       := ST.undftyp;
    x.jump.true  := NIL;
    x.jump.false := NIL;
    x.sym        := NIL;
  END InitItem;

  PROCEDURE DumpItem*(VAR x : Item; header : ARRAY OF CHAR);
    PROCEDURE LogMode(m : INTEGER);
    BEGIN
      CASE m OF
      | Ivar: OPM.LogWStr("Ivar");
      | Ipar: OPM.LogWStr("Ipar");
      | Ivarpar: OPM.LogWStr("Ivarpar");
      | Iconst: OPM.LogWStr("Iconst");
      | Ilproc: OPM.LogWStr("Ilproc");
      | Ixproc: OPM.LogWStr("Ixproc");
      | Icproc: OPM.LogWStr("Icproc");
      | Iiproc: OPM.LogWStr("Iiproc");
      | Itproc: OPM.LogWStr("Itproc");
      | Imethod: OPM.LogWStr("Imethod");
      | Ivarx: OPM.LogWStr("Ivarx");
      | Iind: OPM.LogWStr("Iind");
      | Iindx: OPM.LogWStr("Iindx");
      | Ireg: OPM.LogWStr("Ireg");
      | Iregi: OPM.LogWStr("Iregi");
      | Iregix: OPM.LogWStr("Iregix");
      | Icoc: OPM.LogWStr("Icoc");
      | Iadr: OPM.LogWStr("Iadr");
      | Imodes: OPM.LogWStr("CGH.Itos");
      ELSE
        OPM.LogWStr("(invalid mode) "); OPM.LogWNum(x.mode, 4);
      END;
    END LogMode;

  BEGIN
    OPM.LogWLn; OPM.LogWStr("+++++ CGL.Item: "); OPM.LogWStr(header); OPM.LogWLn;
    OPM.LogWStr("  [level]: "); OPM.LogWNum(level, 4); OPM.LogWLn;
    OPM.LogWStr("  mode   : "); LogMode(x.mode); OPM.LogWLn;
    OPM.LogWStr("  mnolev : "); OPM.LogWNum(x.mnolev, 4); OPM.LogWLn;
    IF (x.reg >= MinRegister) & (x.reg <= MaxRegister) THEN
      OPM.LogWStr("  reg    : "); OPM.LogWNum(x.reg, 4);
      IF x.type.form IN ST.RealSet THEN
        OPM.LogWStr("  refs: "); OPM.LogWNum(FReg[x.reg], 4);
        OPM.LogWStr("  free: "); OPM.LogWSet(FRegFree);
      ELSE
        OPM.LogWStr("  refs: "); OPM.LogWNum(GReg[x.reg], 4);
        OPM.LogWStr("  free: "); OPM.LogWSet(GRegFree);
      END;
    ELSE
      OPM.LogWStr("  reg    : n/a");
    END;
    OPM.LogWLn;
    OPM.LogWStr("  methno : ");
    IF x.mode = Imethod THEN
      OPM.LogWNum(x.methno, 4);
    ELSE
      OPM.LogWStr("  n/a");
    END;
    OPM.LogWLn;
    OPM.LogWStr("  cc     : "); OPM.LogWNum(x.cc, 4); OPM.LogWLn;
    OPM.LogWStr("  adr    : "); OPM.LogWNum(x.adr, 4); OPM.LogWLn;
    OPM.LogWStr("  offset : "); OPM.LogWNum(x.offset, 4); OPM.LogWLn;
    OPM.LogWStr("  inxreg : "); OPM.LogWNum(x.inxreg, 4); OPM.LogWLn;
    OPM.LogWStr("  flags  : "); OPM.LogWSet(x.flags); OPM.LogWLn;
    OPM.LogWStr("  val    : ");
    OPM.LogW("{");
    OPM.LogWStr("ext: ");
    IF x.val.ext # NIL THEN OPM.LogWStr(x.val.ext^);
    ELSE OPM.LogWStr("NIL");
    END;
    OPM.LogWStr("| i0: "); OPM.LogWNum(x.val.i0, 4);
    OPM.LogWStr("| i1: "); OPM.LogWNum(x.val.i1, 4);
    OPM.LogWStr("| set: "); OPM.LogWSet(x.val.set);
    OPM.LogWStr("| real: "); OPM.LogWLReal(x.val.real);
    OPM.LogW("}"); OPM.LogWLn;
    OPM.LogWStr("  type   : ");
    IF x.type # NIL THEN
      OPM.LogWNum(x.type.form, 4);
    ELSE
      OPM.LogWStr("NIL");
    END;
    OPM.LogWLn;
    OPM.LogWStr("  Tjmp   : "); OPM.LogWPtr(x.jump.true); OPM.LogWLn;
    OPM.LogWStr("  Fjmp   : "); OPM.LogWPtr(x.jump.false); OPM.LogWLn;
    OPM.LogWStr("  sym    : ");
    IF x.sym # NIL THEN
      OPM.LogWStr("| kind: ");  OPM.LogWNum(x.sym.kind, 4);
      OPM.LogWStr("| mnolev: "); OPM.LogWNum(x.sym.mnolev, 4);
      OPM.LogWStr("| flags: "); OPM.LogWSet(x.sym.flags);
      OPM.LogWStr("| adr: "); OPM.LogWNum(x.sym.adr, 4);
      OPM.LogWStr("| name: "); OPM.LogWStr(x.sym.name^);
    ELSE
      OPM.LogWStr("NIL");
    END;
    OPM.LogWLn;

    OPM.LogWStr("  td.mode: "); LogMode(x.td.mode); OPM.LogWLn;
    OPM.LogWStr("  td.reg : "); OPM.LogWNum(x.td.reg, 4); OPM.LogWLn;
  END DumpItem;


  PROCEDURE DumpInstruction(VAR inst : Instruction; label : ARRAY OF CHAR);
  BEGIN
    OPM.LogWLn; OPM.LogWStr("+++++ ");
    OPM.LogWHex(pc); OPM.LogWStr(" CGL.Instruction: "); OPM.LogWStr(label); OPM.LogWLn;
    OPM.LogWStr("  [level]: "); OPM.LogWNum(level, 4); OPM.LogWLn;
    OPM.LogWStr("  opclass: ");
    CASE inst.opclass OF
    | 0: OPM.LogWStr("ocGENREG");
    | 1: OPM.LogWStr("ocINTREG");
    | 2: OPM.LogWStr("ocSIGNEXTEND");
    | 3: OPM.LogWStr("ocCONTROLREG");
    | 4: OPM.LogWStr("ocSYSREG");
    | 5: OPM.LogWStr("ocMISC");
    | 6: OPM.LogWStr("ocJRAL");
    | 7: OPM.LogWStr("ocBRANCH");
    | 8: OPM.LogWStr("ocREGMEMIMM");
    | 9: OPM.LogWStr("ocBT");
    | 10: OPM.LogWStr("ocSTACK");
    | 11: OPM.LogWStr("ocSET");
    | 12: OPM.LogWStr("ocSYSTRAP");
    ELSE
      OPM.internal('L', 6500);
    END;
    OPM.LogWLn;
    OPM.LogWStr("  op     : "); OPM.LogWNum(inst.opc, 4); OPM.LogWLn;
    OPM.LogWStr("  Rd     : "); OPM.LogWNum(inst.Rd, 4); OPM.LogWLn;
    OPM.LogWStr("  R0     : "); OPM.LogWNum(inst.R0, 4); OPM.LogWLn;
    OPM.LogWStr("  R1     : "); OPM.LogWNum(inst.R1, 4); OPM.LogWLn;
    OPM.LogWStr("  bd     : "); OPM.LogWNum(inst.bd, 4); OPM.LogWLn;
    OPM.LogWStr("  b0     : "); OPM.LogWNum(inst.b0, 4); OPM.LogWLn;
    OPM.LogWStr("  b1     : "); OPM.LogWNum(inst.b1, 4); OPM.LogWLn;
    OPM.LogWStr("  scale  : "); OPM.LogWNum(inst.scale, 4); OPM.LogWLn;
    OPM.LogWStr("  jcc    : "); OPM.LogWNum(inst.jcc, 4); OPM.LogWLn;
    OPM.LogWStr("  systrap: "); OPM.LogWLn;
    OPM.LogWStr("   halt  : "); OPM.LogWNum(inst.systrap.halt, 4); OPM.LogWLn;
    OPM.LogWStr("   subcl : "); OPM.LogWNum(inst.systrap.subcl, 4); OPM.LogWLn;
    OPM.LogWStr("  dataLo : "); OPM.LogWNum(inst.dataLo, 4); OPM.LogWLn;
    OPM.LogWStr("  dataHi : "); OPM.LogWNum(inst.dataHi, 4); OPM.LogWLn;
    OPM.LogWStr("  sym    : ");
    IF inst.sym # NIL THEN
      OPM.LogWStr("| kind: ");  OPM.LogWNum(inst.sym.kind, 4);
      OPM.LogWStr("| mnolev: "); OPM.LogWNum(inst.sym.mnolev, 4);
      OPM.LogWStr("| flags: "); OPM.LogWSet(inst.sym.flags);
      OPM.LogWStr("| adr: "); OPM.LogWNum(inst.sym.adr, 4);
      OPM.LogWStr("| name: "); OPM.LogWStr(inst.sym.name^);
    ELSE
      OPM.LogWStr("NIL");
    END;
    OPM.LogWLn;
    OPM.LogWStr("  lab    : ");
    IF inst.lab # NIL THEN
      OPM.LogWStr("| offs: ");  OPM.LogWNum(inst.lab.offs, 4);
      OPM.LogWStr("| seg: ");  OPM.LogWNum(inst.lab.seg, 4);
    ELSE
      OPM.LogWStr("NIL");
    END;
    OPM.LogWLn;
    OPM.LogWStr("  flags  : "); OPM.LogWSet(inst.flags); OPM.LogWLn;
  END DumpInstruction;


  PROCEDURE ReserveSystemRegs;
  BEGIN
    GReg[0]  := 1;   (* R0 is always 0. *)
    GReg[31] := 1;   (* R31 is used by hardware for return address. *)
  END ReserveSystemRegs;

  PROCEDURE ReserveABIRegs;
  BEGIN
    (* Reserve registers that should not be allocated
     * since they are used by the ABI *)
  END ReserveABIRegs;

  PROCEDURE GRegFreeAll;
      VAR i : INTEGER;
  BEGIN
    i := 0;
    WHILE i < LEN(GReg) DO
      GReg[i] := 0;
      INC(i);
    END;
    ReserveSystemRegs;
    ReserveABIRegs;
    GRegFree := RegWord;
  END GRegFreeAll;

  PROCEDURE FRegFreeAll;
      VAR i : INTEGER;
  BEGIN
    i := 0;
    WHILE i < LEN(FReg) DO
      FReg[i] := 0;
      INC(i);
    END;
    FRegFree := {MinRegister..MaxRegister};
  END FRegFreeAll;


  (* StatBegin:
   *
   *   Mark the beginning of a statement.
   *   Release all registers, so they are free to be used again.
   *
   *)
  PROCEDURE StatBegin*(pos : LONGINT);
  BEGIN
    GRegFreeAll;
    FRegFreeAll;
  END StatBegin;


  (* StatEnd:
   *
   *   Mark the beginning of a statement.
   *   Cleanup and release all registers that were used..
   *
   *)
  PROCEDURE StatEnd*(pos : LONGINT);
  BEGIN
    GRegFreeAll;
    FRegFreeAll;
  END StatEnd;


  PROCEDURE AvailableGRegs*() : SET;
  BEGIN
    RETURN GRegFree;
  END AvailableGRegs;

  PROCEDURE DumpRegisters(header  : ARRAY OF CHAR;
                          free    : SET;
                          VAR use : ARRAY OF SHORTINT);
    VAR i : INTEGER;
  BEGIN
    OPM.LogWLn;
    OPM.LogWStr("  ++++++ "); OPM.LogWStr(header); OPM.LogWLn;
    OPM.LogWStr("    Free ");  OPM.LogWSet(free); OPM.LogWLn;
    i := 0;
    WHILE i < LEN(use) DO
      OPM.LogWStr("    reg["); OPM.LogWNum(i, 4);
      OPM.LogWStr("] :");
      IF use[i] # 0 THEN
        OPM.LogWNum(use[i], 4);
      ELSE
        OPM.LogWStr("    ");
      END;
      INC(i);
      IF i MOD 4 = 0 THEN
        OPM.LogWLn;
      END;
    END;
    OPM.LogWLn;
  END DumpRegisters;


  PROCEDURE DumpRegInfo*(header : ARRAY OF CHAR);
    VAR i : INTEGER;
  BEGIN
    OPM.LogWStr("++++++ Registers "); OPM.LogWStr(header); OPM.LogWLn;
    DumpRegisters("Integer", GRegFree, GReg);
    DumpRegisters("Float", FRegFree, FReg);
  END DumpRegInfo;


  PROCEDURE RelGReg(reg : LONGINT);
  BEGIN
    (* RegSystem registers are never allocated, but they can be freely used.
     * Ignore attempts to add them back to the set of free registers. *)
    IF ~(reg IN RegSystem) THEN
      IF ~(GReg[reg] > 0) THEN
        OPM.LogWStr("Failed freeing GReg "); OPM.LogWNum(reg, 3); OPM.LogWLn;
        OPM.internal("L", 10000);
      END;
      ASSERT(GReg[reg] > 0, 200);
      DEC(GReg[reg]);
      IF GReg[reg] = 0 THEN
        INCL(GRegFree, reg);
      END;
    END;
  END RelGReg;

  PROCEDURE ReleaseGReg(r : LONGINT);
  BEGIN
    RelGReg(r);
  END ReleaseGReg;

  PROCEDURE ReleaseFReg(r : LONGINT);
  BEGIN
    IF FReg[r] > 0 THEN
      DEC(FReg[r]);
      IF FReg[r] = 0 THEN
        INCL(FRegFree, r);
      END;
    ELSE
      OPM.internal("L", 15001);
    END;
  END ReleaseFReg;

  PROCEDURE ReleaseTemp;
    VAR i : LONGINT;
  BEGIN
    i := 0;
    WHILE i <= NumGReg DO
      IF i IN GRegTemp THEN
        ReleaseGReg(i);
        EXCL(GRegTemp, i);
      END;
      INC(i);
    END;
  END ReleaseTemp;

  PROCEDURE Release*(VAR x : Item);
  BEGIN
    IF ~(x.type.form IN ST.RealSet) THEN
      CASE x.mode OF
      |  Imethod:
         ReleaseGReg(x.td.reg);

      |  Ivarx, Iindx:
         ReleaseGReg(x.inxreg);

      |  Ireg, Iregi, Icoc:
         ReleaseGReg(x.reg);

      |  Iregix:
         ReleaseGReg(x.reg);
         ReleaseGReg(x.inxreg);
      ELSE (* nop *)
      END;
    ELSE (* floating point release *)
      IF x.mode = Ireg THEN
        ReleaseFReg(x.reg);
      END;
    END;
  END Release;


  PROCEDURE UseFReg(r : LONGINT);
  BEGIN
    ASSERT(r IN {0..MAX(SET)});
    INC(FReg[r]);
    EXCL(FRegFree, r);
  END UseFReg;


  PROCEDURE UseGReg(r : LONGINT);
  BEGIN
    ASSERT(r IN RegWord);
    INC(GReg[r]);
    EXCL(GRegFree, r);
  END UseGReg;


  PROCEDURE GetReg*(VAR x : Item; regset : SET);
    VAR
      i : INTEGER;
      fr : SET;
  BEGIN
    IF regset * GRegFree = {} THEN
      OPM.err(EL.ExprTooComplex);
      fr := RegWord;
    ELSE
      fr := GRegFree;
    END;
    i := MAX(SET);
    WHILE i > 0 DO
      IF (i IN regset) & (i IN fr) THEN
        x.mode := Ireg;
        x.reg  := i;
        UseGReg(i);
        RETURN;
      END;
      DEC(i);
    END;
  END GetReg;


  PROCEDURE GetIntReg*(VAR x : Item);
  BEGIN
    GetReg(x, RegWord);
  END GetIntReg;


  PROCEDURE DoubleRef*(VAR x : Item);
  BEGIN
    IF ~(x.type.form IN ST.RealSet) THEN
      CASE x.mode OF
      |  Imethod:
         UseGReg(x.td.reg);

      |  Ivarx, Iindx:
         UseGReg(x.inxreg);

      |  Ireg, Iregi:
         UseGReg(x.reg);

      |  Iregix:
         UseGReg(x.reg);
         UseGReg(x.inxreg);
      ELSE (* nop, does not use registers *)
      END;
    ELSE
      IF x.mode = Ireg THEN
        ASSERT((x.reg >= 0) & (x.reg < LEN(FReg)));
        INC(FReg[x.reg]);
      END;
    END;
  END DoubleRef;


  PROCEDURE MarkRegSetUsed*(s : GRegSet);
    VAR i : INTEGER; x : Item;
  BEGIN
    i := 0;
    s := s - RegSystem;
    WHILE i < MAX(SET) DO
      IF i IN s THEN
        GetReg(x, {i});
      END;
      INC(i);
    END;
  END MarkRegSetUsed;


  PROCEDURE MarkRegSetFree*(s : GRegSet);
    VAR i : INTEGER; x : Item;
  BEGIN
    i := 0;
    s := s - RegSystem;
    WHILE i < MAX(SET) DO
      IF i IN s THEN
        x.type := ST.linttyp;
        x.mode := Ireg;
        x.reg := i;
        Release(x);
      END;
      INC(i);
    END;
  END MarkRegSetFree;


  PROCEDURE GetFReg*(VAR x : Item; regset : SET);
    VAR
      i : INTEGER;
      fr : SET;
  BEGIN (* fp instructions which pop stack should reassign registers XXX *)
    IF regset * FRegFree = {} THEN
      OPM.err(EL.ExprTooComplex);
      fr := {0..MAX(SET)};
    ELSE
      fr := FRegFree;
    END;

    i := MAX(SET);
    WHILE i > 0 DO
      IF (i IN regset) & (i IN fr) THEN
        x.reg  := i;
        x.mode := Ireg;
        UseFReg(i);
        RETURN;
      END;
      DEC(i);
    END;
  END GetFReg;

  PROCEDURE CompilerRegToCPUReg(r : LONGINT) : SHORTINT;
  BEGIN
    RETURN SHORT(SHORT(r));     (* SKL registers are identity.  XXX remove *)
  END CompilerRegToCPUReg;


  PROCEDURE SaveRegisters*(VAR saved : SavedRegInfo); (* returns saved *)
    VAR
      i     : SHORTINT;
      savee : SET;
      x     : Item;
      opc   : SHORTINT;
  BEGIN
    saved.gReg     := GReg;
    saved.fReg     := FReg;
    saved.gRegFree := GRegFree;
    saved.fRegFree := FRegFree;

    (* Save in-use integer registers *)
    InitItem(x);
    x.type := ST.linttyp;
    x.mode := Ireg;
    savee  := IntCallerSaved - GRegFree;
    i := 1;
    WHILE i <= MaxRegister DO
      IF i IN savee THEN
        x.reg := i;
        PutStack(opcPUSH, x);
      END;
      INC(i);
    END;

    (* Save in-use floating point registers *)
    x.type := ST.lrltyp;
    savee  := RealCallerSaved - FRegFree;
    i      := 1;
    WHILE i <= MaxRegister DO
      IF i IN savee THEN
        x.reg := i;
        PutStack(opcPUSHD, x);  (* Save LONGREAL even if only REAL. *)
        END;
      INC(i);
    END;
  END SaveRegisters;

  (* Restore registers saved over procedure invocations.
   * Sets thefunction calls; setup of proper
   * floating point register stack after a function call *)
  PROCEDURE RestoreRegisters*(VAR restore : SavedRegInfo; VAR res : Item);
    VAR
      x        : Item;
      R0       : Item;
      i        : INTEGER;
      s        : LONGINT;
      restoree : SET;
      intFree  : SET;
      realFree : SET;
      procType : ST.Procedure;

  BEGIN
    GRegFree := restore.gRegFree;
    FRegFree := restore.fRegFree;
    GReg     := restore.gReg;
    FReg     := restore.fReg;

    InitItem(R0);
    R0.mode  := Ireg;
    R0.reg   := 0;
    R0.type  := ST.linttyp;
    intFree  := GRegFree;
    realFree := FRegFree;

    IF res.type # ST.notyp THEN
      (* The 'res' argument is the  procedure ST.Type.
       *
       * ST.iproc (interrupt procedure) does not have a functional
       * return type.
       *
       *)

      IF res.type.form IN ST.RealSet THEN
        (* The return is in F1.
         * If it is not free, move F1 to another floating
         * point register so that F1 can be popped off the stack. *)
        IF ~(R1 IN FRegFree) THEN
          x      := res;
          x.mode := Ireg;
          x.reg  := R1;
          x.type := ST.lrltyp;

          GetFReg(res, {MinRegister..MaxRegister});
          PutGenReg(opcADD, R0, x, res);
        ELSE
          GetFReg(res, {1});
        END;
      ELSE
        ASSERT(res.type.form IN ST.BasicSet);
        IF ~(R1 IN GRegFree) THEN
          (* R1 is saved on the stack, but it now holds the
           * return value of a function.  Move the current value
           * to another register so it can be restored from
           * the stack. *)
          x      := res;
          x.mode := Ireg;
          x.reg  := R1;
          x.type := ST.linttyp;

          GetReg(res, RegWord);
          PutGenReg(opcADD, R0, x, res);
        ELSE
          GetReg(res, {1});
        END;
      END;
    END;

    (* Restore floating point registers. *)
    InitItem(x);
    x.mode := Ireg;
    x.type := ST.lrltyp;
    restoree := {MinRegister..MaxRegister} - realFree;

    i      := MaxRegister;
    WHILE i >= MinRegister DO (* Reverse of saving *)
      IF i IN restoree THEN
        x.reg := SHORT(i);
        PutStack(opcPOPD, x);   (* Restore LONGREAL, because it was saved that way. *)
      END;
      DEC(i);
    END;

    (* Restore integer registers. *)
    x.type   := ST.linttyp;
    i        := MaxRegister;
    restoree := {MinRegister..MaxRegister} - RegSystem - intFree;
    WHILE i >= MinRegister DO
      IF i IN restoree THEN
        x.reg := SHORT(i);
        PutStack(opcPOP, x);
      END;
      DEC(i);
    END;
  END RestoreRegisters;


  PROCEDURE NewLabel*() : Label;
    VAR l : Label;
  BEGIN
    NEW(l);
    l.offs    := OPM.UndefAdr;
    l.seg     := segUndef;
    l.next    := LabelList;
    LabelList := l;
    RETURN l;
  END NewLabel;


  PROCEDURE DefineLabel*(lab : Label; seg : SHORTINT; offs : LONGINT);
  BEGIN
    lab.seg  := seg;
    lab.offs := offs;
  END DefineLabel;


  PROCEDURE SetLabel*(lab : Label);
  BEGIN
    DefineLabel(lab, segCode, pc);
  END SetLabel;


  PROCEDURE FixJcc*(VAR dest : Label);
  BEGIN
    IF dest # NIL THEN
      SetLabel(dest);
      dest := NIL;
    END;
  END FixJcc;


  (* change all references to old-Label to now refer to new-Label *)
  PROCEDURE MergeJcc*(VAR old : Label; new : Label);
    VAR b : JccInfo;
  BEGIN (* new = NIL => no destination with which to merge *)
    IF new # NIL THEN
      b := JccFixupList;
      WHILE (b # NIL) DO
        IF b.lab = old THEN
          b.lab := new;
        END;
        b := b.next;
      END;
      old := new;
    END;
  END MergeJcc;


  (* make Ljmp & Rjmp utilize the same label *)
  PROCEDURE JoinJcc*(VAR Ljmp, Rjmp : Label);
  BEGIN
    IF Ljmp # NIL THEN
      Rjmp := Ljmp;
    ELSIF Rjmp # NIL THEN
      Ljmp := Rjmp;
    ELSE
      Ljmp := NewLabel();
      Rjmp := Ljmp;
    END;
    SetLabel(Ljmp);
  END JoinJcc;


  PROCEDURE NewFixup*(mode, segment : SHORTINT; offs : LONGINT) : Fixup;
    VAR f : Fixup;
  BEGIN
    ASSERT(segment IN {segCode, segConst, segCase, segData,
                       segExport, segCommand, segTypeDesc, segTDesc});
    NEW(f);
    f.mode := mode;
    f.segment := segment;
    f.toffs := offs;
    f.doffs := 0;
    f.lab := NIL;
    f.sym := NIL;
    f.next := FixupList;
    FixupList := f;
    RETURN f;
  END NewFixup;


  PROCEDURE NewRecordSizeFixup*(offs, size : LONGINT) : Fixup;
    VAR f : Fixup;
  BEGIN
    f := NewFixup(FixBlk, segTypeDesc, offs);
    f.doffs := size;
    RETURN f;
  END NewRecordSizeFixup;


  PROCEDURE SetFixupLab*(f : Fixup; lab : Label);
  BEGIN
    ASSERT(f.mode IN {FixAbs, FixRel});
    f.lab := lab;
  END SetFixupLab;


  PROCEDURE SetFixupSym*(f : Fixup; sym : ST.Symbol);
  BEGIN
    ASSERT(f.mode IN {FixAbs, FixRel});
    f.sym := sym;
  END SetFixupSym;


  (* ----------- Type Descriptor Segment Generators ----------- *)

  (* Type descriptors must be aligned on paragraph boundaries. *)
  PROCEDURE TDAlign*(VAR adr : LONGINT; nofMeth : LONGINT);
    VAR t0 : LONGINT;
  BEGIN
    t0 := typedescx;
    nofMeth := nofMeth * SIZE(LONGINT);
    INC(t0, nofMeth); (* space for method table *)
    INC(t0, (-t0) MOD 10H);
    typedescx := t0 - nofMeth;
    adr := t0;
  END TDAlign;


  PROCEDURE TDGenString*(str : ARRAY OF CHAR) : LONGINT;
    VAR adr : LONGINT; i : INTEGER; ch : CHAR;
  BEGIN
    adr := typedescx;
    i := 0;
    ch := ' ';
    WHILE ch # 0X DO
      ch := str[i];
      IF typedescx >= MaxTypeDesc THEN
        OPM.err(EL.TypeDescPoolOverflow);
        typedescx := 0;
        adr := 0;
      END;
      TypeDescTab[typedescx] := ch;
      INC(typedescx);
      INC(i);
    END;
    RETURN adr;
  END TDGenString;


  PROCEDURE TDGenByte*(x : SYSTEM.BYTE) : LONGINT;
    VAR j, adr : LONGINT;
  BEGIN
    IF typedescx + SIZE(SYSTEM.BYTE) >= MaxTypeDesc THEN
      OPM.err(EL.TypeDescPoolOverflow);
      typedescx := 0;
    END;
    adr := typedescx;
    TypeDescTab[typedescx] := x;
    INC(typedescx);
    RETURN adr;
  END TDGenByte;


  PROCEDURE TDGenWord*(x : LONGINT) : LONGINT;
    VAR adr, t0 : LONGINT;
  BEGIN
    adr := TDGenByte(SYSTEM.VAL(SYSTEM.BYTE, x)); (* SHORT(SHORT(x MOD 100H))); *)
    t0 := TDGenByte(SYSTEM.VAL(SYSTEM.BYTE, x DIV 100H));
    RETURN adr;
  END TDGenWord;

  PROCEDURE TDGenDWord*(x : LONGINT) : LONGINT;
    VAR adr, t0 : LONGINT;
  BEGIN
    adr := TDGenWord(x);
    t0 := TDGenWord(x DIV 10000H);
    RETURN adr;
  END TDGenDWord;


  PROCEDURE TDGenSym*(x : ST.Symbol) : LONGINT;
    VAR adr : LONGINT; f : Fixup;
  BEGIN
    IF typedescx + SIZE(LONGINT) >= MaxTypeDesc THEN
      OPM.err(EL.TypeDescPoolOverflow);
      typedescx := 0;
    END;
    adr := TDGenDWord(0);
    f := NewFixup(FixAbs, segTypeDesc, adr);
    SetFixupSym(f, x);
    RETURN adr;
  END TDGenSym;


  (* ----------- Constant Segment Generators ----------- *)

  PROCEDURE GenConstString*(sym : ST.Symbol) : LONGINT;
    VAR adr : LONGINT; i : INTEGER; ch : CHAR; str : ST.ConstExt;
  BEGIN
    adr := constx;
    str := sym(ST.SymbolConst).val.ext;
    i := 0;
    ch := ' ';
    WHILE ch # 0X DO
      ch := str[i];
      IF constx >= MaxConst THEN
        OPM.err(EL.ConstantPoolOverflow);
        constx := 0;
        adr := 0;
      END;
      ConstTab[constx] := ch;
      INC(constx);
      INC(i);
    END;
    RETURN adr;
  END GenConstString;


  PROCEDURE GenConstByte*(x : SYSTEM.BYTE) : LONGINT;
    VAR j, adr : LONGINT;
  BEGIN
    IF constx + SIZE(SYSTEM.BYTE) >= MaxConst THEN
      OPM.err(EL.ConstantPoolOverflow);
      constx := 0;
    END;
    adr := constx;
    ConstTab[constx] := x;
    INC(constx);
    RETURN adr;
  END GenConstByte;


  PROCEDURE GenConstWord*(x : LONGINT) : LONGINT;
    VAR adr, t0 : LONGINT;
  BEGIN
    adr := GenConstByte(SYSTEM.VAL(SYSTEM.BYTE, x));
    t0 := GenConstByte(SYSTEM.VAL(SYSTEM.BYTE, x DIV 100H));
    RETURN adr;
  END GenConstWord;


  PROCEDURE GenConstDWord*(x : LONGINT) : LONGINT;
    VAR adr, t0 : LONGINT;
  BEGIN
    adr := GenConstWord(x);
    t0 := GenConstWord(x DIV 10000H);
    RETURN adr;
  END GenConstDWord;


  PROCEDURE FixupConstDWord*(at, val : LONGINT);
    VAR save, t0 : LONGINT;
  BEGIN
    save := constx;
    constx := at;
    t0 := GenConstDWord(val);
    constx := save;
  END FixupConstDWord;


  PROCEDURE GenConstSym*(x : ST.Symbol) : LONGINT;
    VAR adr : LONGINT; f : Fixup;
  BEGIN
    IF constx + SIZE(LONGINT) >= MaxConst THEN
      OPM.err(EL.ConstantPoolOverflow);
      constx := 0;
    END;
    adr := GenConstDWord(0);
    f := NewFixup(FixAbs, segConst, adr);
    f.sym := x;
    RETURN adr;
  END GenConstSym;


  PROCEDURE GenConstReal*(x : REAL) : LONGINT;
    VAR lo, hi : LONGINT;
  BEGIN
    OPM.ConvertReal(x, FALSE, lo, hi);
    RETURN GenConstDWord(lo);
  END GenConstReal;


  PROCEDURE GenConstLReal*(x : LONGREAL) : LONGINT;
    VAR lo, hi : LONGINT;
  BEGIN
    OPM.ConvertReal(x, TRUE, lo, hi);
    lo := GenConstDWord(lo);
    hi := GenConstDWord(hi);
    RETURN lo;
  END GenConstLReal;


  PROCEDURE DefaultInst(VAR x : Instruction);
  BEGIN
    x.opclass       := -1;
    x.opc           := -1;
    x.Rd            := -1;
    x.R0            := -1;
    x.R1            := -1;
    x.bd            := -1;
    x.b0            := -1;
    x.b1            := -1;
    x.scale         := -1;
    x.dataLo        := -1;
    x.dataHi        := -1;
    x.jcc           := -1;
    x.systrap.halt  := -1;
    x.systrap.subcl := -1;
    x.flags         := {};
    x.sym           := NIL;
    x.lab           := NIL;
  END DefaultInst;


  PROCEDURE PutByte*(op : SYSTEM.BYTE);
  BEGIN
    CodeTab[pc] := op;
    INC(pc);
    IF pc >= MaxCode THEN
      pc := 0;
      OPM.err(EL.TooMuchCode);
    END;
  END PutByte;

  PROCEDURE PutOpBytes(opsize : INTEGER; opc : LONGINT);
  END PutOpBytes;

  PROCEDURE PutD*(dsize : INTEGER; data : LONGINT);
    VAR i : INTEGER;
  BEGIN
    i := 0;
    WHILE i < SIZE(LONGINT) DO
      PutByte(SYSTEM.VAL(SYSTEM.BYTE, data));
      data := SYSTEM.LSH(data, -8);
      INC(i);
    END;
  END PutD;

  PROCEDURE PutWord(data : LONGINT);
  BEGIN
    PutD(SIZE(LONGINT), data);
  END PutWord;


  PROCEDURE PutByteAt(pc, data : LONGINT);
  BEGIN
    CodeTab[pc] := SYSTEM.VAL(SYSTEM.BYTE, data);
  END PutByteAt;

  PROCEDURE PutLongAt(pc, data : LONGINT);
    VAR i : INTEGER;
  BEGIN
    i := 0;
    WHILE i < SIZE(LONGINT) DO
      CodeTab[pc] := SYSTEM.VAL(SYSTEM.BYTE, data);
      INC(pc);
      data := SYSTEM.LSH(data, -8);
      INC(i);
    END;
  END PutLongAt;

  PROCEDURE FixupEmitSeg(kind : SHORTINT; segment, displ : LONGINT);
    VAR f : Fixup; lab : Label;
  BEGIN
    lab := NewLabel();
    lab.seg := SHORT(SHORT(segment));
    lab.offs := displ;
    f := NewFixup(kind, segCode, pc);
    f.lab := lab;
    PutD(4, 0);
  END FixupEmitSeg;

  PROCEDURE FixupEmitSym(kind : SHORTINT; VAR x : Instruction);
    VAR f : Fixup; disp : LONGINT;
  BEGIN
    f := NewFixup(kind, segCode, pc);
    f.sym := x.sym;
    disp  := x.dataLo;
    IF f.sym.kind = ST.field THEN
      DEC(disp, x.sym.adr); (* Field address is part of the x.adr field *)
    END;
    PutWord(disp);
  END FixupEmitSym;


  PROCEDURE FixupEmitLab(kind : SHORTINT; lab : Label);
    VAR f : Fixup;
  BEGIN
    f := NewFixup(kind, segCode, pc);
    f.lab := lab;
    PutD(4, 0);
  END FixupEmitLab;


  PROCEDURE GetHelperFixup(VAR module, function : OPS.Name) : FixupHelper;
    VAR f : FixupHelper;
  BEGIN
    f := FixupHelperList;
    LOOP
      IF f = NIL THEN
        NEW(f);
        f.next := FixupHelperList;
        FixupHelperList := f;
        COPY(module, f.module);
        COPY(function, f.function);
        f.loc := NIL;
        EXIT;
      ELSIF (f.module = module) & (f.function = function) THEN
        EXIT;
      ELSE
        f := f.next;
      END;
    END;
    RETURN f;
  END GetHelperFixup;


  PROCEDURE FixupEmitHelper(offs : LONGINT; module, function : OPS.Name);
    VAR
      loc : FixupHelperLocation;
      helper : FixupHelper;
  BEGIN
    helper := GetHelperFixup(module, function);
    NEW(loc);
    loc.offs   := offs;
    loc.next   := helper.loc;
    helper.loc := loc;
    PutD(4, 0);
  END FixupEmitHelper;


  (* [base + offs] := dest *)
  PROCEDURE FixupEmitAt(mode : SHORTINT; base : Label; offs : LONGINT; dest : Label);
    VAR f : Fixup;
  BEGIN
    f := NewFixup(mode, base.seg, base.offs + offs);
    f.lab := dest;
  END FixupEmitAt;


  PROCEDURE JccFixupEmit(cc : SHORTINT; lab : Label);
    VAR jcc : JccInfo;
  BEGIN
    NEW(jcc);
    jcc.next     := JccFixupList;
    JccFixupList := jcc;
    jcc.pc       := pc;
    jcc.lab      := lab;
    jcc.cc       := cc;
    jcc.disp     := 4;
    PutWord(0);
  END JccFixupEmit;


  PROCEDURE GenerateGeneralReg(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.bd, 10)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.b0, 9)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.b1, 8)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateGeneralReg;


  PROCEDURE GenerateIntegerReg(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateIntegerReg;


  PROCEDURE GenerateSignExtend(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateSignExtend;


  PROCEDURE GenerateControlReg(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateControlReg;


  PROCEDURE GenerateSystemReg(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateSystemReg;


  PROCEDURE GenerateMiscellaneous(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateMiscellaneous;


  PROCEDURE GenerateJRAL(VAR inst : Instruction);
    VAR
      d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateJRAL;


  PROCEDURE GenerateBranch(VAR inst : Instruction);
    VAR
      d : SET;
      adr : LONGINT;
  BEGIN
    IF inst.opc = opcJ THEN
      (* Unconditional branches *)
      ASSERT((inst.lab # NIL) & (inst.sym = NIL), 200);
      d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
            SYSTEM.VAL(SET, LONG(inst.opc)));
      PutWord(SYSTEM.VAL(LONGINT, d));
      JccFixupEmit(ccAW, inst.lab);
    ELSIF inst.opc = opcJAL THEN
      d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
            SYSTEM.VAL(SET, SYSTEM.LSH(31, 21)) +
            SYSTEM.VAL(SET, LONG(inst.opc)));
      ASSERT(inst.sym # NIL, 201);
      PutWord(SYSTEM.VAL(LONGINT, d));
      FixupEmitSym(FixAbs, inst);
    ELSE
      (* Conditional branches *)
      ASSERT(inst.opc IN comparisons, 202);
      IF inst.R0 = -1 THEN
        DumpInstruction(inst, "GenerateRegMemImmed");
        OPM.internal("L", 202);
      END;
      d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
            SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
            SYSTEM.VAL(SET, LONG(inst.opc)));

      ASSERT(inst.lab # NIL, 203);
      PutWord(SYSTEM.VAL(LONGINT, d));
      JccFixupEmit(inst.jcc, inst.lab);
    END;
  END GenerateBranch;


  PROCEDURE GenerateRegMemImmed(VAR inst : Instruction);
    VAR
      d : SET;
  BEGIN
    ASSERT((inst.Rd # -1) &
           (inst.R0 # -1) &
           (inst.R1 # -1) & (inst.scale # -1));
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.scale, 6)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
    IF inst.sym # NIL THEN (* Reference to symol *)
      ASSERT(inst.lab = NIL);
      FixupEmitSym(FixAbs, inst);
    ELSIF inst.lab # NIL THEN
      FixupEmitLab(FixAbs, inst.lab);
    ELSE (* Actual constant value *)
      PutWord(inst.dataLo);
      IF inst.opc = opcLDI THEN
        PutWord(inst.dataHi);
      END;
    END;
  END GenerateRegMemImmed;


  PROCEDURE GenerateBitTest(VAR inst : Instruction);
    VAR
      d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R1, 11)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateBitTest;


  PROCEDURE GenerateStack(VAR inst : Instruction);
    VAR
      d : SET;
  BEGIN (* push, pop, enter, leave *)
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.dataLo MOD 65536, 5)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateStack;


  PROCEDURE GenerateConditional(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, LONG(inst.opc)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateConditional;


  PROCEDURE GenerateSysTrap(VAR inst : Instruction);
    VAR d : SET;
  BEGIN
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(inst.opclass, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.Rd, 21)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.R0, 16)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(inst.systrap.halt, 8)) +
          SYSTEM.VAL(SET, LONG(inst.systrap.subcl)));
    PutWord(SYSTEM.VAL(LONGINT, d));
  END GenerateSysTrap;


  PROCEDURE GetFixupKind(o : LONGINT) : SHORTINT;
    VAR x : SHORTINT;
  BEGIN
    x := FixAbs;
    IF (o = 0E9H) (* JMP *) OR (o = 0E8H) (* CALL *) THEN
      x := FixRel;
    END;
    RETURN x;
  END GetFixupKind;

  PROCEDURE PutInst(VAR inst : Instruction);
  BEGIN
(*
     DumpInstruction(inst, "PutInst");
*)
    CASE inst.opclass OF
    | ocGENREG:      GenerateGeneralReg(inst);
    | ocINTREG:      GenerateIntegerReg(inst);
    | ocSIGNEXTEND:  GenerateSignExtend(inst);
    | ocCONTROLREG:  GenerateControlReg(inst);
    | ocSYSREG:      GenerateSystemReg(inst);
    | ocMISC:        GenerateMiscellaneous(inst);
    | ocJRAL:        GenerateJRAL(inst);
    | ocBRANCH:      GenerateBranch(inst);
    | ocREGMEMIMM:   GenerateRegMemImmed(inst);
    | ocBT:          GenerateBitTest(inst);
    | ocSTACK:       GenerateStack(inst);
    | ocSET:         GenerateConditional(inst);
    | ocSYSTRAP:     GenerateSysTrap(inst);
    ELSE
      OPM.internal("L", 1000);
    END;
  END PutInst;


  PROCEDURE RegBankOf(f : SHORTINT) : SHORTINT;
  BEGIN
    IF f IN ST.RealSet THEN
      RETURN 1;
    ELSE
      RETURN 0;
    END;
  END RegBankOf;


  (* Return actual address of non-global Item;
   * Can't be treated as global because then fixups would be needed.
   *)
  PROCEDURE AddressOf*(VAR x : Item) : LONGINT;
  BEGIN
    IF (x.mnolev <= 0) OR (x.sym = NIL) THEN
      RETURN x.adr; (* Address of globals require a fixup, only indicate offset. *)
    ELSE
      RETURN x.adr + x.sym.adr;
    END;
  END AddressOf;


  (* IsConstZero:
   *
   *   Returns TRUE iff 'x' is suitable for replacement with a direct
   *   reference to R0.
   *)
  PROCEDURE IsConstZero*(VAR x : Item) : BOOLEAN;
  BEGIN
    RETURN (x.mode = Iconst) &
           ((x.type.form IN {ST.bool..ST.lint, ST.nil}) & (x.val.i0 = 0)     OR
            (x.type.form IN ST.RealSet)                 & (x.val.real = 0.0) OR
            (x.type.form = ST.set)                      & (x.val.set = {}));
  END IsConstZero;


  (* IsConstOne:
   *
   *   Returns TRUE iff 'x' is suitable for replacement with 'seq Rx, Rx, Rx'.
   *)
  PROCEDURE IsConstOne*(VAR x : Item) : BOOLEAN;
  BEGIN
    RETURN (x.mode = Iconst) &
           ((x.type.form IN {ST.bool..ST.lint, ST.nil}) & (x.val.i0 = 1)     OR
            (x.type.form IN ST.RealSet)                 & (x.val.real = 1.0) OR
            (x.type.form = ST.set)                      & (x.val.set = {0}));
  END IsConstOne;


  (* IsConstTwo:
   *
   *   Returns TRUE iff 'x' is suitable for replacement with a small
   *   sequence to load 2 into a register.
   *)
  PROCEDURE IsConstTwo*(VAR x : Item) : BOOLEAN;
  BEGIN
    RETURN (x.mode = Iconst) &
           ((x.type.form IN {ST.bool..ST.lint, ST.nil}) & (x.val.i0 = 2)     OR
            (x.type.form IN ST.RealSet)                 & (x.val.real = 2.0) OR
            (x.type.form = ST.set)                      & (x.val.set = {1}));
  END IsConstTwo;


  PROCEDURE globaldisp(VAR x : Item; VAR inst : Instruction);
  BEGIN (* global symbol address *)
    inst.sym    := x.sym;
    inst.dataLo := x.adr;
    inst.R0     := 0; (* base *)
  END globaldisp;

  PROCEDURE displ(baseReg : SHORTINT; disp : LONGINT; VAR inst : Instruction);
  BEGIN
    inst.R0     := baseReg;
    inst.dataLo := disp;
  END displ;

  PROCEDURE downlevel(VAR x : Item) : SHORTINT;
    VAR
      b : Item;
      n : SHORTINT;
      stk : Instruction;
  BEGIN
    DefaultInst(stk);
    b.type := ST.linttyp;
    GetReg(b, RegWord);
    INCL(GRegTemp, b.reg);

    stk.opclass := ocREGMEMIMM; (* Register Memory/Immediate *)
    stk.opc     := opcLW;        (* lw *)
    stk.Rd      := SHORT(SHORT(b.reg));
    stk.R0      := SFP;
    stk.R1      := 0;
    stk.scale   := 0;         (* S = 1 *)
    stk.dataLo  := 8;         (* +8 offset *)
    PutInst(stk);             (* lw  (Rstack, R0 * 1, 8), Rb *)

    stk.R0 := stk.Rd;
    n := level - x.mnolev;
    WHILE n > 1 DO
      DEC(n);
      PutInst(stk); (* lw  (Rb, R0 * 1, 8), Rb *)
    END;
    RETURN stk.Rd; (* Stack pointer to access variables from parent scope. *)
  END downlevel;

  PROCEDURE indirect(baseReg  : SHORTINT;
                     VAR x    : Item;
                     VAR inst : Instruction) : SHORTINT;
    VAR
      indreg : Item;
      adr    : LONGINT;
      indir  : Instruction;
  BEGIN
    DefaultInst(indir);
    GetReg(indreg, RegWord);

    indir.opclass := ocREGMEMIMM;
    indir.opc     := opcLW;
    indir.Rd      := SHORT(SHORT(indreg.reg));

    IF x.mnolev <= 0 THEN (* Global symbol; no base, no index, no scaling. *)
      indir.R0    := 0;
      indir.R1    := 0;
      indir.scale := 0;
      indir.sym   := inst.sym;
      inst.sym    := NIL;
    ELSE (* Stack-based symbol; displacement only. *)
      indir.R0     := baseReg; (* base register *) (* XXX right? *)
      indir.R1     := 0;  (* index register *)
      indir.scale  := 0;
      indir.dataLo := AddressOf(x);
    END;

    PutInst(indir); (* lw [pointer], indir *)
    RETURN SHORT(SHORT(indreg.reg)); (* Register holding loaded value. *)
  END indirect;


  PROCEDURE scaleof(size : LONGINT) : SHORTINT;
  BEGIN (* Returns scale field for given operand size *)
    IF size = 1 THEN
      RETURN 0;
    ELSIF size = 2 THEN
      RETURN 1;
    ELSIF size = 4 THEN
      RETURN 2;
    ELSIF size = 8 THEN
      RETURN 3;
    ELSE
      RETURN 0;                 (* Cannot scale. *)
    END;
  END scaleof;

  PROCEDURE scale(VAR x : Item; VAR inst : Instruction);
  BEGIN (* Set scaling & index register *)
    ASSERT(x.mode IN { Ivarx, Iindx, Iregix });

    inst.scale := scaleof(x.type.size);
    IF x.mode IN { Iindx, Iregix } THEN
      inst.R1 := SHORT(SHORT(x.inxreg));
    ELSIF x.mode = Ivarx THEN
      IF x.mnolev >= 0 THEN
        (* Local variable. *)
        IF x.mnolev = 0 THEN (* global *)
          inst.R1 := SHORT(SHORT(x.inxreg));
        ELSIF x.mnolev = level THEN (* local *)
          inst.R1 := SHORT(SHORT(x.inxreg)); (* [inxreg * scale] *)
        ELSE (* Non-local, from outer scope. *)
          inst.R1 := SHORT(SHORT(x.inxreg));
        END;
      ELSE (* Global variable. *)
        inst.R1 := SHORT(SHORT(x.inxreg));
      END;
    END;
  END scale;

  (* index:
   *
   *   Generate index of { Iregix, Ivarx, Iindx }.
   *)
  PROCEDURE index(VAR x : Item; VAR inst : Instruction);
    VAR
      s     : LONGINT;
      Rsize  : Item;
      Rindex : Item;

    PROCEDURE LoadSize(s : LONGINT; VAR size : Item);
      VAR
        inst : Instruction;
    BEGIN
      DefaultInst(inst);
      InitItem(size);
      GetReg(size, RegWord);
      size.type := ST.linttyp;

      inst.opclass := ocREGMEMIMM;
      inst.opc     := opcLWI;
      inst.Rd      := SHORT(SHORT(size.reg));
      inst.R0      := 0;
      inst.R1      := 0;
      inst.scale   := 0;
      inst.dataLo  := s;
      PutInst(inst);            (* lwi s, Rsize *)
    END LoadSize;

  BEGIN
    ASSERT(x.mode IN {Iindx, Iregix, Ivarx});
    s := x.type.size; (* inv: s > 0 *)
    IF (s > MAX(SET)) OR ~(s IN {1, 2, 4, 8}) THEN
      (* Scale cannot be encoded in instruction. *)
      Rindex := x;
      DoubleRef(Rindex);
      Rindex.mode := Ireg;
      Rindex.reg  := Rindex.inxreg;
      LoadSize(s, Rsize);
      PutGenReg(opcMUL, Rindex, Rsize, Rindex);
      inst.R1 := SHORT(SHORT(Rindex.reg));
    ELSE
      scale(x, inst);
    END;
  END index;

  PROCEDURE Operand(VAR x : Item; VAR inst : Instruction);
    VAR
      R0       : Item;
      frameReg : SHORTINT;
      lo, hi   : LONGINT;
      real     : REAL;
      nlfp     : Item;          (* Non-local frame pointer. *)
      offset   : Item;          (* Offset of variable in frame. *)
  BEGIN
    frameReg := SFP;
    CASE x.mode OF
    |  Ivar, Ipar:
       IF x.mnolev <= 0 THEN
         globaldisp(x, inst);
       ELSIF x.mnolev = level THEN
         inst.scale := 0;
         inst.R1    := 0;
         displ(SFP, AddressOf(x), inst); (* [sfp +/- offset] *)
       ELSE
         frameReg   := downlevel(x);
         inst.R0    := frameReg;
         inst.R1    := 0;
         inst.scale := 0;
         displ(frameReg, AddressOf(x), inst);
      END;

    |  Ivarpar, Iind:
       IF x.mnolev <= 0 THEN
         globaldisp(x, inst);
       ELSIF x.mnolev = level THEN
         displ(SFP, AddressOf(x), inst); (* [sfp +/- offset] *)
       ELSE
         frameReg := downlevel(x);
       END;
       frameReg    := indirect(frameReg, x, inst);  (* Base register. *)
       inst.R1     := 0;                            (* No index register. *)
       inst.scale  := 0;
       displ(frameReg, x.offset, inst);

    |  Ivarx:
       index(x, inst);
       IF x.mnolev <= 0 THEN (* Global symbol. *)
         globaldisp(x, inst);
       ELSIF x.mnolev = level THEN
         displ(SFP, AddressOf(x), inst); (* [sfp +/- offset + Rx] *)
       ELSE
         displ(downlevel(x), (* Dynamic frame register. *)
               AddressOf(x), (* Address in dynamic frame. *)
               inst);
         scale(x, inst);
       END;

    |  Iregi: (* base register only *)
       displ(SHORT(SHORT(x.reg)), x.offset, inst);
       inst.R1    := 0;
       inst.scale := 0;

    |  Iregix:
       inst.R0 := SHORT(SHORT(x.reg));
       index(x, inst);
       displ(SHORT(SHORT(x.reg)), x.offset, inst);

    | Iadr:
      ASSERT(x.mnolev <= 0, 265);
      (* Address of global symbol *)
      ASSERT(x.sym # NIL);
      inst.R0     := 0;
      inst.R1     := 0;
      inst.dataLo := x.adr;
      inst.scale  := 0;
      inst.sym    := x.sym;

    | Iconst:
      inst.R0    := 0;
      inst.R1    := 0;
      inst.scale := 0;
      IF x.type.form IN ST.IntSet +  {ST.bool, ST.byte, ST.char, ST.nil} THEN
        inst.dataLo := x.val.i0;
      ELSIF x.type.form = ST.set THEN
        inst.dataLo := SYSTEM.VAL(LONGINT, x.val.set);
      ELSIF x.type.form = ST.real THEN
        real := SHORT(x.val.real);
        inst.dataLo := SYSTEM.VAL(LONGINT, real);
      ELSE
        ASSERT(x.type.form = ST.lreal, 210);
        OPM.GetLRealHalves(x.val.real, lo, hi);
        inst.dataLo := lo;
        inst.dataHi := hi;
      END;

    | Ilproc, Ixproc:
      ASSERT(x.sym # NIL);
      inst.sym    := x.sym;
      inst.dataLo := 0;
    END;
  END Operand;


  PROCEDURE PutCompare*(VAR lop, rop, result : Item); (* <cmp> lop, rop, result *)
    VAR
      inst : Instruction;
  BEGIN
    ASSERT((lop.mode = Ireg) & (rop.mode = Ireg) &
           (result.mode IN {Ireg,
                            Icoc}), 200); (* Can reuse register in result.adr *)
    DefaultInst(inst);
    inst.opclass := ocGENREG;
    inst.opc     := opcCMP;
    inst.Rd      := SHORT(SHORT(result.reg));
    inst.R0      := SHORT(SHORT(lop.reg));
    inst.R1      := SHORT(SHORT(rop.reg));
    inst.bd      := 0;          (* Alway integer register. *)
    inst.b0      := RegBankOf(lop.type.form);
    inst.b1      := RegBankOf(rop.type.form);
    PutInst(inst);
  END PutCompare;


  PROCEDURE PutConditionalSet*(opc : SHORTINT; (* ocSET opcodes *)
                               VAR Rd, Rcoc : Item); (* s<opc> Rd, Rcoc *)
    VAR
      inst : Instruction;
  BEGIN
    ASSERT((Rd.mode = Ireg) & (Rcoc.mode = Icoc));
    DefaultInst(inst);
    inst.opclass := ocSET;
    inst.opc     := opc;
    inst.Rd      := SHORT(SHORT(Rd.reg));
    inst.R0      := SHORT(SHORT(Rcoc.reg));
    PutInst(inst);
  END PutConditionalSet;


  PROCEDURE PutLoadAddress*(VAR x, y : Item); (* Load address of 'y' into register 'x' *)
    VAR inst : Instruction;
  BEGIN
    ASSERT(x.mode IN {Ireg, Iregi}, 200);
    DefaultInst(inst);
    inst.opclass := ocREGMEMIMM;
    inst.opc     := opcLA;
    inst.Rd      := SHORT(SHORT(x.reg));
    inst.R1      := 0;
    inst.scale   := 0;
    Operand(y, inst);
    PutInst(inst);
  END PutLoadAddress;

  PROCEDURE PutLoad*(VAR x, y : Item); (* Load 'y' from memory into register 'x' *)
    VAR
      inst : Instruction;
      c : LONGINT;
  BEGIN
    ASSERT((x.mode = Ireg) & ~(y.mode IN {Ireg, Icoc}));

    DefaultInst(inst);
    inst.Rd := SHORT(SHORT(x.reg));

    IF y.mode = Iconst THEN
      IF IsConstZero(y) THEN
        (* Load R0 into the destination register. *)
        inst.opclass := ocGENREG; (* add R0, R0, Rx *)
        inst.opc     := opcADD;
        inst.Rd      := SHORT(SHORT(x.reg));
        inst.R0      := 0;      (* Register R0 *)
        inst.R1      := 0;      (* Register R0 *)
        inst.bd      := RegBankOf(y.type.form);
        inst.b0      := 0;      (* integer bank *)
        inst.b1      := 0;      (* integer bank *)
        PutInst(inst);
      ELSIF y.type.form IN ST.RealSet THEN
        inst.opclass := ocREGMEMIMM; (* l(f|d)i <value>, Rx *)
        IF y.type.form = ST.real THEN
          inst.opc := opcLFI;
        ELSE
          inst.opc := opcLDI;
        END;
        Operand(y, inst);
        PutInst(inst);
      ELSE
        ASSERT(x.type.form IN ST.BasicSet, 200);
        inst.opclass := ocREGMEMIMM; (* lwi <value>, Rx *)
        inst.opc     := opcLWI;
        Operand(y, inst);
        PutInst(inst);
      END;
    ELSE
      inst.opclass := ocREGMEMIMM;
      CASE y.type.form OF
      | ST.bool, ST.byte, ST.char:
        inst.opc := opcLBU;

      | ST.sint:
        inst.opc := opcLB;

      | ST.int:
        inst.opc := opcLH;

      | ST.lint, ST.pointer, ST.procedure, ST.set:
        inst.opc := opcLW;

      | ST.real:
        inst.opc := opcLF;

      | ST.lreal:
        inst.opc := opcLD;
      END;
      inst.Rd    := SHORT(SHORT(x.reg));
      inst.R0    := 0;          (* No base register. *)
      inst.R1    := 0;          (* Index register. *)
      inst.scale := 0;          (* Scale. *)
      IF y.mode = Iregix THEN
        inst.R0 := SHORT(SHORT(y.inxreg));
      END;
      Operand(y, inst);
      PutInst(inst);
    END;
  END PutLoad;


  PROCEDURE PutAbs*(VAR R1, Rd : Item); (* abs R0, Ry, Rx *)
    VAR
      inst : Instruction;
  BEGIN
    ASSERT(R1.mode = Ireg, 201);
    ASSERT(Rd.mode = Ireg, 202);
    DefaultInst(inst);
    inst.opclass := ocGENREG;
    inst.opc     := opcABS;
    inst.Rd      := SHORT(SHORT(Rd.reg));
    inst.R0      := 0;
    inst.R1      := SHORT(SHORT(R1.reg));
    inst.bd      := RegBankOf(Rd.type.form);
    inst.b0      := 0;
    inst.b1      := RegBankOf(R1.type.form);
    PutInst(inst);
  END PutAbs;

  PROCEDURE PutGenReg*(opc : SHORTINT; VAR r0, r1, dest : Item);
    VAR
      inst : Instruction;
  BEGIN (* <opc>  R0, R1, Rd *)
    ASSERT(r0.mode = Ireg, 200);
    ASSERT(r1.mode = Ireg, 201);
    ASSERT(dest.mode = Ireg, 202);
    DefaultInst(inst);
    inst.opclass := ocGENREG;
    inst.opc     := opc;
    inst.Rd      := SHORT(SHORT(dest.reg));
    inst.R0      := SHORT(SHORT(r0.reg));
    inst.R1      := SHORT(SHORT(r1.reg));
    inst.bd      := RegBankOf(dest.type.form);
    inst.b0      := RegBankOf(r0.type.form);
    inst.b1      := RegBankOf(r1.type.form);
    PutInst(inst);
  END PutGenReg;


  PROCEDURE PutIntReg*(opc : SHORTINT; VAR r0, r1, dest : Item);
    VAR
      inst : Instruction;
  BEGIN (* <opc>  R0, R1, Rd *)
    ASSERT(r0.mode = Ireg, 200);
    ASSERT(r1.mode = Ireg, 201);
    ASSERT(dest.mode = Ireg, 202);
    DefaultInst(inst);
    inst.opclass := ocINTREG;
    inst.opc     := opc;
    inst.Rd      := SHORT(SHORT(dest.reg));
    inst.R0      := SHORT(SHORT(r0.reg));
    inst.R1      := SHORT(SHORT(r1.reg));
    PutInst(inst);
  END PutIntReg;


  PROCEDURE PutSysTrap*(opc, subcl : SHORTINT; VAR x : Item);
    VAR
      inst : Instruction;
  BEGIN
    ASSERT(opc IN { opcTRAPASSERT,
                    opcTRAPRANGE,      (* Integer range *)
                    (* opcTRAPARRAY *) (* PutSysTrapBound *)
                    opcTRAPIGUARD,
                    opcTRAPEGUARD,
                    opcTRAPCASE,
                    opcTRAPFUNC,
                    opcTRAPWITH,
                    OPCTRAPGUARD,
                    opcTRAPNIL });

    ASSERT(x.mode = Ireg, 200);
    DefaultInst(inst);
    inst.opclass       := ocSYSTRAP;
    inst.opc           := 0;
    inst.Rd            := 0;
    inst.R0            := SHORT(SHORT(x.reg));
    inst.systrap.halt  := opc;
    inst.systrap.subcl := subcl;
    PutInst(inst);
  END PutSysTrap;

  PROCEDURE PutSysTrapArray*(VAR index, bound : Item);
    VAR
      inst : Instruction;
  BEGIN
    ASSERT((index.mode = Ireg) & (bound.mode = Ireg), 200);
    DefaultInst(inst);
    inst.opclass       := ocSYSTRAP;
    inst.opc           := 0;
    inst.Rd            := SHORT(SHORT(bound.reg));
    inst.R0            := SHORT(SHORT(index.reg));
    inst.systrap.halt  := opcTRAPARRAY;
    inst.systrap.subcl := 0;
    PutInst(inst);
  END PutSysTrapArray;

  PROCEDURE PutStoreMem*(opc : SHORTINT; VAR x, y : Item); (* Store 'y' into memory at 'x' *)
    VAR
      inst : Instruction;
      c    : LONGINT;
  BEGIN
    ASSERT(x.mode IN { Ivar, Ipar, Ivarpar, Ivarx,
                       Iind, Iregi, Iregix, Iadr }, 200);
    ASSERT(y.mode = Ireg, 201);

    DefaultInst(inst);
    inst.Rd      := SHORT(SHORT(y.reg)); (* Source reg for this encoding. *)
    inst.R1      := 0;
    inst.scale   := 0;
    inst.opclass := ocREGMEMIMM;
    inst.opc     := opc;
    Operand(x, inst);
    PutInst(inst);
  END PutStoreMem;


  PROCEDURE PutBT(opc     : SHORTINT;
                  bit     : SHORTINT;
                  VAR set : Item;
                  VAR Rd  : Item);
    VAR
      inst : Instruction;
  BEGIN
    inst.opclass := ocBT;
    inst.opc     := opc;
    inst.Rd      := SHORT(SHORT(Rd.reg));
    inst.R0      := bit;
    inst.R1      := SHORT(SHORT(set.reg));
    PutInst(inst); (* <opc> bit, set, Rd *)
  END PutBT;

  PROCEDURE PutBitTestMemory*(opc     : SHORTINT;
                              VAR bit : Item;
                              VAR set : Item;
                              VAR Rd  : Item);
  BEGIN
    ASSERT(Rd.mode = Ireg, 200);
    ASSERT(bit.mode = Iconst, 201);
    ASSERT(set.mode = Ireg, 202);
    PutBT(opc, SHORT(SHORT(bit.val.i0)), set, Rd);
  END PutBitTestMemory;


  PROCEDURE PutBitTest*(VAR bit : Item;
                        VAR set : Item;
                        VAR Rd : Item);
    VAR
      opc : SHORTINT;
      R0  : SHORTINT;
  BEGIN
    ASSERT((set.mode = Ireg) & (bit.mode IN {Ireg, Iconst}));
    ASSERT(Rd.mode = Ireg);

    IF bit.mode = Iconst THEN
      R0  := SHORT(SHORT(bit.val.i0));
      opc := opcBTCR;
    ELSE
      R0  := SHORT(SHORT(bit.reg));
      opc := opcBTRR;
    END;
    PutBT(opc, R0, set, Rd);
  END PutBitTest;


  PROCEDURE PutEnterLeave(opc : SHORTINT; words : INTEGER; Rd : SHORTINT);
    VAR
      inst : Instruction;
  BEGIN (* enter Rd, size
         * leave Rd, size *)
    DefaultInst(inst);
    inst.opclass := ocSTACK;
    inst.opc     := opc;
    inst.Rd      := Rd;
    inst.dataLo  := words;
    PutInst(inst);
  END PutEnterLeave;


  PROCEDURE PutOpenStackFrame*(words : INTEGER; Rd : SHORTINT);
  BEGIN
    PutEnterLeave(opcENTER, words, Rd);
  END PutOpenStackFrame;


  PROCEDURE PutCloseStackFrame*(words : INTEGER; Rd : SHORTINT);
  BEGIN
    PutEnterLeave(opcLEAVE, words, Rd);
  END PutCloseStackFrame;


  PROCEDURE PutStack*(opc : SHORTINT; VAR x : Item);
    VAR
      inst : Instruction;
  BEGIN
    ASSERT(x.mode = Ireg, 200);
    DefaultInst(inst);
    inst.opclass := ocSTACK;
    inst.opc     := opc;
    inst.Rd      := SHORT(SHORT(x.reg));
    PutInst(inst);
  END PutStack;


  PROCEDURE PutJRAL*(VAR x : Item); (* Used for call through procedure variable only. *)
    VAR
      inst : Instruction;
  BEGIN
    ASSERT(x.mode = Ireg);
    DefaultInst(inst);
    inst.opclass := ocJRAL;
    inst.opc     := 0;
    inst.Rd      := 31;
    inst.R0      := SHORT(SHORT(x.reg));
    PutInst(inst);
  END PutJRAL;


  PROCEDURE PutReturn*(Iproc : BOOLEAN);
    VAR
      inst : Instruction;
  BEGIN (* JRAL R31, words  *)
    DefaultInst(inst);
    IF ~Iproc THEN
      inst.opclass := ocJRAL;
      inst.opc     := 0;
      inst.Rd      := 0;
      inst.R0      := 31;
    ELSE (* Interrupt Procedure *)
      inst.opclass := ocMISC;
      inst.opc     := opcERET;
    END;
    PutInst(inst);
  END PutReturn;

  PROCEDURE NewCaseTable*(low, high : LONGINT) : Label;
    VAR n : LONGINT; i : LONGINT; lab : Label;
  BEGIN
    INC(casex, (-casex) MOD 4);
    lab := NewLabel();
    DefineLabel(lab, segCase, casex);
    n := SHORT(4 * (high - low + 1));
    IF casex < MaxCase - n THEN
      i := casex;
      INC(casex, n);
      WHILE i < casex DO
        CaseTab[i] := FALSE;
        INC(i);
      END;
    ELSE
      OPM.err(EL.TooManyCaseStat);
      casex := 0;
    END;
    RETURN lab;
  END NewCaseTable;

  PROCEDURE SetCaseElse*(tab : Label; low, high : LONGINT; else : Label);
    VAR i, j, k : LONGINT;
  BEGIN
    i := 0;
    j := high - low + 1;
    k := tab.offs;
    WHILE i < j DO
      IF CaseTab[k] = FALSE THEN
        CaseTab[k] := TRUE;
        FixupEmitAt(FixAbs, tab, i * 4, else);
      END;
      INC(i);
      INC(k);
    END;
  END SetCaseElse;

  PROCEDURE SetCaseEntry*(low, high : LONGINT; table, target : Label);
  BEGIN
    ASSERT(low <= high, 134);
    WHILE low <= high DO
      CaseTab[table.offs + low] := TRUE;
      FixupEmitAt(FixAbs, table, low * 4, target);
      INC(low);
    END;
  END SetCaseEntry;

  PROCEDURE CaseJump*(VAR x : Item; tab : Label);
    VAR
      Rt   : Item;
      inst : Instruction;
  BEGIN
    InitItem(Rt);
    GetReg(Rt, RegWord);
    DefaultInst(inst);
    inst.opclass := ocREGMEMIMM;
    inst.opc     := opcLW;
    inst.Rd      := SHORT(SHORT(Rt.reg));
    inst.scale   := scaleof(SIZE(LONGINT));
    inst.R0      := 0;
    inst.R1      := SHORT(SHORT(x.reg));
    inst.dataLo  := 0;
    inst.lab     := tab;
    PutInst(inst);              (* la (tab + Rx:4), Rt *)

    DefaultInst(inst);
    inst.opclass := ocJRAL;
    inst.opc     := 0;
    inst.Rd      := 0;
    inst.R0      := SHORT(SHORT(Rt.reg));
    PutInst(inst);              (* jral Rt, R0 *)
  END CaseJump;

  PROCEDURE CallCompilerHelper*(mod, func : ARRAY OF CHAR);
    CONST
      (* Compiler defect: SYSTEM.VAL(SET, opcJRAL) == 0 *)
      opcJRAL = { 0, 1, 3 };    (* Workaround compiler defect. *)

    VAR
      module, function : OPS.Name;
      d : SET;
  BEGIN
    COPY(mod, module);
    COPY(func, function);
    d := (SYSTEM.VAL(SET, SYSTEM.LSH(ocBRANCH, 26)) +
          SYSTEM.VAL(SET, SYSTEM.LSH(31, 21)) +
          opcJRAL);
    PutWord(SYSTEM.VAL(LONGINT, d)); (* jal instruction word *)
    FixupEmitHelper(pc, module, function); (* jal module.function *)
  END CallCompilerHelper;


  PROCEDURE Inverted*(x: LONGINT) : SHORTINT;  (* inverted sense of Icoc *)
  BEGIN
    ASSERT(x IN ccSet, 200);
    IF ODD(x) THEN
      RETURN SHORT(SHORT(x - 1));
    ELSE
      RETURN SHORT(SHORT(x + 1));
    END;
  END Inverted;

  PROCEDURE PutJump*(cond      : SHORTINT; (* Condition code *)
                     VAR R0    : Item;
                     VAR label : Label);
    VAR
      inst : Instruction;
  BEGIN
    IF cond # ccNV THEN
      IF label = NIL THEN
        label := NewLabel();
      END;
      IF cond = ccAW THEN
        Jmp(label);
      ELSE
        ASSERT(cond IN ccSet, 200);
        ASSERT(R0.mode = Icoc, 201);
        DefaultInst(inst);

        (* The condition code (ccXYZ) values must match the
         * opcode encodings, up to ccAW.  ccNV is a special case that
         * causes no jump to be generated here.
         *)
        inst.opclass := ocBRANCH;
        inst.opc     := cond;
        inst.lab     := label;
        inst.jcc     := cond;
        IF cond = ccAW THEN
          inst.R0  := 0;
        ELSE
          inst.R0 := SHORT(SHORT(R0.reg));
        END;
        PutInst(inst);
      END;
    END;
  END PutJump;


  PROCEDURE PutJAL*(VAR x : Item);
    VAR
      inst : Instruction;
  BEGIN
    ASSERT(x.mode IN { Ilproc, Ixproc }, 200);
    DefaultInst(inst);
    inst.opclass := ocBRANCH;
    inst.opc     := opcJAL;
    Operand(x, inst);
    PutInst(inst);
  END PutJAL;


  PROCEDURE Jmp*(VAR lab : Label);
    VAR
      inst : Instruction;
  BEGIN
    DefaultInst(inst);
    inst.opclass := ocBRANCH;
    inst.opc     := opcJ;
    inst.lab     := lab;
    PutInst(inst);
  END Jmp;

  PROCEDURE JmpT*(VAR x : Item; VAR lab : Label);
  BEGIN
    ASSERT(x.mode = Icoc);
    MergeJcc(x.jump.true, lab);

    PutJump(x.cc, x, x.jump.true);
    IF lab = NIL THEN
      lab := x.jump.true;
    END;
    FixJcc(x.jump.false);
  END JmpT;

  PROCEDURE JmpF*(VAR x : Item; VAR lab : Label);
  BEGIN
    ASSERT(x.mode = Icoc);
    MergeJcc(x.jump.false, lab);
    PutJump(Inverted(x.cc), x, x.jump.false);
    IF lab = NIL THEN
      lab := x.jump.false;
    END;
    FixJcc(x.jump.true);
  END JmpF;

  PROCEDURE GetSegAddress*(seg : SHORTINT; VAR x : Item);
    VAR
      lab : Label;
      inst : Instruction;
  BEGIN
    ASSERT(x.mode = Ireg);
    DefaultInst(inst);
    lab := NewLabel();
    DefineLabel(lab, seg, 0);

    inst.opclass := ocREGMEMIMM;     (* lwi  segment-address, Rx *)
    inst.opc     := opcLWI;
    inst.Rd      := SHORT(SHORT(x.reg));
    inst.R0      := 0;
    inst.R1      := 0;
    inst.scale   := 0;
    inst.lab     := lab;
    PutInst(inst);
  END GetSegAddress;

  PROCEDURE Align*(segment, align : SHORTINT);
    VAR orig, l, d : LONGINT;

    PROCEDURE AlignAdr(VAR x : LONGINT; max : LONGINT);
      VAR s : LONGINT;
    BEGIN
      s := (-x) MOD align;
      IF (x + s <= max) & (x + s >= 0) THEN
        INC(x, s);
      ELSE
        OPM.err(EL.CodeSegOverflow + segment);
        x := 0;
      END;
    END AlignAdr;

  BEGIN
    CASE segment OF
    | segCode:
       orig := pc;
       AlignAdr(orig, MaxCode);
       IF orig # 0 THEN
         d := orig - pc;
         WHILE d > 0 DO
           PutOpBytes(1, 0); (* Four '0' bytes is 'add R0, R0, R0' *)
           DEC(d);
         END;
       END;
    | segData:
      ASSERT(FALSE, 147);

    | segConst:
      AlignAdr(constx, MaxConst); (* zero out the bytes too. *)

    | segCase:
      AlignAdr(casex, MaxCase);(* zero out the bytes too. *)

    | segTypeDesc:
      AlignAdr(typedescx, MaxTypeDesc);
    END;
  END Align;

  PROCEDURE FindPtrs*(type : ST.Type; adr : LONGINT;
                      VAR tab : ARRAY OF LONGINT; VAR last : INTEGER);
    VAR fld : ST.Symbol; base : ST.Type; i, n : LONGINT; last1 : INTEGER;

    PROCEDURE Add(adr: LONGINT);
    BEGIN
      IF last < LEN(tab) THEN
        tab[last] := adr;
        INC(last);
      END;
    END Add;

  BEGIN
    IF type.form = ST.pointer THEN
      Add(adr);
    ELSIF type.form = ST.record THEN
      base := type(ST.Record).ancestor;
      IF base # NIL THEN
        FindPtrs(base, adr, tab, last)
      END;
      fld := ST.FirstField(type(ST.Record));
      WHILE fld # NIL DO
        FindPtrs(fld.type, fld.adr + adr, tab, last);
        fld := ST.NextField(fld);
      END
    ELSIF type.form = ST.array THEN
      base := type(ST.Array).of;
      n := type(ST.Array).n;
      WHILE base.form = ST.array DO
        n := base(ST.Array).n * n;
        base := base(ST.Array).of;
      END;
      IF (base.form = ST.pointer) OR (base.form = ST.record) THEN
        last1 := last;
        FindPtrs(base, adr, tab, last);
        IF last # last1 THEN
          i := 1;
          WHILE (i < n) & (last < LEN(tab)) DO
            INC(adr, base.size);
            FindPtrs(base, adr, tab, last);
            INC(i);
          END
        END;
      END;
    END;
  END FindPtrs;

  PROCEDURE ProcessJumpFixups(l : JccInfo);
    VAR relPC, destPC : LONGINT; pf : JccInfo;
  BEGIN
    WHILE l # NIL DO (* ASSERT(l.lab.seg = segCode, 131); *)
      ASSERT(l.disp IN {1, 4});
      relPC := l.pc + l.disp;
      destPC := l.lab.offs - relPC;
      IF l.disp = 1 THEN
        PutByteAt(l.pc, destPC);
      ELSE
        PutLongAt(l.pc, destPC);
      END;
      l := l.next;
    END;
  END ProcessJumpFixups;

  PROCEDURE GenRefPoint*(proc : ST.Symbol);
  BEGIN
    OPM.RefW(OPM.RefPointTag);
    OPM.RefWNum(proc.adr);
    OPM.RefWNum(pc - proc.adr);
  END GenRefPoint;

  PROCEDURE GenRefName*(name : ARRAY OF CHAR);
    VAR ch : CHAR; i, len : INTEGER;
  BEGIN
    len := 0;
    REPEAT ch := name[len];
           INC(len);
    UNTIL ch = 0X;
    DEC(len);
    OPM.RefWNum(len);
    i := 0;
    WHILE i < len DO
      OPM.RefW(name[i]);
      INC(i);
    END;
  END GenRefName;

  PROCEDURE GenRefs*(VAR info : ST.ProcessScopeInfo);
    VAR f : SHORTINT; sym : ST.Symbol;
  BEGIN
    sym := info.sym;
    IF sym.kind IN {ST.var, ST.par, ST.varpar} THEN (* and not register variables,
                                                     * if implemented *)
      f := sym.type.form;
      IF ((f IN {ST.bool, ST.byte, ST.char, ST.sint, ST.int,
                 ST.lint, ST.real, ST.lreal, ST.set, ST.pointer}) OR
          (f = ST.array) & (sym.type(ST.Array).of.form = ST.char) &
          (sym.type.size < 32)) THEN
        OPM.RefW(CHR(sym.kind));
        OPM.RefW(CHR(f));
        OPM.RefWNum(sym.adr);
        GenRefName(sym.name^);
      END;
    END;
  END GenRefs;

  PROCEDURE WStr(s : ARRAY OF CHAR);
    VAR i, index : LONGINT; ch : CHAR;

    PROCEDURE FindStr(VAR s : ARRAY OF CHAR) : LONGINT;
      VAR o : ObjStr; i : LONGINT;
    BEGIN
      ASSERT(ObjectStrings # NIL, 132);
      o := ObjectStrings;
      WHILE (o # ObjectStrings) & (s # o.str^) DO
        o := o.next;
      END;
      IF o # ObjectStrings THEN
        RETURN -o.i;
      ELSE
        NEW(o);
        o.i := ObjectStrings.i + 1;
        o.next := ObjectStrings;
        NEW(o.str, LEN(s));
        COPY(s, o.str^);
        ObjectStrings := o;
        RETURN o.i;
      END;
    END FindStr;

  BEGIN
    index := FindStr(s);
    OPM.ObjWNum(index);
    IF index > 0 THEN
      i := 0;
      ch := s[0];
      WHILE ch # 0X DO
        INC(i);
        ch := s[i];
      END;
      OPM.ObjWNum(i); (* length prefix of bytes written (excluding terminating 0X) *)
      i := 0;
      ch := s[0];
      WHILE ch # 0X DO
        OPM.ObjW(ch);
        INC(i);
        ch := s[i];
      END;
    END;
  END WStr;

  PROCEDURE WSymbolName(sym : ST.Symbol);
    VAR
      l : LONGINT;
      name : OPS.FullName;
  BEGIN
    IF sym.kind = ST.tproc THEN
      ST.GetFullProcedureName(sym(ST.SymbolProc), name);
      l := 0;
      LOOP
        IF l >= LEN(name) THEN
          EXIT;
        ELSIF name[l] = OPM.HiddenNameSentinel THEN
          name[l] := 0X;
          EXIT;
        END;
        INC(l);
      END;
      WStr(name);
    ELSE
      WStr(sym.name^);
    END;
  END WSymbolName;

  PROCEDURE ^ Export(VAR info : ST.ProcessScopeInfo);
  PROCEDURE WType(sym : ST.Symbol; VAR info : ObjScopeInfo);
    VAR
      f : SHORTINT;
      typesym : ST.Symbol;
      type : ST.Type;
  BEGIN
    type := sym.type;
    typesym := type.sym;
    IF ST.HasTD(type) & (typesym = sym) THEN (* not an alias *)
      ASSERT(type.mno = 0);                  (* Not imported, not nested. *)
      IF (typesym.name^ # "") & (type.ref # OPM.nofTypeMax) THEN
        (* named & exported; entires in module desc: pbfp & pvfp *)
        INC(info.nofexp);
        OPM.ObjW(Estruc);
        WSymbolName(typesym);
        IE.FPrintType(type);
        OPM.ObjWNum(type.pbfp);
        OPM.ObjWNum(type.pvfp);
      END;
      IF type.form = ST.record THEN
        ST.ProcessScope(type(ST.Record).scope, Export, info);
      END;
    END;
  END WType;

  PROCEDURE Use(VAR info : ST.ProcessScopeInfo);
    VAR type : ST.Type; typesym, sym : ST.Symbol;
  BEGIN
    sym := info(ObjScopeInfo).sym;
    IF ST.used IN sym.flags THEN
      IE.FPrintSymbol(sym);
      sym.adr := info(ObjScopeInfo).useIndex; (* Written to symbol file. *)
      INC(info(ObjScopeInfo).useIndex);

      CASE sym.kind OF
      |  ST.const:
         OPM.ObjW(Uconst);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.type:
         OPM.ObjW(Utype);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);
         type := sym.type;
         typesym := type.sym;
         IF ST.HasTD(type) & (typesym = sym) THEN
           IE.FPrintType(type);
           IF typesym.name^ # "" THEN
             (* not only Record, e.g. non-exported dereferenced external array *)
             IF ST.pvused IN type.flags THEN
               OPM.ObjW(Upvstruc);
               WSymbolName(typesym);
               OPM.ObjWNum(type.pvfp);
               IF sym.history = ST.inconsistent THEN
                 OPM.err(EL.FprintInconsistent);
               END;
             ELSIF ST.pbused IN type.flags THEN
               OPM.ObjW(Upbstruc);
               WSymbolName(typesym);
               OPM.ObjWNum(type.pbfp);
             END;
             (* ELSE fp already checked *)
           END;
         END;
         IF ST.HasTD(type) & (typesym = sym) THEN
           IF type.form = ST.record THEN
             ST.ProcessScope(type(ST.Record).scope, Use, info);
           END;
         END;

      |  ST.var:
         OPM.ObjW(Uvar);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.xproc, ST.iproc:
         OPM.ObjW(Uxproc);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.tproc:
         OPM.ObjW(Uxproc);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.cproc:
         OPM.ObjW(Ucproc);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.recdesc:
         OPM.ObjW(Urectd);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.darrdesc:
         OPM.ObjW(Udarrtd);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);

      |  ST.arrdesc:
         OPM.ObjW(Uarrtd);
         WSymbolName(sym);
         OPM.ObjWNum(sym.fprint);
      ELSE (* NOP *)
      END;
    END;
  END Use;

  PROCEDURE FindNewMethods(VAR info : ST.ProcessScopeInfo);
    VAR sym : ST.Symbol;
  BEGIN
    sym := info.sym;
    IF sym.kind = ST.tproc THEN
      info(MethodScopeInfo).tab[info(MethodScopeInfo).nofnewmeth] := sym(ST.SymbolProc);
      INC(info(MethodScopeInfo).nofnewmeth);
    END;
  END FindNewMethods;

  PROCEDURE TypeDescriptors(VAR info : ST.ProcessScopeInfo);
    VAR sym : ST.Symbol;

    PROCEDURE Brand(type : ST.Type);
    BEGIN
      type.ref := -info(ObjScopeInfo).nofdesc - 1;
      INC(info(ObjScopeInfo).nofdesc);
    END Brand;

    PROCEDURE WRecTD(td : ST.RecordTD);
      VAR type, ancestor : ST.Record; nofinhmth, recptr, i : INTEGER;
      ancestorTD : ST.SymbolTypeDesc;
      RecTab :  ARRAY OPM.RecMaxPtrs + 1 OF LONGINT;
      methinfo : MethodScopeInfo;

    BEGIN
      type := td.described(ST.Record);
      IF type.ref >= 0 THEN
        Brand(type);
        ancestor := type.ancestor;
        OPM.ObjW(Trec);
        IF type.sym # NIL THEN
          WSymbolName(type.sym);
          IF type.sym.name^ = "" THEN
            IE.FPrintType(type);
            OPM.ObjWNum(type.pvfp);
          END;
        ELSE
          WStr('');
        END;
        OPM.ObjWNum(type.size);
        IF ancestor = NIL THEN
          nofinhmth := 0;
          OPM.ObjWNum(-1);
        ELSE
          ancestorTD := ST.GetTD(ancestor);
          nofinhmth := SHORT(ancestor.nofmeth);
          IE.FPrintSymbol(ancestorTD);
          OPM.ObjWNum(ancestor.mno);
          WSymbolName(ancestorTD);
          OPM.ObjWNum(ancestorTD.fprint);
          (* extension table of base td copied by loader *)
        END;
        OPM.ObjWNum(type.nofmeth);
        OPM.ObjWNum(nofinhmth);
        methinfo.nofnewmeth := 0;
        ST.ProcessScope(type.scope, FindNewMethods, methinfo);
        OPM.ObjWNum(methinfo.nofnewmeth);
        recptr := 0;
        FindPtrs(type, 0, RecTab, recptr);
        IF recptr >= LEN(RecTab) THEN
          OPM.err(EL.TooManyRecordPointers);
        END;
        OPM.ObjWNum(recptr);
        WHILE methinfo.nofnewmeth > 0 DO
          DEC(methinfo.nofnewmeth);
          OPM.ObjWNum(methinfo.tab[methinfo.nofnewmeth].methno);
          OPM.ObjWNum(methinfo.tab[methinfo.nofnewmeth].adr);
        END;
        i := 0;
        WHILE i < recptr DO
          OPM.ObjWNum(RecTab[i]);
          INC(i);
        END; (* pointer offsets *)
      END;
    END WRecTD;

    PROCEDURE WArrayTD(td : ST.ArrayTD);
      VAR type, element : ST.Type; nofDim : LONGINT; f : SHORTINT; tdSym : ST.SymbolTypeDesc;
    BEGIN
      type := td.described; nofDim := 1;
      IF type.ref >= 0 THEN
        Brand(type);
        OPM.ObjW(Tarray);
        WSymbolName(td);
        OPM.ObjWNum(td.fprint);
        element := type(ST.Array).of;
        WHILE element.form = ST.array DO
          INC(nofDim);
          element := element(ST.Array).of;
        END;
        f := element.form;
        IF f IN {ST.bool, ST.byte, ST.char, ST.sint, ST.int,
                 ST.lint, ST.real, ST.lreal, ST.set, ST.procedure} THEN
          OPM.ObjW(1X);
          OPM.ObjWNum(f);
        ELSIF f = ST.pointer THEN
          OPM.ObjW(2X);
          OPM.ObjWNum(f);
        ELSE
          ASSERT(f = ST.record);
          OPM.ObjW(3X);
          OPM.ObjWNum(element.mno);
          tdSym := ST.GetTD(element);
          WSymbolName(tdSym);
          OPM.ObjWNum(tdSym.fprint);
        END;
        OPM.ObjWNum(nofDim);
        element := type;
        WHILE element.form = ST.array DO
          OPM.ObjWNum(element(ST.Array).n);
          element := element(ST.Array).of;
        END; (* write LEN(arr, n) *)
      END;
    END WArrayTD;

    (* This duplicates some effort spend in CGH.DynArrTD --
     * if array type descriptors are not initialized by
     * generated code, then they can be handled by the loader
     * by using the type descriptor information
    *)
    PROCEDURE WDynArrayTD(td : ST.ArrayTD);
      VAR type, eltype, arrtype : ST.Type;
          f : SHORTINT; nofDim : LONGINT; tdSym : ST.SymbolTypeDesc;
    BEGIN
      type := td.described;
      IF type.ref >= 0 THEN
        Brand(type);
        OPM.ObjW(Tdarray);
        WSymbolName(td);
        OPM.ObjWNum(td.fprint);
        eltype := type(ST.Array).of;
        WHILE eltype.form = ST.dynarr DO
          eltype := eltype(ST.Array).of;
        END;
        f := eltype.form;

        IF f IN {ST.bool, ST.byte, ST.char, ST.sint, ST.int,
                 ST.lint, ST.real, ST.lreal, ST.set, ST.procedure} THEN
          OPM.ObjW(1X);
          OPM.ObjWNum(type(ST.Array).n + 1);
          OPM.ObjWNum(f);
        ELSIF f = ST.pointer THEN
          OPM.ObjW(2X);
          OPM.ObjWNum(type(ST.Array).n + 1);
          OPM.ObjWNum(f);
        ELSIF f = ST.record THEN
          OPM.ObjW(3X);
          OPM.ObjWNum(type(ST.Array).n + 1);
          OPM.ObjWNum(eltype.mno);
          tdSym := ST.GetTD(eltype);
          WSymbolName(tdSym);
          OPM.ObjWNum(tdSym.fprint);
        ELSIF f = ST.array THEN
          OPM.ObjW(4X);
          OPM.ObjWNum(type(ST.Array).n + 1);
          arrtype := eltype;
          nofDim := 0;
          WHILE arrtype.form = ST.array DO
            arrtype := arrtype(ST.Array).of;
            INC(nofDim);
          END;
          f := arrtype.form;
          IF f IN {ST.bool, ST.byte, ST.char, ST.sint, ST.int,
                   ST.lint, ST.real, ST.lreal, ST.set, ST.procedure} THEN
            OPM.ObjW(0X);
            OPM.ObjWNum(f);
          ELSIF f = ST.pointer THEN
            OPM.ObjW(1X);
            OPM.ObjWNum(f);
          ELSE
            ASSERT(f = ST.record);
            OPM.ObjW(2X); (* array n of record tag *)
            OPM.ObjWNum(arrtype.mno);
            tdSym := ST.GetTD(arrtype);
            WSymbolName(tdSym);
            OPM.ObjWNum(tdSym.fprint);
          END;
          OPM.ObjWNum(nofDim);
          arrtype := eltype;
          WHILE arrtype.form = ST.array DO
            OPM.ObjWNum(arrtype(ST.Array).n);
            arrtype := arrtype(ST.Array).of;
          END; (* write LEN(arr, n) *)
        END;
      END;
    END WDynArrayTD;

  BEGIN
    sym := info.sym;
    CASE sym.kind OF
    |  ST.arrdesc:
       WArrayTD(sym(ST.ArrayTD));

    |  ST.darrdesc:
       WDynArrayTD(sym(ST.ArrayTD));

    |  ST.recdesc:
       WRecTD(sym(ST.RecordTD));
    ELSE (* not a type descriptor *)
    END;
  END TypeDescriptors;

  PROCEDURE Private(VAR info : ST.ProcessScopeInfo);
    VAR sym : ST.Symbol;
  BEGIN
    sym := info.sym;
    IF (sym.vis IN {ST.hidden, ST.internal}) THEN (* internal or a type descriptor *)
      CASE sym.kind OF
      |  ST.var:
         FindPtrs(sym.type, sym.adr, info(ObjScopeInfo).PtrTab, info(ObjScopeInfo).nofptr);
      ELSE (* if a procedure and it's address is not 0, then mark *)
      END;
    END;
  END Private;

  PROCEDURE Export(VAR info : ST.ProcessScopeInfo);
    VAR
      proc : ST.Procedure;
      f : Fixup;
      sym : ST.Symbol;
      localTBP : BOOLEAN;
      exported : BOOLEAN;
      hasAddress : BOOLEAN;
      constAddress : BOOLEAN;
  BEGIN
    sym := info.sym;
    IF sym.history # ST.removed THEN
      exported := sym.vis IN {ST.hidden, ST.export, ST.exportR};
      localTBP := (sym.kind = ST.tproc) & (sym.vis = ST.internal);
      IF (exported OR localTBP) & (sym.mnolev = 0) THEN
        IE.FPrintSymbol(sym);
        CASE sym.kind OF
        |  ST.const:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Econst);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);

        |  ST.type:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Etype);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);
           WType(sym, info(ObjScopeInfo));

        |  ST.darrdesc:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Edarraytd);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);

        |  ST.arrdesc:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Earraytd);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);

        |  ST.recdesc:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Erectd);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);

        |  ST.var:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Evar);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);
           FindPtrs(sym.type, sym.adr, info(ObjScopeInfo).PtrTab,
                    info(ObjScopeInfo).nofptr);

        |  ST.xproc, ST.iproc, ST.tproc:
           IF ~(ST.intrinsic IN sym.flags) THEN
             INC(info(ObjScopeInfo).nofexp);
             OPM.ObjW(Exproc);
             WSymbolName(sym);
             OPM.ObjWNum(sym.fprint);
             proc := sym.type(ST.Procedure);

             (* inv: A ST.tproc symbol will have at least one argument. *)
             IF (proc.parms = NIL) & (proc.result.form = ST.void) THEN (* command *)
               IF info(ObjScopeInfo).nofcom < OPM.MaxCommands THEN
                 info(ObjScopeInfo).ComTab[info(ObjScopeInfo).nofcom] := sym;
                 INC(info(ObjScopeInfo).nofcom);
               ELSE
                 OPM.err(EL.TooManyCommands);
                 info(ObjScopeInfo).nofcom := 0;
              END;
             END;
           END;

        |  ST.cproc:
           INC(info(ObjScopeInfo).nofexp);
           OPM.ObjW(Ecproc);
           WSymbolName(sym);
           OPM.ObjWNum(sym.fprint);
        ELSE
          (* nop *)
        END;

        (* If the exported symbol has an address or it is one of
         * the few types of constants that actually are allocated to
         * memory, then make a fixup into the export table.
         * 97.09.07: only string constants are allocated memory. *)

        constAddress := (sym.kind = ST.const) & (sym.type = ST.stringtyp);
        hasAddress   := (sym.kind IN {ST.darrdesc, ST.arrdesc, ST.recdesc,
                                      ST.var, ST.xproc, ST.iproc, ST.tproc});
        IF (hasAddress OR constAddress) & ~(ST.intrinsic IN sym.flags) THEN
          f := NewFixup(FixAbs, segExport, info(ObjScopeInfo).nofexp - 1);
          SetFixupSym(f, sym);
        END;
      END;
    END;
  END Export;

  PROCEDURE OutCode*(VAR module : ARRAY OF CHAR);
    VAR
      i : INTEGER;
      sym : ST.Symbol;
      info : ObjScopeInfo;

    PROCEDURE Helpers(fixup : FixupHelper);
      VAR loc : FixupHelperLocation;
    BEGIN
      WHILE fixup # NIL DO
        INC(info.nofhlp);
        WStr(fixup.module);
        WStr(fixup.function);
        loc := fixup.loc;
        WHILE loc # NIL DO
          OPM.ObjWNum(loc.offs);
          loc := loc.next;
        END;
        OPM.ObjWNum(-1);
        fixup := fixup.next;
      END;
    END Helpers;

    PROCEDURE Fixups(fixup : Fixup);
    BEGIN
      WHILE fixup # NIL DO
        INC(info.noffix);
        ASSERT(fixup.segment IN {segCode, segConst, segCase, segData,
                                 segExport, segCommand, segTypeDesc, segTDesc}, 130);
        ASSERT(fixup.toffs # MAX(LONGINT), 131); (* unallocated address *)
        OPM.ObjWNum(fixup.mode);
        OPM.ObjWNum(fixup.segment);
        OPM.ObjWNum(fixup.toffs);

        CASE fixup.mode OF
        | FixAbs, FixRel:
          ASSERT((fixup.sym = NIL) # (fixup.lab = NIL), 1280);
          IF fixup.sym # NIL THEN (* symbol fixup *)
            ASSERT((fixup.sym.mnolev <= 0) OR (fixup.sym.kind = ST.lproc), 150);
            OPM.ObjW(1X);
            OPM.ObjWNum(AllocSeg[fixup.sym.kind]);
            IF fixup.sym.mnolev <= 0 THEN
              OPM.ObjWNum(fixup.sym.mnolev);
            ELSE
              OPM.ObjWNum(0); (* local procedure *)
            END;
            ASSERT(fixup.sym.adr + fixup.doffs # MAX(LONGINT), 160); (* unallocated address *)
            OPM.ObjWNum(fixup.sym.adr + fixup.doffs);
          ELSE (* label fixup *)
            OPM.ObjW(2X);
            OPM.ObjWNum(fixup.lab.seg);
            OPM.ObjWNum(fixup.lab.offs + fixup.doffs);
          END;

        | FixBlk:
          ASSERT((fixup.sym = NIL) & (fixup.lab = NIL));
          OPM.ObjWNum(fixup.doffs);
        END;
        fixup := fixup.next;
      END;
    END Fixups;

    PROCEDURE Commands;
      VAR i : INTEGER; f : Fixup;
    BEGIN
      i := 0;
      WHILE i < info.nofcom DO
        sym := info.ComTab[i];
        WSymbolName(sym);
        f := NewFixup(FixAbs, segCommand, i);
        SetFixupSym(f, sym);
        INC(i);
      END;
    END Commands;

  BEGIN
    ProcessJumpFixups(JccFixupList);
    Align(segCode, 4); Align(segConst, 4);
    info.nofexp := 0;
    info.nofprv := 0;
    info.nofdesc := 0;
    info.nofcom := 0;
    info.nofptr := 0;
    info.nofhlp := 0;
    info.noffix := 0;
    (* header block *) OPM.ObjW(80X);
    OPM.ObjWLInt(0); (* ref size *)
    OPM.ObjWLInt(0); (* nofexp *)
    OPM.ObjWLInt(0); (* nofprv *)
    OPM.ObjWLInt(0); (* nofdesc *)
    OPM.ObjWLInt(0); (* nofcom *)
    OPM.ObjWLInt(0); (* nofptr *)
    OPM.ObjWLInt(0); (* nofhlp *)
    OPM.ObjWLInt(0); (* noffix *)
    OPM.ObjWLInt(pc);
    OPM.ObjWLInt(-ST.topScope(ST.SymbolScope).dsize);
    OPM.ObjWLInt(constx);
    OPM.ObjWLInt(typedescx);
    OPM.ObjWLInt(casex);
    OPM.ObjWLInt(exportx);
    OPM.ObjWLInt(ST.nofGmod - 1); (* number of imports *)
    WStr(module);
    (* imports *) OPM.ObjW(81X);
    i := 1;
    WHILE i < ST.nofGmod DO
      WSymbolName(ST.GlbMod[i]);
      INC(i);
    END;

    (* exports *) OPM.ObjW(82X);
    ST.ProcessScope(ST.topScope, Export, info); (* Export objects, collect
                                                 * commands & pointers. *)

    (* privates *) OPM.ObjW(83X);
    ST.ProcessScope(ST.topScope, Private, info);

    (* type info *) OPM.ObjW(84X);
    ST.ProcessScope(ST.topScope, TypeDescriptors, info);

    (* commands *) OPM.ObjW(85X);
    Commands;

    (* pointers *) OPM.ObjW(86X);
    i := 0;
    WHILE i < info.nofptr DO
      OPM.ObjWNum(info.PtrTab[i]);
      INC(i);
    END;

    (* constants *) OPM.ObjW(87X);
    OPM.ObjWBytes(ConstTab^, constx);

    (* type descriptors *) OPM.ObjW(88X);
    OPM.ObjWBytes(TypeDescTab^, typedescx);

    (* code *) OPM.ObjW(89X);
    OPM.ObjWBytes(CodeTab^, pc);

    (* uses *) OPM.ObjW(8AX);
    i := 1;
    info.useIndex := 0;
    WHILE i < ST.nofGmod DO
      ST.ProcessScope(ST.GlbMod[i], Use, info);
      OPM.ObjW(0X);
      INC(i);
    END;

    (* compiler helper fixups *) OPM.ObjW(8BX);
    Helpers(FixupHelperList);

    (* fixups *) OPM.ObjW(8CX);
    Fixups(FixupList);

    (* references block written in OPM.RegisterRefObj*)
    OPM.RegisterRefObj(info.nofexp, info.nofprv, info.nofdesc,
                       info.nofcom, info.nofptr, info.nofhlp, info.noffix);
  END OutCode;


  PROCEDURE NILGlobalPointers;
  BEGIN
    LabelList := NIL;
    FixupList := NIL;
    JccFixupList := NIL;
    FixupHelperList := NIL;
    CaseTab := NIL;
    CodeTab := NIL;
    ConstTab := NIL;
    TypeDescTab := NIL;
    ObjectStrings := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin*;
    VAR i : INTEGER;
  BEGIN
    pc := 0;
    constx := 0;
    typedescx := 0;
    casex := 0;
    exportx := 0;
    NILGlobalPointers;
    i := 0;
    WHILE i < LEN(FReg) DO
      FReg[i] := 0;
      INC(i);
    END;
    NEW(CaseTab);
    NEW(CodeTab);
    NEW(ConstTab);
    NEW(TypeDescTab);
    NEW(ObjectStrings);
    ObjectStrings.next := NIL;
    ObjectStrings.i := 0;
    NEW(ObjectStrings.str, 1);
    ObjectStrings.str[0] := 0X; (* dummy header; do not use this entry *)
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN
    NILGlobalPointers;
  END ModuleEnd;

BEGIN

  AllocSeg[ST.anon] := segUndef;
  AllocSeg[ST.var] := segData;
  AllocSeg[ST.par] := segUndef;
  AllocSeg[ST.varpar] := segUndef;
  AllocSeg[ST.const] := segConst;
  AllocSeg[ST.stdproc] := segUndef;
  AllocSeg[ST.fwdproc] := segUndef;
  AllocSeg[ST.lproc] := segCode;
  AllocSeg[ST.xproc] := segCode;
  AllocSeg[ST.cproc] := segCode;
  AllocSeg[ST.iproc] := segCode;
  AllocSeg[ST.tproc] := segCode;
  AllocSeg[ST.field] := segUndef;
  AllocSeg[ST.type] := segUndef;
  AllocSeg[ST.module] := segCode;
  AllocSeg[ST.scope] := segUndef;
  AllocSeg[ST.darrdesc] := segTypeDesc;
  AllocSeg[ST.arrdesc] := segTypeDesc;
  AllocSeg[ST.recdesc] := segTypeDesc;
END SKLCGL.
