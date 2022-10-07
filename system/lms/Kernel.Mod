(* Copyright (c) 1997-2000, 2021-2022 Logic Magicians Software *)
 MODULE Kernel; (* 97.01.20 *)
  IMPORT SYSTEM;

  TYPE
    ADDRESS* = LONGINT;

  CONST (* heap management *)
    hmBlockSize* = 10H; (* integral size (bytes) of allocated memory blocks;
                         * strongly tied to compiler code generation *)
    hmHeapChains = 6; (* number of different block sizes kept on free lists *)
    hmTagSize* = SIZE(ADDRESS); (* size (bytes) of block tag *)
    hmPtrTagOffs* = -SIZE(LONGINT); (* offset to block tag, given a pointer *)
    hmDescFlagsOffs* = 0; (* offset to the descriptor flags in a type descriptor *)

    (* BlkFree: offsets  *)
    bfLinkOffs* = 4; (* offset (bytes) to next-block-on-list field
                      * in a BlkFree; given the address of the block tag *)

    (* GC: Block Tag Flags *)
    (* Tag(q) <=> (q = pointer => mem[q - SIZE(ADDRESS]) & (q = ADR(memory block ) => mem[q]) *)
    (* BlkRecord(q) <=> Tag(q) * {BlkSyst, BlkFree, BlkAray} = {} *)
    (* BlkArray(q) <=> Tag(q) * {BlkSyst, BlkFree, BlkAray} = {BlkAray} *)
    BlkDesc* = -1; (* no other bits set in the tag field indicates a type descriptor *)
    BlkMark* = 0;
    BlkSyst* = 1;
    BlkFree* = 2;
    BlkAray* = 3;
    BlkFlags* = {BlkMark, BlkSyst, BlkFree, BlkAray};

  (* TD: descriptor flag info; must match LMMD & compiler generated type descriptors.
   * See compiler documentation for description  *)
    DescFlagsValidBit* = 30; (* A real descriptor flag & not a pointer offset.
                              * See documentation for Memory Layout and block tags.
                              *)
    DescFlagsSignBit*  = 31; (* if present, then DescFlagsValidBit has no
                              *  meaning.  See documentation as for bit 30.
                              *)
    DescFlagsRecord* = 0;
    DescFlagsDynArray0* = 1;
    DescFlagsDynArray1* = 2;
    DescFlagsDynArray2* = 3;
    DescFlagsDynArray3* = 4;
    DescFlagsDynArray4* = 5;
    DescFlagsDynArray5* = 6;
    DescFlagsStaticArray0* =7;
    DescFlagsStaticArray1* = 8;
    DescFlagsStaticArray2* = 9;
    DescNofArrayType = 10;

    SimpleElemSet* = {DescFlagsDynArray0,
                      DescFlagsDynArray3,
                      DescFlagsStaticArray0}; (* element is a simple or procedure type *)
    PointerElemSet* = {DescFlagsDynArray1,
                       DescFlagsDynArray4,
                       DescFlagsStaticArray1}; (* element is a pointer type *)
    RecordElemSet* = {DescFlagsDynArray2,
                      DescFlagsDynArray5,
                      DescFlagsStaticArray2}; (* element is a record type *)

    (* pointer to dynarr: simple elem offsets *)
    seBlockSize* = 0; (* size of allocated block (in the heap block) *)

    (* pointer to dynarr: common TD offsets *)
    datdFlags* = 0; (* offset to heap flags in TD *)
    datdNofDim* = 8; (* number of array dimensions *)
    datdElemSize* = 12; (* offset to element size *)

    (* pointer to dynarr: array descriptor adjustors base values
     * (see documentation on array block layouts) *)
    seAlpha* = 8;
    peAlpha* = 16;
    reAlpha* = 20;

    (* pointer to dynarr: common array block offsets (array block = block tag address) *)
    daBlockSize* = 4; (* q.blockSize *)
    daNofElem* = 8; (* q.nofElem *)
    daArrPos* = 12; (* q.arrpos *)
    daCnt* = 16; (* q.tdidx *)

    (* pointer to dynarr: common array data offsets *)
    daTD = -4; (* from SYSTEM.ADR(x[0]) *)
    daLen0 = -8; (* from SYSTEM.ADR(x[0]) *)

    (* pointer to dynarr: record elem offsets (in the heap block) *)
    reTD* = 4; (* offset in array TD where the record-element TD is found *)

    (* pointer to statarr: common offsets *)
    saElemSize* = 8; (* offset to element size *)
    saNofDim* = 12; (* number of dimensions *)
    saDim0* = 16; (* 0th dimension *)

    (* pointer to record: offsets into the record type descriptor *)
    rtdRecSize* = 12; (* (unpadded) record size *)
    rtdBlockSize* = 16; (* record (dynamically allocated) block size, in bytes.  Includes block tag *)
    rtdName* = 24; (* offset of pointer to record name *)
    rtdModule* = 28; (* offset of pointer to module descriptor *)
    rtdFinalize* = 32; (* offset to finalization procedure for record; NIL => no finalization set *)
    rtdPtrTabOffs* = 36; (* offset to pointer table *)
    rtdCnt* = hmPtrTagOffs; (* q.idx for RECORD types *)

  CONST (* memory block classes (for fast descrimination of memory blocks in GC) *)
    bcRec = 0; (* pointer to record *)
    bcSmp = seAlpha; (* pointer to array of simple type; GC not performed on blocks of this type *)
    bcAgg = reAlpha; (* aggregate; pointer to (some) array of record *)
    bcPtr = peAlpha; (* pointer to (some) array of pointer *)
    NeedsGC = {bcRec, bcAgg, bcPtr}; (* heap blocks kinds which need GC *)

  TYPE
    GCFindFunctionFn* = PROCEDURE(ip, sfp : ADDRESS) : BOOLEAN;
    GCNextPointerFn*  = PROCEDURE(VAR addr : ADDRESS) : BOOLEAN;

  VAR
    gcFindFunction : GCFindFunctionFn;
    gcNextPointer  : GCNextPointerFn;

  TYPE (* AllocationFailStrategy type *)
    AllocationFailStrategy* = SHORTINT;

  CONST (* AllocationFailStrategy values *)
    afsNIL* = 0;
    afsTRAP* = 1;

  CONST (* time/date *)
    InitialYear = 1990;  (* start year for Oberon dates *)

  TYPE
    Name* = POINTER TO ARRAY OF CHAR;
    ModuleName* = Name;
    Module* = POINTER TO ModuleDesc;

    Cmd* = RECORD
      name* : Name;
      adr* : ADDRESS; (* absolute address *)
    END;

    Export* = RECORD
      name* : Name;
      fprint*, pvfprint* : LONGINT;
      adr* : ADDRESS;  (* absolute address *)
      kind* : INTEGER;
    END;

    ReferenceBlock* = POINTER TO ARRAY OF CHAR;
    DataBlock       = POINTER TO ARRAY OF SYSTEM.BYTE;
    ExportBlock     = POINTER TO ARRAY OF Export;
    ImportBlock     = POINTER TO ARRAY OF Module;
    PointerBlock    = POINTER TO ARRAY OF LONGINT;
    CommandBlock    = POINTER TO ARRAY OF Cmd;
    TDescBlock      = POINTER TO ARRAY OF ADDRESS;
    ModuleDesc* = RECORD
      next*     : Module;
      refcnt*   : LONGINT; (* reference count *)
      sb*       : ADDRESS; (* static base (addr: [data -|sb|+ constants] *)
      finalize* : PROCEDURE; (* finalization procedure when module is unloaded *)
      tdescs*   : TDescBlock; (* absolute addresses of type descriptors *)
      exports*  : ExportBlock; (* items exported from this module *)
      privates* : ExportBlock; (* private symbols of this module *)
      commands* : CommandBlock; (* exported commands of this module *)
      pointers* : PointerBlock; (* data segment offsets of global pointers *)
      imports*  : ImportBlock; (* items imported from other modules *)
      jumps*    : DataBlock; (* case tables *)
      data*     : DataBlock; (* data & constant segment *)
      tddata*   : DataBlock; (* type descriptor data *)
      code*     : DataBlock; (* code segment *)
      refs*     : ReferenceBlock; (* reference block *)
      name*     : Name;
    END;


  CONST (* type descriptor information *)
    nofPointerOffset = 16384; (* compiler-imposed limit; see compiler sources *)

  TYPE (* type descriptor information;
        * not a real type; compiler-data-structure-type
        * never allocate anything of this type
        *)
    TypeDesc* = POINTER TO TypeDescDesc;
    TypeDescDesc* = RECORD
      flags* : SET; (* flags which describe the descriptor; see compiler documentation *)
      ancestor* : ADDRESS;
      extLev* : LONGINT; (* extension level *)
      size* : LONGINT; (* unpadded record size *)
      blockSize* : LONGINT; (* memory block size for this record *)
      nofPointers* : LONGINT;
      name* : ADDRESS; (* pointer to record 0X terminated record name *)
      module* : ADDRESS; (* pointer to Modules.Module descriptor for module which owns this record *)
      finalization* : ADDRESS; (* procedure *)
      pointers* : ARRAY nofPointerOffset OF LONGINT; (* (Ai: 0 <= i < Module.nofPointers: valid(Module.pointers[i])) *)
    END;

  CONST (* Hardware trap info. *)
    (* SKL VM *) HaltInvalidOpCode* = 0;     (* Invalid Opcode. *)
    (* SKL VM *) HaltBreak* = 1;             (* 'break' instruction. *)
    (* SKL VM *) HaltAlignment* = 2;         (* Bad alignment. *)
    (* SKL VM *) HaltReadAccess* = 3;        (* Read out-of-bounds memory. *)
    (* SKL VM *) HaltWriteAccess* = 4;       (* Write out-of-bounds memory. *)
    (* SKL VM *) HaltDivideByZero* = 5;      (* Divide by Zero. *)
    (* SKL VM *) HaltReserved0* = 6;         (* Reserved. *)
    (* SKL VM *) HaltReserved1* = 7;         (* Reserved. *)

  CONST (* Language trap info. *)
    (* OPM *) HaltAssert* = 8;
    (* OPM *) HaltRange* = 12;
    (* OPM *) HaltArray* = 13;
    (* OPM *) HaltIGuard* = 14;
    (* OPM *) HaltEGuard* = 15;
    (* OPM *) HaltCase* = 16;
    (* OPM *) HaltFunc* = 17;
    (* OPM *) HaltWith* = 18;
    (* OPM *) HaltGuardCheck* = 19; (* NIL pointer used in type guard *)
    (* OPM *) HaltPointerCheck* = 20; (* NIL pointer dereferenced *)
    (* Files *) HaltFileIO* = 128;

  (* Do not declare a pointer to this type, or change its name, without
   *  updating the bootstrap loader to deal with its type descriptor. *)
  TYPE (* hardware trap info buffer for swapping info with bootstrap loader *)
    TrapInfo = RECORD
      trap : LONGINT;
      ip, sp, sfp : LONGINT;
      regs : ARRAY 32 OF LONGINT;
    END;

  TYPE
    TerminatorProc* = PROCEDURE (exitcode : LONGINT);
    LoopProc* = PROCEDURE;
    SysTrapProc* = PROCEDURE(trap : LONGINT; ip, sfp : ADDRESS);
    HwdTrapProc* = PROCEDURE(ip, sfp, cr2 : LONGINT);

   VAR
     CmdLine : ADDRESS;         (* Address of 'System Block' holding command line. *)

  VAR (* Time management *)
    SetClockProc* : PROCEDURE (time, date : LONGINT); (* to use a wrapped function which interacts with the OS *)
    GetClockProc* : PROCEDURE (VAR time, date : LONGINT); (* to use a wrapped function which interacts with the OS *)

  TYPE
    MemoryRegionDesc = RECORD
      beg- : ADDRESS;           (* [beg, end) *)
      end- : ADDRESS;
      size : LONGINT;           (* Size, in bytes. *)
    END;

    HeapInfoDesc = RECORD
      region     : MemoryRegionDesc;
      allocated- : LONGINT; (* Number of bytes allocated from heap. *)
      blocks     : ARRAY hmHeapChains + 1 OF ADDRESS; (* 16, 32, 48, 64,
                                                       * 80, 96, >96 byte blocks
                                                       *)
    END;

  VAR (* Heap management *)
    GCActive- : BOOLEAN;
    stack-    : MemoryRegionDesc;
    heap-     : HeapInfoDesc;

  VAR (* Trap management *)
      pc-, sb-, fp- : ADDRESS; (*PC, static basic, frame pointer: status upon trap*)
      halt- : LONGINT; (* INT 3 halt number *)
      err- : INTEGER;

  VAR
    FontRoot* : ADDRESS; (* pointer to Fonts.root *)
    mlist* : ADDRESS; (* list of currently loaded modules (same as Modules.modules & used by Modules) *)
    MainLoop : LoopProc; (* Oberon.Loop address *)
    TerminationProc : TerminatorProc;


  CONST (* VMServiceDesc services *)
    VMSVCBootstrap*    = 0;  (* Trap back to interpreter for bootstrap. *)
    VMSVCTrace         = 1;  (* Enable and disable tracing *)
    VMSVCEarlySysTrap  = 2;  (* SysTrap before system bootstrapped. *)
    VMSVCDebugLog      = 3;  (* Bootstrap debugging output. *)
    VMSVCTerminate*    = 4;  (* Terminate VM *)
    VMSVCTime*         = 5;  (* Timekeeping. *)
    VMSVCDirectory*    = 6;  (* Directory Handling. *)
    VMSVCFile*         = 7;  (* File handling. *)
    VMSVCConsole*      = 8;  (* Console I/O. *)
    VMSVCFillMemory    = 9;  (* Fill memory. *)
    VMSVCEarlyHwdTrap  = 10; (* HwdTrap before system bootstrapped. *)
    VMSVCEnvironment*  = 11; (* Get host OS' shell environment value. *)

  TYPE
    VMServiceDesc* = RECORD
      service* : LONGINT;
    END;

    VMServiceTerminateDesc = RECORD (VMServiceDesc)
      rc : LONGINT;             (* Return code back to OS. *)
    END;

    VMServiceSysTrapDesc = RECORD (VMServiceDesc)
      ip   : LONGINT;
      sfp  : LONGINT;
      trap : LONGINT;
    END;

    VMServiceHwdTrapDesc = RECORD (VMServiceDesc)
      ip   : LONGINT;
      sfp  : LONGINT;
      trap : LONGINT;
      cr2 : LONGINT;
    END;

    VMServiceTraceDesc = RECORD (VMServiceDesc)
      traceEnable : BOOLEAN;
      (* TODO: Allow controlling registers, stack and core *)
    END;

    VMServiceFillMemoryDesc = RECORD (VMServiceDesc)
      adr  : LONGINT;         (* Address at which fill starts. *)
      size : LONGINT;         (* Number of 4-byte words. *)
      val  : LONGINT;         (* Value to fill memory with. *)
    END;

  CONST (* VMServiceLogDesc operations*)
    VMSVCLogCh     = 0;
    VMSVCLogString = 1;
    VMSVCLogBool   = 2;
    VMSVCLogHex    = 3;
    VMSVCLogInt    = 4;
    VMSVCLogLn     = 5;
    VMSVCLogChHex  = 6;

  TYPE
    VMServiceLogDesc = RECORD (VMServiceDesc)
      op   : LONGINT;             (* operation *)
      data : LONGINT;
      adr  : ADDRESS;
    END;


  VAR
    BlockClass : ARRAY DescNofArrayType OF SHORTINT;
    SysTrapHandler : SysTrapProc;
    HwdTrapHandler : HwdTrapProc;
    AFS : AllocationFailStrategy;


  PROCEDURE - InstCount 02H, 00H, 20H, 10H;
  PROCEDURE InstructionCount*() : LONGINT;
    VAR result : LONGINT;
  BEGIN
    InstCount;
    SYSTEM.GETREG(1, result);
    RETURN result;
  END InstructionCount;

  PROCEDURE - VMSVC 03H, 00H, 01H, 14H;

  (* No function using VMService should be ever allocate memory.
   * This is to ensure they can continue to be executed during
   * a GC.
   *)
  PROCEDURE VMService*(    service : LONGINT; (* VMServiceDesc service *)
                       VAR block   : VMServiceDesc);
  BEGIN
    block.service := service;
    SYSTEM.PUTREG(1, SYSTEM.ADR(block));
    VMSVC;
  END VMService;


  PROCEDURE VMSVCTracing*(enable : BOOLEAN);
    VAR
      vmsvc : VMServiceTraceDesc;
  BEGIN
    vmsvc.traceEnable := enable;
    VMService(VMSVCTrace, vmsvc);
  END VMSVCTracing;


  (* --- begin Kernel Debugging --- *)
  PROCEDURE ^ GetBlockSize(q : ADDRESS) : LONGINT;

  PROCEDURE VMSVCDebug(VAR svc : VMServiceLogDesc);
  BEGIN
    VMService(VMSVCDebugLog, svc);
  END VMSVCDebug;

  PROCEDURE DebugCh*(ch : CHAR);
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op   := VMSVCLogCh;
    svc.data := ORD(ch);
    VMService(VMSVCDebugLog, svc);
  END DebugCh;

  PROCEDURE DebugStr*(s : ARRAY OF CHAR);
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op   := VMSVCLogString;
    svc.data := LEN(s);
    svc.adr  := SYSTEM.ADR(s[0]);
    VMService(VMSVCDebugLog, svc);
  END DebugStr;

  PROCEDURE DebugBool*(b : BOOLEAN);
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op   := VMSVCLogBool;
    svc.data := SYSTEM.VAL(SHORTINT, b);
    VMService(VMSVCDebugLog, svc);
  END DebugBool;

  PROCEDURE DebugHex*(x : LONGINT);
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op   := VMSVCLogHex;
    svc.data := x;
    VMService(VMSVCDebugLog, svc);
  END DebugHex;

  PROCEDURE DebugPtr*(x : SYSTEM.PTR);
  BEGIN
    IF x = NIL THEN DebugStr('NIL');
    ELSE DebugHex(SYSTEM.VAL(LONGINT, x));
    END;
  END DebugPtr;

  PROCEDURE DebugInt*(x : LONGINT);
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op   := VMSVCLogInt;
    svc.data := x;
    VMService(VMSVCDebugLog, svc);
  END DebugInt;

  PROCEDURE DebugLn*;
    VAR
      svc : VMServiceLogDesc;
  BEGIN
    svc.op := VMSVCLogLn;
    VMService(VMSVCDebugLog, svc);
  END DebugLn;

  PROCEDURE DebugChHex*(ch : CHAR);
    VAR  i: LONGINT; y: LONGINT; a: ARRAY 10 OF CHAR;
  BEGIN i := 0;
    REPEAT
      y := ORD(ch) MOD 10H;
      IF y < 10 THEN
        a[i] := CHR(y + 30H)
      ELSE
        a[i] := CHR(y + 37H)
      END;
      ch := CHR(ORD(ch) DIV 10H);
      INC(i)
    UNTIL i = 2;
    a[i] := 0X;
    REPEAT
      DEC(i);
      DebugCh(a[i]);
    UNTIL i = 0;
  END DebugChHex;

  PROCEDURE DumpMemBlock(adr      : ADDRESS;
                         len      : LONGINT; (* Number of bytes to output. *)
                         elemSize : LONGINT; (* { 1, 4 } element size *)
                         indent   : LONGINT;
                         nl       : SET);
    CONST
      BPL = 16; (* Bytes per line; fits in 80 column terminal. *)

    VAR
      i, k, src : LONGINT;
      ch : CHAR;
      btp : LONGINT;            (* Bytes to print. *)

      PROCEDURE Indent;
        VAR i : INTEGER;
      BEGIN
        i := 0;
        WHILE i < indent DO
          DebugCh(' ');
          INC(i);
        END;
      END Indent;

      PROCEDURE NLn;
      BEGIN DebugLn; Indent;
      END NLn;

      PROCEDURE BytesToPrint(len : LONGINT) : LONGINT;
      BEGIN
        IF len < BPL THEN RETURN len;
        ELSE RETURN BPL;
        END;
      END BytesToPrint;

      PROCEDURE HexPart(adr      : ADDRESS;
                        elemSize : LONGINT;
                        btp      : LONGINT);
        VAR i, liB : LONGINT;
      BEGIN (* Print hex part. *)
        i := 0;
        WHILE i < btp DO
          IF elemSize = 1 THEN
            SYSTEM.GET(adr, ch);
            DebugChHex(ch);
          ELSE (* elemSize = 4 *)
            SYSTEM.GET(adr, liB);
            DebugHex(liB);
          END;
          DebugCh(' ');
          INC(i, elemSize);
          INC(adr, elemSize);
        END;

        (* Pad to char part. *)
        IF btp < BPL THEN
          IF elemSize = 4 THEN
            (* The 4-byte output produces 9 characters.
             *
             * This is not evenly divisible into the default BPL of
             * 16, so 4-byte output is a special case.
             *
             * However, it's not that important because the only use
             * of 4-byte output is to print the 4-byte tag of a heap
             * block, so padding is always going to be the same.
             *)
            DebugStr('                                      ');
          ELSE (* elemSize = 1 *)
            WHILE i < BPL DO
              DebugStr('   ');  (* '00 ' *)
              INC(i);
            END;
          END;
        END;
      END HexPart;

      PROCEDURE CharPart(adr : ADDRESS;
                         btp : LONGINT);
        VAR i : LONGINT;
      BEGIN (* Print char part. *)
        i := 0;
        WHILE i < btp DO
          SYSTEM.GET(adr, ch);
          IF (ch < ' ') OR (ch > 7FX) THEN
            ch := '.';
          END;
          DebugCh(ch);
          INC(i);
          INC(adr);
        END;
        NLn;
      END CharPart;

  BEGIN (* pre: elemSize IN {1, 4} *)
    IF 0 IN nl THEN NLn;
    ELSE Indent;
    END;
    IF len # 0 THEN
      k := 0;
      WHILE len > 0 DO
        src := adr + k;
        btp := BytesToPrint(len);
        DebugHex(src);
        DebugStr(': ');
        HexPart(src, elemSize, btp);
        DebugStr('  ');  (* Space before character part. *)
        CharPart(src, btp);
        INC(k, btp);
        DEC(len, btp);
      END;
      DebugLn;
    END;
  END DumpMemBlock;


  PROCEDURE DumpHeap*;
    CONST
      MB = 1024 * 1024;

    VAR
      q, bs, arrdat, tdadr, nameadr, len : LONGINT;
      tag : SET;
      ch : CHAR;
      mod : Module;
  BEGIN
    DebugLn;
    DebugStr('beg heap dump');
    DebugLn;
    q := heap.region.beg;
    DebugStr('Heap : [');
    DebugHex(heap.region.beg);
    DebugStr(', ');
    DebugHex(heap.region.end);
    DebugStr(']  (Size: ');
    DebugInt(heap.region.size DIV MB);
    DebugStr(' MiB)');
    DebugLn;

    DebugStr('Stack: [');
    DebugHex(stack.beg);         (* Stack grows down. *)
    DebugStr(', ');
    DebugHex(stack.end);
    DebugStr(')  (Size: ');
    DebugInt((stack.end - stack.beg) DIV MB);
    DebugStr('  Mib)  [Stack grows down.]');
    DebugLn;
    DebugLn;
    REPEAT
      SYSTEM.GET(q, tag);
      DebugHex(q);
      DebugStr(': tag=');
      DebugHex(SYSTEM.VAL(LONGINT, tag));
      DebugStr(' { ');
      IF BlkMark IN tag THEN
        DebugStr('BlkMark ');
      END;
      IF BlkSyst IN tag THEN
        DebugStr('BlkSyst ');
      END;
      IF BlkFree IN tag THEN
        DebugStr('BlkFree ');
      END;
      IF BlkAray IN tag THEN
        DebugStr('BlkAray ');
      END;
      bs := GetBlockSize(q);
      DebugStr('} size=');
      DebugHex(bs);
      tdadr := SYSTEM.VAL(LONGINT, tag * (-BlkFlags));
      IF BlkAray IN tag THEN
        DebugStr(' data=');
        DebugHex(tdadr);
      ELSIF BlkFree IN tag THEN
      ELSIF BlkSyst IN tag THEN
      ELSE (* record block *)
        DebugStr(' td='); DebugHex(tdadr);
        len := 0;
        SYSTEM.MEMR(tdadr, rtdModule, mod); (* pointer to record name; see LMSO docs *)
        DebugStr(' name=');
        IF mod # NIL THEN
          DebugStr(mod.name^);
          DebugStr('.');
        END;
        SYSTEM.MEMR(tdadr, rtdName, nameadr); (* pointer to record name; see LMSO docs *)
        len := 0; SYSTEM.GET(nameadr, ch);
        WHILE ch # 0X DO
          DebugCh(ch);
          INC(nameadr);
          INC(len);
          SYSTEM.GET(nameadr, ch);
        END;
      END;
      IF ~(BlkFree IN tag) THEN
        DumpMemBlock(q,          4, 4, 2, {0}); (* block tag *)
        DumpMemBlock(q + 4, bs - 4, 1, 2, {1}); (* block body *)
      ELSE
        DebugLn;
      END;
      INC(q, bs);
    UNTIL q = heap.region.end;
    DebugStr('end heap dump');
    DebugLn;
    DebugLn;
  END DumpHeap;
  (* --- end Kernel Debugging --- *)

  PROCEDURE min(x, y : LONGINT) : INTEGER;
  BEGIN
    IF x < y THEN
      RETURN SHORT(x);
    ELSE
      RETURN SHORT(y);
    END;
  END min;

  PROCEDURE Align(VAR v : LONGINT; b : LONGINT);
  BEGIN
    INC(v, (-v) MOD b);
  END Align;

  PROCEDURE ZeroMem(adr : ADDRESS; size : LONGINT);
    VAR
      vmsvc : VMServiceFillMemoryDesc;
  BEGIN
    vmsvc.val  := 0;
    vmsvc.adr  := adr;
    vmsvc.size := size;
    VMService(VMSVCFillMemory, vmsvc);
  END ZeroMem;

  (* This compiler helper function is used to initialize memory to the
   * value of NIL.  This is used by the compiler to initialize global
   * and local variable space.  This will initialize all data to the
   * same value.
   *
   * If NilVal is changed to some value that is larger than a
   * single byte, then VMSVCFillMemory cannot be used; it fills with a
   * single byte value.
   *)
  PROCEDURE InitMemory*;
    VAR
      adr, nbytes : LONGINT;
      vmsvc : VMServiceFillMemoryDesc;
    CONST
      NilVal = 0;               (* Must match SKLMD.NilVal. *)
  BEGIN
    SYSTEM.GETREG(1, adr);
    SYSTEM.GETREG(2, nbytes);
    vmsvc.val  := NilVal;
    vmsvc.adr  := adr;
    vmsvc.size := nbytes;
    VMService(VMSVCFillMemory, vmsvc);
  END InitMemory;

  PROCEDURE InstallMainLoop*(loop : LoopProc);
  BEGIN
    MainLoop := loop;
  END InstallMainLoop;

  PROCEDURE InstallLoop*(p : PROCEDURE);
  END InstallLoop;

  PROCEDURE InstallSysTrap*(P : SysTrapProc);
  BEGIN
    SysTrapHandler := P;
  END InstallSysTrap;

  PROCEDURE InstallHwdTrap*(P : HwdTrapProc);
  BEGIN
    HwdTrapHandler := P;
  END InstallHwdTrap;

  (* q <=> (q # NIL) & (q points to type tag of the desired block);
   * returns size of allocated block in bytes.
   *)
  PROCEDURE GetBlockSize(q : ADDRESS) : LONGINT;
    VAR BlockSize, DescFlags : LONGINT; tag, flags: SET;
  BEGIN
    SYSTEM.GET(q, tag);
    flags := tag * BlkFlags;
    tag := tag * (-BlkFlags);
    IF BlkSyst IN flags THEN
      BlockSize := SYSTEM.VAL(LONGINT, tag);
    ELSIF BlkAray IN flags THEN
      SYSTEM.MEMR(q, SIZE(ADDRESS), BlockSize);
    ELSIF BlkFree IN flags THEN
      BlockSize := SYSTEM.VAL(LONGINT, tag);
    ELSE (* descriptor block *)
      SYSTEM.MEMR(SYSTEM.VAL(ADDRESS, tag), hmDescFlagsOffs, DescFlags);
      DescFlags := DescFlags MOD 100H;
      IF DescFlags = DescFlagsRecord THEN
        SYSTEM.MEMR(SYSTEM.VAL(ADDRESS, tag), rtdBlockSize, BlockSize);
      ELSE (* pointer to some array type *)
        SYSTEM.MEMR(q, daBlockSize, BlockSize);
      END;
    END;
    Align(BlockSize, hmBlockSize);
    ASSERT(BlockSize > 0);
    RETURN BlockSize;
  END GetBlockSize;


  PROCEDURE Available*() : LONGINT;
    VAR i, avail, blockSize : LONGINT; ptr : ADDRESS;
  BEGIN
    avail := 0; i := hmHeapChains;
    WHILE i >= 0 DO
      ptr := heap.blocks[i];
      DEC(i);
      WHILE ptr # 0 DO
        blockSize := GetBlockSize(ptr);
        INC(avail, blockSize);
        SYSTEM.MEMR(ptr, bfLinkOffs, ptr);
      END;
    END;
    RETURN avail;
  END Available;


  PROCEDURE LargestAvailable*() : LONGINT;
    VAR i, blockSize : LONGINT; ptr : ADDRESS;
  BEGIN
    i := hmHeapChains;
    WHILE (i >= 0) & (heap.blocks[i] = 0) DO
      DEC(i);
    END;
    IF i < 0 THEN
      RETURN 0;
    ELSE
      ptr := heap.blocks[i];
      i := 0;
      WHILE ptr # 0 DO
        blockSize := GetBlockSize(ptr);
        IF blockSize > i THEN
          i := blockSize;
        END;
        SYSTEM.MEMR(ptr, bfLinkOffs, ptr);
      END;
    END;
    RETURN i;
  END LargestAvailable;


  (* Insert a free block at adr (adr points to tag) into the list for size *)
  PROCEDURE Insert(adr : ADDRESS; size : LONGINT);
    VAR i : INTEGER; ptr : ADDRESS;
  BEGIN
    i := min((size DIV hmBlockSize) - 1, hmHeapChains);
    ptr := adr;
    SYSTEM.PUT(ptr, SYSTEM.VAL(SET, size) + {BlkFree}); (* free block tag <=> free block size *)
    SYSTEM.MEMW(ptr, bfLinkOffs, heap.blocks[i]);
    heap.blocks[i] := ptr;
  END Insert;


  PROCEDURE Finalize(q : ADDRESS); (* q <=> memory block address; not pointer value *)
    VAR tdptr : ADDRESS; tdflags : LONGINT; bc : SHORTINT; finalize : PROCEDURE (ptr : ADDRESS);
  BEGIN
    SYSTEM.GET(q, tdptr);
    IF SYSTEM.VAL(SET, tdptr) * {BlkFree, BlkSyst} = {} THEN
      IF BlkAray IN SYSTEM.VAL(SET, tdptr) THEN
        (* mem[(tdptr - {BlkMark, BlkAray}) + hmPtrTagOffs] -> real td pointer *)
        SYSTEM.MEMR(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdptr) * (-BlkFlags)),
                    hmPtrTagOffs, tdptr);
        tdptr := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tdptr) * (-BlkFlags));
      END;
      SYSTEM.MEMR(tdptr, hmDescFlagsOffs, tdflags);
      bc := BlockClass[tdflags MOD 100H];
      IF bc = bcRec THEN
        SYSTEM.MEMR(tdptr, rtdFinalize, finalize);
      ELSIF bc = bcAgg THEN
        SYSTEM.MEMR(tdptr, reTD, tdptr); (* TD of element type *)
        SYSTEM.MEMR(tdptr, rtdFinalize, finalize);
      ELSE (* simple element or pointer to array of pointer (nop) *)
        finalize := NIL;
      END;
      IF finalize # NIL THEN
        finalize(q + SIZE(ADDRESS));
      END;
    END;
  END Finalize;


  PROCEDURE Sweep;
    VAR
      q, p, data : ADDRESS;
      blockSize : LONGINT;
      b : BOOLEAN;
  BEGIN
    heap.allocated := 0;
    q := 0;
    WHILE q < LEN(heap.blocks) DO (* all free chains <-> empty *)
      heap.blocks[q] := 0;
      INC(q);
    END;
    q := heap.region.beg;

    REPEAT
      WHILE (q # heap.region.end) &
            (SYSTEM.BIT(q, BlkMark) OR
             SYSTEM.BIT(q, BlkSyst)) DO (* Process reachable & system blocks. *)
        SYSTEM.BITR(q, BlkMark);
        blockSize := GetBlockSize(q);

        (* The array block will have an internal type tag which needs to be reset *)
        IF SYSTEM.BIT(q, BlkAray) THEN
          SYSTEM.GET(q, data); (* address of array + BlkFlags *)
          SYSTEM.BITR(SYSTEM.VAL(ADDRESS,
                                 SYSTEM.VAL(SET, data) * (-BlkFlags)) + hmPtrTagOffs,
                      BlkMark); (* internal tag *)
        END;
        INC(q, blockSize);
        INC(heap.allocated, blockSize);
      END;

      IF q # heap.region.end THEN
        p := q; (* Process free blocks. *)
        REPEAT
          Finalize(q);
          blockSize := GetBlockSize(q);
          INC(q, blockSize); (* coalesce contiguous unmarked blocks *)
        UNTIL (q = heap.region.end) OR
              SYSTEM.BIT(q, BlkMark) OR SYSTEM.BIT(q, BlkSyst);
        Insert(p, q - p);
      END;
    UNTIL q = heap.region.end;
  END Sweep;


  (* arr <= address of array[0] *)
  (* tag <= address of dynarr tag *)
  (* alpha <= alpha offset for descriptor size calculation *)
  (* returns: Block(arr) (beginning of block, not ADR(Tag(arr)) *)
  PROCEDURE GetArrayBlock(arr, tag : ADDRESS; alpha : LONGINT) : ADDRESS;
    VAR x : LONGINT;
  BEGIN
    SYSTEM.MEMR(tag, datdNofDim, x);
    x := alpha + 4 * x;
    RETURN arr - ((-x) MOD 16 + x);
  END GetArrayBlock;


  PROCEDURE Mark(qq : ADDRESS);
    TYPE
      ArrayInfo = RECORD
        tdaddr   : ADDRESS; (* type descriptor address (for array blocks) (temp) *)
        arrpos   : LONGINT; (* current position in array block;
                             * inv: arrpos >= nofElem => traversed *)
        nofElem  : LONGINT; (* number of (flattened) elements in array block *)
        elemSize : LONGINT; (* size of array block elements *)
        nabk     : ADDRESS; (* BlkArray(n) => Block(n) & ~BlkArray(n) => undef *)
        abk      : ADDRESS; (* BlkArray(q) => Block(q) & ~BlkArray(q) => undef *)
      END;

      BlockInfo = RECORD
        addr  : ADDRESS;        (* Address of memory block *)
        tag   : ADDRESS;        (* Block type tag. *)
        class : SHORTINT;       (* BlockClass(). *)
        flags : LONGINT;        (* Descriptor flags. *)
      END;

      QBlockInfo = RECORD (BlockInfo)
        offset : ADDRESS;       (* Offset, in heap block, of pointer. *)
        tdidx  : ADDRESS;       (* Address in TD pointer table. *)
      END;

    VAR
      (* inv: qq is a pointer to a reachable & marked memory block. *)
      traversed : BOOLEAN;  (* TRUE => all pointers in memory block have been traversed *)
      tos       : ADDRESS;  (* top of pointer traversal stack *)
      q         : QBlockInfo;
      array     : ArrayInfo;
      nb        : BlockInfo;
      tmp       : BlockInfo;(* (BlkRecord(q) => tmp = q(BlockInfo)) &
                             * (BlkArray(q) => tmp.addr = q.data + q.arrpos) *)

  BEGIN
    q.addr := qq;
    SYSTEM.MEMR(q.addr, hmPtrTagOffs, q.tag);
    q.tag := SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, q.tag) * (-BlkFlags));
    SYSTEM.MEMR(q.tag, hmDescFlagsOffs, q.flags);
    q.class  := BlockClass[q.flags MOD 100H]; (* BlockKind(q) *)
    tmp.addr := q.addr;

    IF q.class = bcRec THEN
      q.tdidx := q.tag;
    ELSIF q.class IN {bcAgg, bcPtr} THEN
      array.abk := GetArrayBlock(q.addr, q.tag, q.class); (* inv: abk <=> Block(q) *)
      IF q.class = bcAgg THEN
        array.arrpos := 0;
        SYSTEM.MEMR(q.tag, reTD, q.tdidx);
      ELSIF q.class = bcPtr THEN
        array.arrpos := -1;
        q.tdidx := 0;
        q.offset := 0;
        DEC(tmp.addr, SIZE(ADDRESS)); (* t := q.data - 1 *)
      END;
    ELSE
      RETURN; (* Simple elem; nothing further to collect. *)
    END;
    INC(q.tdidx, rtdPtrTabOffs - SIZE(ADDRESS)); (* q.tdidx is now one word before
                                                  * pointer offset table. *)
    tos := 0;
    LOOP
      INC(q.tdidx, SIZE(ADDRESS));

      (* inv: q.class <=> BlockKind(q) *)
      IF q.class = bcRec THEN
        SYSTEM.GET(q.tdidx, q.offset); (* Get next pointer offset. *)
        traversed := q.offset < 0;
      ELSIF q.class IN {bcAgg, bcPtr} THEN
        IF q.class = bcAgg THEN (* array of [array of] record *)
          SYSTEM.GET(q.tdidx, q.offset);
          IF q.offset < 0 THEN
            INC(array.arrpos);
            SYSTEM.MEMR(q.tag, reTD, array.tdaddr);
            SYSTEM.MEMR(array.abk, daNofElem, array.nofElem); (* q.nofElem *)
            q.tdidx := array.tdaddr + rtdPtrTabOffs; (* tdidx := 0; *)
            IF array.arrpos < array.nofElem THEN
              SYSTEM.GET(q.tdidx, q.offset);
              SYSTEM.MEMR(array.tdaddr, rtdRecSize, array.elemSize);
              INC(tmp.addr, array.elemSize);
            END;
            traversed := (q.offset < 0) OR (array.arrpos >= array.nofElem);
          END;
        ELSE (* q.class = bcPtr *) (* array of [array of] pointer *)
          INC(array.arrpos);
          INC(tmp.addr, SIZE(ADDRESS));
          SYSTEM.MEMR(array.abk, daNofElem, array.nofElem);
          traversed := array.arrpos >= array.nofElem;
        END;
      END;

      IF traversed THEN
        IF q.class = bcRec THEN
          (* 'offset' is the sentinel value that will reproduce the
           * original 'tag' value.
           *)
          q.tag := q.tdidx + q.offset; (* Original tag value for record. *)
          SYSTEM.MEMW(q.addr, hmPtrTagOffs, SYSTEM.VAL(SET, q.tag) + {BlkMark});
        END;

        IF tos = 0 THEN
          EXIT;
        ELSE (* Pop(q, tmp.addr, tmp.class); *)
          (* inv: tmp.class <-> TOS bc *)
          IF tmp.class = bcRec THEN
            tmp.addr := tos;
            SYSTEM.MEMR(tos, rtdCnt, q.tdidx);
            q.tdidx := SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, q.tdidx) * (-{BlkMark}));
            SYSTEM.GET(q.tdidx, q.offset);
            (* inv: offset := mem[tos.tdidx];
             *
             * tdidx <=> pointer into TD
             *)
          ELSE (* tmp.class IN {bcAgg, bcPtr} *)
            SYSTEM.MEMR(tos, hmPtrTagOffs, q.tag);
            q.tag := SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, q.tag) * (-BlkFlags));
            array.abk := GetArrayBlock(tos, q.tag, tmp.class);
            SYSTEM.MEMR(array.abk, daArrPos, array.arrpos); (* arrpos := tos.arrpos; *)
            IF tmp.class = bcAgg THEN
              SYSTEM.MEMR(tos, reTD, array.tdaddr);
              SYSTEM.MEMR(array.tdaddr, rtdRecSize, array.elemSize);
              SYSTEM.MEMR(array.abk, daCnt, q.offset); (* offset := mem[tos.tdidx]; *)
            ELSIF tmp.class = bcPtr THEN
              array.elemSize := SIZE(ADDRESS);
              q.offset := 0;
            END;
            (* inv: elemSize <=> array element size *)
            tmp.addr := tos + array.arrpos * array.elemSize; (* tos.data + arrpos * ElemSize(tos); *)
          END;

          (* This is the actual POP operation *)
          SYSTEM.GET(tmp.addr + q.offset, nb.addr); (* n := mem[t + offset]; *)
          SYSTEM.PUT(tmp.addr + q.offset, q.addr); (* mem[t + offset] := q; *)
          q.addr  := tos;
          q.class := tmp.class;
          tos     := nb.addr;

          IF nb.addr # 0 THEN (* inv: n is the previous pointer being traversed *)
            tmp.class := bcRec; (* tbc := BlockKind(tos) *)
            SYSTEM.MEMR(nb.addr, hmPtrTagOffs, q.tag);
            q.tag := SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, q.tag) * (-BlkFlags));
            SYSTEM.MEMR(q.tag, hmDescFlagsOffs, q.flags);

            IF (DescFlagsValidBit IN SYSTEM.VAL(SET, q.flags)) &
               ~(DescFlagsSignBit IN SYSTEM.VAL(SET, q.flags)) THEN
              q.flags := q.flags MOD 100H;
              IF q.flags IN {0..DescNofArrayType-1} THEN
                tmp.class := BlockClass[q.flags];
              END;
            END;
          END;
        END;
      ELSE (* The structure has not been traversed.
            * Process next element.
            *)
        (* inv: q.class <=> BlockKind(q) *)
        (* inv: tmp <=> ADR(memory being collected.
         *
         *  This can be any type of block, so 'q.addr' cannot be directly
         *  used due to arrays and other aggregates
         *)
        SYSTEM.GET(tmp.addr + q.offset, nb.addr); (* inv: nb.addr <=> next pointer *)
        IF nb.addr # 0 THEN
          SYSTEM.MEMR(nb.addr, hmPtrTagOffs, nb.tag);

          (* Skip blocks that are already marked. *)
          IF ~(BlkMark IN SYSTEM.VAL(SET, nb.tag)) THEN
            nb.tag := SYSTEM.VAL(ADDRESS,
                                 SYSTEM.VAL(SET, nb.tag) * (-BlkFlags)); (* ntag <=> TD(n) *)
            SYSTEM.MEMR(nb.tag, hmDescFlagsOffs, nb.flags);
            nb.class := BlockClass[nb.flags MOD 100H]; (* BlockKind(n) *)

            (* inv: n <=> address referenced by current pointer *)
            (* inv: nb.class <=> BlockClass(n) *)

            SYSTEM.BITS(nb.addr + hmPtrTagOffs, BlkMark); (* internal tag *)
            IF nb.class IN {bcAgg, bcPtr, bcSmp} THEN (* external tag *)
              array.nabk := GetArrayBlock(nb.addr, nb.tag, nb.class);
              SYSTEM.BITS(array.nabk + hmPtrTagOffs, BlkMark);
            END;

            IF (nb.class IN NeedsGC) &
               ~(BlkSyst IN (SYSTEM.VAL(SET, nb.tag) * BlkFlags)) THEN (* Push(q, t) *)
              IF q.class = bcRec THEN
                SYSTEM.MEMW(q.addr, rtdCnt,
                            SYSTEM.VAL(SET, q.tdidx) + {BlkMark}); (* q.tdidx := tdidx *)
              ELSE (* q.class IN {bcAgg, bcPtr} *)
                SYSTEM.MEMW(array.abk, daArrPos, array.arrpos); (* q.arrpos := arrpos *)
                IF q.class = bcAgg THEN
                  SYSTEM.MEMW(array.abk, daCnt, q.tdidx); (* q.tdidx := tdidx *)
                END;
              END;

              (* Swizzle pointers: { memory, tos, q, n }  *)
              SYSTEM.PUT(tmp.addr + q.offset, tos); (* mem[t + offset] := tos *)
              tmp.class := q.class;
              tos       := q.addr;
              q.addr    := nb.addr;
              q.class   := nb.class;
              q.tag     := nb.tag;

              (* inv: tag <=> Tag(q) *)

              IF q.class = bcRec THEN
                tmp.addr := q.addr;
                q.tdidx  := q.tag;
              ELSE
                array.abk := array.nabk;
                IF q.class = bcAgg THEN
                  tmp.addr := q.addr; (* t := q.data *)
                  array.arrpos := 0;
                  SYSTEM.MEMR(q.tag, reTD, q.tdidx); (* inv: tdidx <=> record TD pointer *)
                ELSE (* q.class = bcPtr *)
                  tmp.addr := q.addr; (* q.data; *)
                  array.arrpos := -1;
                  q.offset := -SIZE(ADDRESS); (* offset := -1 *)
                  q.tdidx := 0;
                END;
              END;
              INC(q.tdidx, rtdPtrTabOffs - SIZE(ADDRESS)); (* tdidx := -1 *)
            END;
          END;
        END;
      END;
    END;
  END Mark;


  PROCEDURE MarkBlock(ptr : ADDRESS);
    VAR
      tag    : SET;
      dflags : LONGINT;
      bc     : SHORTINT;
      abk    : ADDRESS;
  BEGIN
    IF ptr # 0 THEN
      SYSTEM.BITS(ptr + hmPtrTagOffs, BlkMark);
      SYSTEM.MEMR(ptr, hmPtrTagOffs, tag);
      IF ~(BlkSyst IN tag) THEN
        (* If this is a BlkAray then the external tag must be set
         * indicating the block is marked. *)
        tag := tag * (-BlkFlags);
        SYSTEM.MEMR(SYSTEM.VAL(LONGINT, tag), hmDescFlagsOffs, dflags);
        bc := BlockClass[dflags MOD 100H]; (* BlockKind(q) *)
        IF bc IN {bcAgg, bcPtr, bcSmp} THEN (* external tag *)
          abk := GetArrayBlock(ptr, SYSTEM.VAL(LONGINT, tag), bc);
          SYSTEM.BITS(abk + hmPtrTagOffs, BlkMark);
        END;
        Mark(ptr);
      END;
    END;
  END MarkBlock;


  PROCEDURE GC*;
  CONST
    SFP  = 29;                   (* R29: stack frame pointer. *)

  VAR
    mod : Module;
    i, len, ptrAdr : ADDRESS;
    sfp, stackPtr, ip : ADDRESS;
    stackTag, descTag : ADDRESS;
    blockSize : LONGINT;
    ptrVal : ADDRESS;
    tag : SET;
    b : BOOLEAN;

  BEGIN
    GCActive := TRUE;
    mod := SYSTEM.VAL(Module, mlist);
    WHILE mod # NIL DO
      IF mod.pointers = NIL THEN
        len := 0;
      ELSE
        len := LEN(mod.pointers^);
      END;
      i := 0;
      WHILE i < len DO
        ptrAdr := mod.pointers[i];
        SYSTEM.GET(ptrAdr, ptrVal);
        MarkBlock(ptrVal);
        INC(i);
      END;
      mod := mod.next;
    END;

    (* Scan the stack, from the current stack frame
     * pointer to the beginning.
     *
     * The current stack frame pointer will be at a lower address than the
     * top of the stack, because the stack grows down.
     *
     * The 'stack.end' value is contiguously right before 'heap.region.beg'
     *
     * This is disabled because it is possible to recognize a non-pointer
     * value as a pointer in very rare conditions.  The following are used
     * to identify a potential pointer:
     *
     *   o Pointer value is properly aligned.
     *   o The whole pointer value is in the heap.
     *   o The tag at the referenced memory is properly aligned.
     *   o The whole tag value is in the heap.
     *   o The tag's flags have only bits {0..3, 30} set.
     *     Bit 30   : DescFlagsValidBit
     *     Bits 0..3: type of memory block (range: [0, 9])
     *     All other bits must be 0.
     *   o The referenced block is not BlkSyst.
     *   o The referenced block is not already marked.
     *
     * A better approach would be to identify open stack frames by
     * return address, and then use the functionality in SKLTrap.Mod
     * to extract the offsets of local pointer variables from the
     * stack frame.  This would remove all the guesswork and be a
     * perfect solution.
     *
     *)
    SYSTEM.GETREG(SFP, sfp);
    WHILE sfp < stack.end DO
      IF gcFindFunction # NIL THEN
        SYSTEM.MEMR(sfp, SIZE(Kernel.ADDRESS), ip);
        IF (ip MOD SIZE(ADDRESS) = 0) &
           (ip >= heap.region.beg) &
           (ip + SIZE(LONGINT) < heap.region.end) THEN
          (* All instructions are aligned to a word boundary,
           * and must be in the heap. *)
          IF gcFindFunction(ip, sfp) THEN
            WHILE gcNextPointer(stackPtr) DO
              (* 'stackPtr' is a memory block pointed to by an open
               * stack frame.  It must be marked. *)
              MarkBlock(stackPtr);
            END;
          END;
        END;
      END;
      SYSTEM.GET(sfp, sfp);
    END;

    Sweep;
    GCActive := FALSE;
  END GC;

  PROCEDURE GetAFS*(VAR afs : AllocationFailStrategy);
  BEGIN afs := AFS
  END GetAFS;

  PROCEDURE SetAFS*(afs : AllocationFailStrategy);
  BEGIN AFS := afs;
  END SetAFS;


  PROCEDURE SetGCStackInfo*(findFunction  : GCFindFunctionFn;
                            nextPointer   : GCNextPointerFn);
  BEGIN
    gcFindFunction := findFunction;
    gcNextPointer  := nextPointer;
  END SetGCStackInfo;


  (* This routine from ETH report 156
     size MUST include the tag size when calling this!  should be a
     multiple of blocksize

     If unable to allocate memory, a trap is raised
  *)
  PROCEDURE Allocate(VAR blkadr : ADDRESS; size : LONGINT);
    VAR
      i : INTEGER;
      sizetmp : LONGINT;
      r, last, ptr, linktmp : ADDRESS;
  BEGIN
    i := min(size DIV hmBlockSize, hmHeapChains);
    WHILE (i < hmHeapChains) & (heap.blocks[i] = 0) DO
      INC(i);
    END; (* smallest non-empty list *)
    last := SYSTEM.ADR(heap.blocks[i]);
    SYSTEM.GET(last, ptr); (* address & pointer to free block *)
    IF ptr # 0 THEN
      sizetmp := GetBlockSize(ptr);
      WHILE (ptr # 0) & (sizetmp < size) DO
        last := ptr + bfLinkOffs;
        SYSTEM.GET(last, ptr); (* next block on list; first fit, if i = hmHeapChains *)
        sizetmp := GetBlockSize(ptr);
      END;
    END;

    IF ptr # 0 THEN
      SYSTEM.GET(ptr + bfLinkOffs, linktmp);
      SYSTEM.PUT(last, linktmp); (* remove block from list *)
      IF sizetmp > size THEN (* block must be split *)
        r := ptr + size;
        SYSTEM.PUT(r, SYSTEM.VAL(SET, sizetmp - size) + {BlkFree});  (* New free block;
                                                                      * residual of split. *)
        i := min(((sizetmp - size) DIV hmBlockSize) - 1, hmHeapChains);
        SYSTEM.PUT(r + bfLinkOffs, heap.blocks[i]);
        heap.blocks[i] := r; (* Put residual back on the proper list. *)
      END;
      blkadr := ptr;
      INC(heap.allocated, size);
      ZeroMem(blkadr, size);
    ELSE
      blkadr := 0;
    END;
  END Allocate;

  PROCEDURE AlignHeapSize*(nofBytes : LONGINT) : LONGINT;
  BEGIN
    INC(nofBytes, hmTagSize);
    Align(nofBytes, hmBlockSize);
    RETURN nofBytes;
  END AlignHeapSize;

  (* R1 = address of variable being allocated
     R2 = size in bytes
  *)
  PROCEDURE NewBlock*;
    VAR blkadr, adr : ADDRESS; size : LONGINT;
  BEGIN
    SYSTEM.GETREG(1, adr); (* R1 is address of variable to get pointer. *)
    SYSTEM.GETREG(2, size); (* R2 is block size *)
    size := AlignHeapSize(size);
    Allocate(blkadr, size);
    IF blkadr # 0 THEN
      SYSTEM.PUT(blkadr, SYSTEM.VAL(SET, size) + {BlkSyst});
      SYSTEM.PUT(adr, blkadr + hmTagSize);
    ELSE
      SYSTEM.PUT(adr, 0);
    END;
  END NewBlock;

  (* R1 contains the address of the record pointer being allocated,
     R2 contains a pointer to the record type descriptor
  *)
  PROCEDURE NewRecord*;
    VAR blkadr, adr, tdptr : ADDRESS; size : LONGINT;
  BEGIN
    SYSTEM.GETREG(1, adr);    (* R1: address of pointer *)
    SYSTEM.GETREG(2, tdptr);  (* R2: address of type descriptor *)
    SYSTEM.MEMR(tdptr, rtdRecSize, size);
    size := AlignHeapSize(size);
    Allocate(blkadr, size);
    IF blkadr # 0 THEN
      SYSTEM.MEMW(tdptr, rtdBlockSize, size); (* fixup the block size entry *)
      SYSTEM.PUT(blkadr, tdptr);
      SYSTEM.PUT(adr, blkadr + hmTagSize);
    ELSE
      SYSTEM.PUT(adr, 0);
    END;
  END NewRecord;

  (* calculate the size of the requested array, in bytes *)
  PROCEDURE CalcArraySize(BlockKind, elSize, nofDim : LONGINT;
                          bounds : ADDRESS;
                          VAR nofElem, size, alpha : LONGINT);
    VAR
      i, dim, x : LONGINT;
  BEGIN
    i := 0;
    size := elSize;
    nofElem := 1;
    WHILE i < nofDim DO
      SYSTEM.GET(bounds + i * 4, dim);
      size := size * dim;
      nofElem := nofElem * dim;
      INC(i);
    END;

    (* add in size of heap block preamble *)
    IF BlockKind IN SimpleElemSet THEN
      x := seAlpha;
    ELSIF BlockKind IN PointerElemSet THEN
      x := peAlpha;
    ELSE (* BlockKind IN RecordElemSet *)
      x := reAlpha;
    END;

    x := (x + 4 * nofDim);
    alpha := (-x) MOD 16 + x; (* alpha <=> Offset to array data from
                               *           beginning of block. *)
    IF size # 0 THEN
      INC(size, alpha); (* See documentation on heap-based array layout. *)
      size := AlignHeapSize(size);
    END;
  END CalcArraySize;

  (*
    blkadr <= address at which memory was allocated
    userptr <= address of user pointer being allocated
    bk <=> block kind
    td <=> address of type descriptor
    size <=> size, in bytes, of allocated block
    nofElem <=> number of (flattened) elements in array
    nofDim <=> number of dimensions in array
    srcBounds <=> address of array dimension boundaries
    alpha <=> offset to array data from beginning of heap block
  *)
  PROCEDURE SetDynArrInfo(userptr, blkadr, bk, td : ADDRESS;
                          size, nofElem, nofDim : LONGINT;
                          srcBounds : ADDRESS;
                          alpha : LONGINT);
    VAR
      len : LONGINT; arrayData : ADDRESS;
  BEGIN
    (* inv: alpha <=> offset to array data from the `paragraph-aligned'
     *                block address; add in the block tag size to be
     *                the true array-data-address
     *)
    arrayData := blkadr + alpha + SIZE(LONGINT);
    SYSTEM.PUT(blkadr, SYSTEM.VAL(SET, arrayData) + {BlkAray});
    SYSTEM.MEMW(blkadr, daBlockSize, size);
    SYSTEM.PUT(userptr, arrayData);
    INC(blkadr, SIZE(ADDRESS));

    (* inv: arrayData points to the start of the user-accessible heap block *)
    (* inv: blkadr points to beginning of heap block *)
    SYSTEM.MEMW(arrayData, daTD, SYSTEM.VAL(SET, td) + {BlkAray});
    SYSTEM.MEMW(blkadr, daNofElem, nofElem);

    (* The array lengths are pushed onto the stack in reverse order
     * (0th index last). This makes the 0th dimension length always be
     * at the same stack offset.  Additionally, the 0th dimension in the
     * descriptor is at the same negative  offset, with progressively higher
     * indices being at more negative offsets.
     *
     * Adjust 'arrayData' so that the backwards indices on the stack can be
     * easily copied to their descriptor locations.
     *)
    DEC(arrayData, SIZE(ADDRESS) * nofDim);
    WHILE nofDim > 0 DO
      SYSTEM.GET(srcBounds, len);
      INC(arrayData, SIZE(ADDRESS));
      SYSTEM.MEMW(arrayData, daLen0, len - 1); (* Store max index, not LEN. *)
      INC(srcBounds, SIZE(ADDRESS));
      DEC(nofDim);
    END;
  END SetDynArrInfo;

  (*
    R1 contains the address of the item which is being newed
    R2 contains a pointer to the array descriptor
  *)
  PROCEDURE - LEAVE 01H, 00H, 0A0H, 2BH;   (* LEAVE R29, 0 *)
  PROCEDURE - JRALR1  0, 0, 1, 18H;        (* JRAL R1, R0 *)
  PROCEDURE NewDynArray*;
    CONST
      SFP           = 29; (* R29: stack frame pointer. *)
      Dim0StackOffs = 8;  (* Offset of 0th dimension's bound on
                           * stack from the SFP.
                           * Dimensions pushed in reverse order. *)
    VAR
      i, descFlags, elSize, nofDim, nofElem, size : LONGINT;
      BlockKind, alpha : LONGINT;
      adr, td, blkadr, retadr : ADDRESS;
      sfp : LONGINT;

  BEGIN
    SYSTEM.GETREG(1, adr);    (* R1: Address of pointer. *)
    SYSTEM.GETREG(2, td);     (* R2: address of type descriptor. *)

    SYSTEM.MEMR(td, datdFlags, descFlags);
    BlockKind := descFlags MOD 100H;

    SYSTEM.MEMR(td, datdElemSize, elSize); (* element size *)
    SYSTEM.MEMR(td, datdNofDim, nofDim);
    SYSTEM.GETREG(SFP, sfp);

    CalcArraySize(BlockKind, elSize, nofDim, sfp + Dim0StackOffs, nofElem, size, alpha);
    (* inv: size <=> total size of (requested + overhead) array in bytes *)
    (* inv: nofElem <=> total number of elements in the (flattened) array *)

    IF size # 0 THEN
      Allocate(blkadr, size);
      IF blkadr # 0 THEN
        SYSTEM.GETREG(SFP, sfp); (* inv: sp holds the frame pointer *)
        SetDynArrInfo(adr, blkadr, BlockKind, td, size, nofElem,
                      nofDim, sfp + Dim0StackOffs, alpha);
      ELSE
        SYSTEM.PUT(adr, 0); (* out-of-memory. *)
      END;
    ELSE
      SYSTEM.PUT(adr, 0); (* attempt to allocate 0-length array *)
    END;

    SYSTEM.GETREG(SFP, sfp);
    SYSTEM.MEMR(sfp, SIZE(LONGINT), retadr); (* Read return address from stack *)

    SYSTEM.PUTREG(1, retadr);
    SYSTEM.PUTREG(2, (nofDim + 1) * SIZE(LONGINT)); (* Drop dimensions from stack *)
    (* No statement below here must modify { R1, R2 }. *)
    LEAVE;                      (* LEAVE R29, 0 (Restore previous stack frame.) *)
    JRALR1;
  END NewDynArray;

  (*
    R1 = address of pointer
    R2 = type descriptor pointer
  *)
  PROCEDURE NewStaticArray*;
    VAR
      td, adr, blkadr : ADDRESS;
      descFlags, elSize, nofDim, nofElem, size, BlockKind, alpha : LONGINT;
  BEGIN
    SYSTEM.GETREG(1, adr);      (* R1: address of pointer. *)
    SYSTEM.GETREG(2, td);       (* R2: address of type descriptor. *)
    SYSTEM.MEMR(td, datdFlags, descFlags);
    BlockKind := descFlags MOD 100H;
    SYSTEM.MEMR(td, saElemSize, elSize);
    SYSTEM.MEMR(td, saNofDim, nofDim);
    CalcArraySize(BlockKind, elSize, nofDim, td + saDim0,
                  nofElem, size, alpha);
    IF size # 0 THEN
      Allocate(blkadr, size);
      IF blkadr # 0 THEN
        SetDynArrInfo(adr, blkadr, BlockKind, td, size,
                      nofElem, nofDim, td + saDim0, alpha);
      ELSE
        SYSTEM.PUT(adr, 0); (* out-of-memory. *)
      END;
    ELSE
      SYSTEM.PUT(adr, 0); (* Attempt to allocate 0-length array. *)
    END;
  END NewStaticArray;


  (* System Trap -- ASSERT failure or HALT
    R1 = system trap value (see compiler document for valid values; also see OPM
  *)
  PROCEDURE SysTrap*;
    CONST
      SFP = 29;                 (* R29 is stack frame pointer. *)
    VAR
      trap : LONGINT;
      sfp, ip : ADDRESS;
      svc : VMServiceSysTrapDesc;
  BEGIN
    SYSTEM.GETREG(1, trap);     (* R1 is the trap number *)
    SYSTEM.GETREG(SFP, sfp);
    SYSTEM.MEMR(sfp, SIZE(ADDRESS), ip);
    IF SysTrapHandler # NIL THEN
      SysTrapHandler(trap, ip, sfp);
    ELSE
      svc.ip   := ip;
      svc.sfp  := sfp;
      svc.trap := trap;
      VMService(VMSVCEarlySysTrap, svc);
    END;
  END SysTrap;

  (* This function is assigned to CR1.
   * It is invoked if a hardware trap occurs.
   *)
  PROCEDURE - GetCR0 00H, 00H, 20H, 0CH; (* lcr CR0, R1 *)
  PROCEDURE - GetCR2 00H, 00H, 22H, 0CH; (* lcr CR2, R1 *)
  PROCEDURE HwdTrap;
    CONST
      SFP = 29;                 (* R29 is stack frame pointer. *)
    VAR
      cr0    : LONGINT; (* Address (IP) of exception *)
      cr2    : LONGINT; (* Exception status *)
      sfp    : ADDRESS; (* Stack Frame Pointer at exception time *)
      svc    : VMServiceHwdTrapDesc;
  BEGIN
    GetCR0;
    SYSTEM.GETREG(1, cr0);
    GetCR2;
    SYSTEM.GETREG(1, cr2);
    SYSTEM.GETREG(SFP, sfp);
    IF HwdTrapHandler # NIL THEN
      HwdTrapHandler(cr0, sfp, cr2);
    ELSE
      svc.ip   := cr0;
      svc.sfp  := sfp;
      svc.trap := 0;
      svc.cr2  := cr2;
      VMService(VMSVCEarlyHwdTrap, svc);
    END;
  END HwdTrap;


  PROCEDURE - SetCR5 01H, 00H, 0A1H, 0CH; (* scr R1, CR5 *)
  (* SetSysTrap:
   *
   *   Set %cr5 to the address of 'SysTrap'.  This allows the
   *   'sys trap' family of instructions (like 'trapnil') to
   *   directly invoke the trap handler.
   *
   *   The 'sys trap' family of instructions reduces code
   *   generated by the compiler, which makes the SKL
   *   interpreter faster.
   *)
  PROCEDURE SetSysTrap;
    VAR
      trap : PROCEDURE;
  BEGIN
    trap := SysTrap;
    SYSTEM.PUTREG(1, SYSTEM.VAL(LONGINT, trap));
    SetCR5;
  END SetSysTrap;

  (* SetHwdTrap:
   *
   *   Set %cr1 to the address of HwdTrap().
   *)
  PROCEDURE - LoadCR1 01H, 00H, 021H, 0CH; (* scr R1, CR1 *)
  PROCEDURE SetHwdTrap;
    VAR
      trap : PROCEDURE;
  BEGIN
    trap := HwdTrap;
    SYSTEM.PUTREG(1, SYSTEM.VAL(LONGINT, trap));
    LoadCR1;
  END SetHwdTrap;


  PROCEDURE Copy*; (* standard procedure COPY helper (move 0X-terminated strings) *)
    VAR
      source : ADDRESS; (* R1 *)
      dest   : ADDRESS; (* R2 *)
      len    : LONGINT; (* R3: LEN(dest) (number of bytes) *)
      ch     : CHAR;
  BEGIN
    SYSTEM.GETREG(1, source);
    SYSTEM.GETREG(2, dest);
    SYSTEM.GETREG(3, len);
    REPEAT
      SYSTEM.GET(source, ch);
      SYSTEM.PUT(dest, ch);
      DEC(len);
      INC(source);
      INC(dest);
    UNTIL (len <= 0) OR (ch = 0X);
  END Copy;

  PROCEDURE CopyMemory(source : ADDRESS; dest : ADDRESS; len : LONGINT);
    VAR
      byte : SYSTEM.BYTE;
  BEGIN
    REPEAT
      SYSTEM.GET(source, byte);
      SYSTEM.PUT(dest, byte);
      DEC(len);
      INC(source);
      INC(dest);
    UNTIL len <= 0;
  END CopyMemory;


  PROCEDURE MoveBlock*; (* Move binary data *)
    VAR
      source : ADDRESS; (* R1 *)
      dest   : ADDRESS; (* R2 *)
      len    : LONGINT; (* R3: LEN(dest) (number of bytes) *)
  BEGIN
    SYSTEM.GETREG(1, source);
    SYSTEM.GETREG(2, dest);
    SYSTEM.GETREG(3, len);
    CopyMemory(source, dest, len);
  END MoveBlock;


  PROCEDURE StdSysMove*; (* Move binary data *)
    VAR
      source : ADDRESS; (* R1 *)
      dest   : ADDRESS; (* R2 *)
      len    : LONGINT; (* R3: number of bytes *)
  BEGIN
    SYSTEM.GETREG(1, source);
    SYSTEM.GETREG(2, dest);
    SYSTEM.GETREG(3, len);
    CopyMemory(source, dest, len);
  END StdSysMove;

  (* Sets system clock from Oberon style date and time
     date := (year*16+month)*32+day
     time := (hour*64+minute)*64+seconds
  *)
  PROCEDURE SetClock*(time, date : LONGINT);
  BEGIN
    IF SetClockProc # NIL THEN
      SetClockProc(time, date);
    END;
  END SetClock;

  (* Returns Oberon style date and time
     date := (year*16+month)*32+day
     time := (hour*64+minute)*64+seconds
  *)
  PROCEDURE GetClock*(VAR time, date : LONGINT);
  BEGIN
    (* FIXME: GetClockProc should be NIL during bootstrapping, but
     * FIXME: SEGV occurs when initializing DebugIO during bootstrap. *)
    IF FALSE & (GetClockProc # NIL) THEN
      GetClockProc(time, date);
    ELSE
      time := 0;
      date := 0;
    END;
  END GetClock;

  (* Returns length of command line, including 0X *)
  PROCEDURE GetCommandLineLength*() : INTEGER;
    VAR
      adr : ADDRESS;
      l   : INTEGER;
      ch  : CHAR;
  BEGIN
    adr := CmdLine;
    l   := 0;
    IF adr # 0 THEN
      LOOP
        SYSTEM.GET(adr, ch);
        INC(l);
        INC(adr);
        IF ch = 0X THEN (* inv: Block must be 0X terminated. *)
          EXIT;
        END;
      END;
    END;
    RETURN l;
  END GetCommandLineLength;

  PROCEDURE GetCommandLine*(VAR l : ARRAY OF CHAR);
    VAR
      i, len : LONGINT;
      ch : CHAR;
      adr : ADDRESS;
  BEGIN
    adr := CmdLine;
    IF adr # 0 THEN
      i := 0;
      len := LEN(l);
      REPEAT
        SYSTEM.GET(adr, ch);
        l[i] := ch;
        INC(i);
        INC(adr);
      UNTIL (i >= len) OR (ch = 0X);
      l[LEN(l) - 1] := 0X;
    ELSE
      l[0] := 0X;
    END;
  END GetCommandLine;

  PROCEDURE - ModuleInit  0H, 0H, 0FCH, 1BH; (* JAL R28, R31 *)

  (* BootstrapModuleInit
   *
   *   This function is used by the bootstrap loader to execute
   *   module initialization code, and then return back to the
   *   loader to continue processing the next module.
   *
   *   This is only invoked by the bootstrap loader.
   *   R28 holds the address of the module initialization function.
   *)
  PROCEDURE BootstrapModuleInit*;
    VAR
      svc : VMServiceDesc;
  BEGIN
    ModuleInit;
    VMService(VMSVCBootstrap, svc);
  END BootstrapModuleInit;


  (* TerminateOberon
   *
   *   This function is used by the bootstrap loader to terminate
   *   the Oberon system when the first non-bootstrap module
   *   inititlization exits.
   *
   *   Note that this is incompatible with traditional the Oberon
   *   input loop.  The traditional input loop allowed interaction
   *   through the keyboard and mouse.  However, without a graphical
   *   display, this Oberon system cannot have user interaction.
   *)
  PROCEDURE TerminateOberon*(rc : LONGINT);
    VAR
      svc : VMServiceTerminateDesc;
  BEGIN
    svc.rc := rc;
    VMService(VMSVCTerminate, svc);
  END TerminateOberon;


  (* Cannot perform a full GC yet because allocated memory will not appear.
   * mlist # pointer type => too much collection
   *)
  PROCEDURE InitGC;
  BEGIN Sweep;
  END InitGC;

  PROCEDURE InstallTerminator*(proc : TerminatorProc);
  BEGIN
    TerminationProc := proc;
  END InstallTerminator;

  PROCEDURE Terminate*(code : LONGINT);
  BEGIN
    IF TerminationProc # NIL THEN
      TerminationProc(code);
    ELSE
      HALT(1200);
    END;
  END Terminate;

  PROCEDURE Init;
    VAR
      BootstrapAdr : LONGINT;
      i            : LONGINT;
      stackBottom  : ADDRESS;
      stackSize    : LONGINT;
      heapOrg      : ADDRESS;
      heapSize     : LONGINT;
  BEGIN
    SYSTEM.GETREG(1, heapOrg);      (* R1 is the heap start. *)
    SYSTEM.GETREG(2, heapSize);     (* R2 is the full heap allocation
                                     * size in bytes (stack + heap). *)
    SYSTEM.GETREG(3, stackBottom);  (* R3 is address of bottom of stack. *)
    SYSTEM.GETREG(4, stackSize);    (* R4 is the stack size in bytes. *)

    SYSTEM.GETREG(5, mlist);        (* R5 is Module list. *)
    SYSTEM.GETREG(6, CmdLine);      (* R6 is command line. *)


    (* The stack occupies [stack.beg, stack.end), but the stack origin
     * is at stack.end. Adding data to the stack grows it towards
     * stack.beg because it grows down.
     *)
    stack.beg        := stackBottom;
    stack.size       := stackSize;
    stack.end        := stackBottom + stackSize;
    heap.region.beg  := heapOrg;
    heap.region.size := heapSize;
    heap.region.end  := heapOrg + heapSize;

    GCActive := FALSE;
    SetClockProc := NIL;
    GetClockProc := NIL;
    TerminationProc := NIL;
    AFS := afsTRAP;             (* What happens if memory allocation fails? *)

    BlockClass[DescFlagsRecord]       := bcRec;
    BlockClass[DescFlagsDynArray0]    := bcSmp;
    BlockClass[DescFlagsDynArray1]    := bcPtr;
    BlockClass[DescFlagsDynArray2]    := bcAgg;
    BlockClass[DescFlagsDynArray3]    := bcSmp;
    BlockClass[DescFlagsDynArray4]    := bcPtr;
    BlockClass[DescFlagsDynArray5]    := bcAgg;
    BlockClass[DescFlagsStaticArray0] := bcSmp;
    BlockClass[DescFlagsStaticArray1] := bcPtr;
    BlockClass[DescFlagsStaticArray2] := bcAgg;
    InitGC;
    SysTrapHandler := NIL;
    HwdTrapHandler := NIL;
  END Init;

BEGIN
  gcFindFunction := NIL;
  gcNextPointer  := NIL;
  Init;
  SetSysTrap;
  SetHwdTrap;
END Kernel.
