MODULE Modules;
IMPORT
  SYSTEM,
  Kernel,
  HostOS,
  FileDir,
  Files,
  FileUtils,
  CommandLine,
  Environment,
  Console;

  CONST
    dsFingerprint = 0;
    dsTypeDescriptors = 1;
    dsInitialize = 2;
    dsDiskLoad = 3;
    dsCacheLoad = 4;
    dsLoading = 5;
    DiagSet = {};

  CONST
    OFtag      = 0F8320000H;  (* object file tag (must match SKLMD) *)
    OFversion  = 11161967H;  (* must match SKLMD *)

  CONST (* res values *)
    done* = 0;
    fileNotFound* = 1;
    notAnObj* = 2;
    fpMismatch* = 3;
    corruptObj* = 4;
    cmdNotFound* = 5;
    modNotFound* = 6;
    notEnoughSpace* = 7;
    refCntNotZero* = 8;
    objNotFound* = 9;
    cyclicImport* = 10;
    objVersionMismatch* = 11;
    helperModNotFound* = 12;

    special = 151;

  TYPE (* VMServiceDesc.service = Kernel.VMSVCTerminate *)
    SVCTerminate = RECORD (Kernel.VMServiceDesc)
      rc : LONGINT;             (* in: VM return code. *)
    END;

  CONST (* Type kinds *)
    Trec = 1X; Tdarray = 2X; Tarray = 3X; (* must match LMCGL *)

  CONST (* Used symbol kind *)
    Uconst = 1X; Utype = 2X; Uvar = 3X;
    Uxproc = 4X; Uiproc = 4X; Ucproc = 5X;
    Upbstruc = 6X; Upvstruc = 7X;
    Urectd = 8X; Udarraytd = 9X; Uarraytd = 0AX;
    Unofuse = 10; (* number of 'uses' symbol kinds *)

  TYPE
    Name* = Kernel.Name;
    ModuleName* = Kernel.ModuleName;
    Command* = PROCEDURE;

  CONST (* Exported symbol kind *)
    Econst = 1X; Etype = 2X; Evar = 3X;
    Exproc = 4X; Eiproc = 4X;
    Ecproc = 5X; Estruc = 6X;
    Erectd = 8X; Edarraytd = 9X; Earraytd = 0AX;

  CONST (* dynamic array element types (must match CGL.WDynArrayTD) *)
    daSimple = 1X;
    daPointer = 2X;
    daRecord = 3X;
    daArray = 4X;

  CONST (* dynamic array of array element types (must match CGL.WDynArrayTD) *)
    daaSimple = 0X;
    daaPointer = 1X;
    daaRecord = 2X;

  CONST (* array element types (must match CGL.WArrayTD) *)
    aSimple = 1X;
    aPointer = 2X;
    aRecord = 3X;

  CONST (* segments (must match LMCGL) *)
    segUndef = -1;
    segCode = 0;
    segConst = 1;
    segCase = 2;  (* case jump tables *)
    segData = 3;
    segExport = 4; (* exported entry points *)
    segCommand = 5; (* exported commands *)
    segTypeDesc = 6;
    segTDesc = 7; (* segment of absolute addresses of type descriptors *)
    segNofSegments = 8;

  CONST (* Fixup modes (must match LMCGL) *)
    fixAbs = 0;  (* absolute address of fixup-to item *)
    fixRel = 1;  (* relative address of fixup-to item;
                  * rel = next instruction addres - fixup-to address *)
    fixBlk = 2; (* record type descriptor `record block size' *)

  CONST (* fixup kinds (must match LMCGL) *)
    fkSymbol = 1X;
    fkLabel = 2X;

  TYPE (* Exported symbol info *)
    Export* = Kernel.Export;

  TYPE
    Cmd* = Kernel.Cmd;
    Module* = Kernel.Module;
    ModuleDesc* = Kernel.ModuleDesc;
    ADDRESS = LONGINT;

  VAR
    (* The value assigned (by the loader) to 'modules' is also assigned
     * to Kernel.mlist.  Because of this, the first entry in the list
     * of loaded modules must be preserved so that Kernel.mlist does
     * not change
     *)
    modules*: Module; (* modules currently loaded by the system; new modules always added at end *)
    importing-: Name; (* res # done => name of module which caused import failure *)
    imported- : Name; (* res # done => name of module which was imported by 'importing' *)
    object-: Name;  (* res = fpMismatch *)
    res-: INTEGER;

  VAR
    ExportUseMap : ARRAY Unofuse OF CHAR;
    indent : INTEGER; (* debug only *)
    EmptyString : Name;
    OberonName, LoopName : Name;

  VAR
    SearchPath : Environment.Elements;

  PROCEDURE ^ ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
  PROCEDURE ^ Load(VAR (* R/O *) name: ARRAY OF CHAR; VAR mod : Module);


  PROCEDURE exit(rc : LONGINT);
    VAR
      svc : SVCTerminate;
  BEGIN
    svc.rc := rc;
    Kernel.VMService(Kernel.VMSVCTerminate, svc);
  END exit;


  (* pre: ASCIIZ(s) *)
  (* post: (result # NIL) & ASCIIZ(result) & (Ai:0..LEN(s): result[i] = s[i]) *)
  PROCEDURE NewName(s : ARRAY OF CHAR) : Name;
    VAR i : INTEGER; ch : CHAR; str : Name;
  BEGIN
    i := 0;
    REPEAT
      ch := s[i];
      INC(i);
    UNTIL (i >= LEN(s)) OR (ch = 0X);
    ASSERT(ch = 0X);

    (* inv: i <-> number of characters in s including 0X *)
    NEW(str, i);
    COPY(s, str^);
    RETURN str;
  END NewName;

  PROCEDURE Indent;
    VAR i : INTEGER;
  BEGIN
    i := 0;
    WHILE i < indent DO
      Console.Str('  ');
      INC(i);
    END;
  END Indent;

  PROCEDURE CodeSeg(mod : Module);
  BEGIN
    IF mod # NIL THEN
      Console.Str(' code=[');
      Console.Hex(SYSTEM.ADR(mod.code[0]));
      Console.Str('..');
      Console.Hex(SYSTEM.ADR(mod.code[LEN(mod.code^) - 1]));
      Console.Str(')');
    ELSE Console.Str(' not loaded');
    END;
  END CodeSeg;

  PROCEDURE AddModule(mod : Module);
    VAR
      m : Module;
  BEGIN
    m := modules;               (* inv: modules # NIL *)
    WHILE m.next # NIL DO
      m := m.next;
    END;
    mod.next := NIL;
    m.next := mod;
  END AddModule;

  PROCEDURE Fixup(target, fixkind, dest : LONGINT);
    VAR value : LONGINT;
  BEGIN
    IF res # done THEN
      RETURN;                 (* prevent fixups to non-valid memory *)
    END;
    SYSTEM.GET(target, value);
    INC(dest, value); (* fixups are additive with the value generated by the compiler *)
    CASE fixkind OF
    | fixAbs: SYSTEM.PUT(target, dest);
    | fixRel: SYSTEM.PUT(target, dest - (target + 4));
    | fixBlk: SYSTEM.PUT(target, dest);
    END;
  END Fixup;

  PROCEDURE GetSegAddress(mod : Module; segment, offs : LONGINT) : LONGINT;
    VAR addr : LONGINT;
  BEGIN
    CASE segment OF
    | segCode: addr := SYSTEM.ADR(mod.code[offs]);
    | segConst: addr := SYSTEM.ADR(mod.data[mod.sb + offs]);
    | segCase: addr := SYSTEM.ADR(mod.jumps[offs]);
    | segData:
      (* If there are no constants in the module being loaded, then
       * mod.sb will have been set to the end of mod.data^.
       * Accessing it with 'mod.sb' will yield an out-of-bounds index.
       * Because mod.data^ is an array of SYSTEM.BYTE, indexing can be
       * performed on the result of SYSTEM.ADR() to avoid the index check
       * generated by the compiler.
       *
       * The same technique is not needed for 'segConst', because 'mod.sb'
       * will never be out-of-bounds in that case.
       *
       * No other section is split this way, so all other indices should
       * be in-bounds.
       *)
      addr := SYSTEM.ADR(mod.data^) + mod.sb + offs;
    | segExport: addr := SYSTEM.ADR(mod.exports[offs].adr);
    | segCommand: addr := SYSTEM.ADR(mod.commands[offs].adr);
    | segTypeDesc: addr := SYSTEM.ADR(mod.tddata[offs]);
    | segTDesc: addr := SYSTEM.ADR(mod.tdescs[offs]);
    END;
    RETURN addr;
  END GetSegAddress;

  PROCEDURE GetExportAddress(mod : Module; name : Name) : LONGINT;
    VAR  i, nofexp : LONGINT;
  BEGIN
    IF mod.exports # NIL THEN
      i := 0;
      nofexp := LEN(mod.exports^);
      WHILE (i < nofexp) & (mod.exports[i].name^ # name^) DO
        INC(i);
      END;
      IF i < nofexp THEN
        RETURN mod.exports[i].adr;
      ELSE
        res := corruptObj;
        RETURN 0;
      END;
    ELSE
      res := corruptObj;
      RETURN 0;
    END;
  END GetExportAddress;

  PROCEDURE LoadModule(VAR R : Files.Rider; VAR mod : Module);
    TYPE
      String = POINTER TO StringDesc;
      StringDesc = RECORD
        next : String;
        i : LONGINT;
        n : Name;
      END;

      Uses = POINTER TO UsesDesc;
      UsesDesc = RECORD
        next : Uses;
        num : INTEGER; (* uses number *)
        mod : INTEGER; (* module number *)
        name : Name; (* symbol name *)
      END;

    VAR
      b : BOOLEAN;
      i : LONGINT;
      refsize, nofexp, nofprv, nofdesc, nofcom : LONGINT;
      nofptr, nofhlp, noffix, pc, dsize, constx : LONGINT;
      typedescx, casex, exportx, nofimports : LONGINT;
      modname, impname : Name;
      strings : String;
      uses : Uses;
      init : Command;

    (* pre: (name # NIL ) & ASCIIZ(name) *)
    (* post: TRUE -> cyclic import (name is on list of modules which have been loaded already) *)
    (* post: FALSE -> not a cyclic import *)
    PROCEDURE CyclicImport(name : Name) : BOOLEAN;
      VAR
        mod : Module;
    BEGIN
      mod := modules;
      WHILE (mod # NIL) & (mod.name^ # name^) DO
        mod := mod.next;
      END;
      IF mod # NIL THEN
        res := cyclicImport;
      END;
      RETURN res = cyclicImport;
    END CyclicImport;

    PROCEDURE SaveUses(num, mod : LONGINT; name : Name);
      VAR u : Uses;
    BEGIN  NEW(u); u.next := uses; uses := u; u.num := SHORT(num);
      u.mod := SHORT(mod); u.name := name;
    END SaveUses;

    (* pre: num <-> uses-list index number *)
    PROCEDURE GetImportedSymbolAddr(num : LONGINT) : LONGINT;
      VAR u : Uses;
    BEGIN
      u := uses;
      WHILE (u # NIL) & (u.num # num) DO
        u := u.next;
      END;
      IF u # NIL THEN
        RETURN GetExportAddress(mod.imports[u.mod], u.name);
      ELSE
        Console.Str('cannot find symbol #');
        Console.Int(num, 3);
        Console.Ln;
        res := special;
        RETURN 0;
      END;
    END GetImportedSymbolAddr;

    PROCEDURE Block(tag : CHAR);
      VAR
        ch : CHAR;
    BEGIN
      Files.Read(R, ch);
      IF ch # tag THEN
        res := corruptObj;
        IF mod # NIL THEN
          importing := mod.name;
        END;
      END;
    END Block;

    PROCEDURE ReadString(VAR n : Name);
      VAR i, len : LONGINT; s : String;
    BEGIN Files.ReadNum(R, i); ASSERT(i > 0);
      IF i > 0 THEN
        Files.ReadNum(R, len); NEW(s); NEW(s.n, len + 1);
        s.i := i; Files.ReadBytes(R, s.n^, len); s.next := strings; strings := s;
      ELSE s := strings; WHILE s.i # -i DO s := s.next; END;
      END;
      n := s.n;
    END ReadString;

    PROCEDURE NewModuleDesc(VAR m : Module) : BOOLEAN;
      VAR ok : BOOLEAN; mod : Module;
    BEGIN
      NEW(mod);
      m := mod;
      ok := mod # NIL;
      IF ok THEN
        mod.finalize := NIL;
        mod.name := modname;
        mod.refcnt := 0;
        mod.sb := dsize;
        IF nofdesc > 0 THEN
          NEW(mod.tdescs, nofdesc);
          ok := mod.tdescs # NIL;
        END;
        IF ok & (nofexp > 0) THEN
          NEW(mod.exports, nofexp);
          ok := mod.exports # NIL;
        END;

        IF ok & (nofprv > 0) THEN
          NEW(mod.privates, nofprv); ok := mod.privates # NIL;
        END;

        IF ok & (nofcom > 0) THEN
          NEW(mod.commands, nofcom);
          ok := mod.commands # NIL;
        END;

        IF ok & (nofptr > 0) THEN
          NEW(mod.pointers, nofptr);
          ok := mod.pointers # NIL;
        END;

        IF ok & (nofimports > 0) THEN
          NEW(mod.imports, nofimports);
          ok := mod.imports # NIL;
        END;

        IF ok & (casex > 0)  THEN
          NEW(mod.jumps, casex);
          ok := mod.jumps # NIL;
        END;

        IF ok & (constx + dsize > 0) THEN
          NEW(mod.data, constx + dsize);
          ok := mod.data # NIL;
        END;

        IF ok & (typedescx > 0) THEN
          NEW(mod.tddata, typedescx);
          ok := mod.tddata # NIL;
        END;

        IF ok & (pc > 0) THEN
          NEW(mod.code, pc);
          ok := mod.code # NIL;
        END;

        IF ok & (refsize > 0) THEN
          NEW(mod.refs, refsize);
          ok := mod.refs # NIL;
        END;
      END;

      IF ~ok THEN
        importing := EmptyString;
        res := notEnoughSpace;
      END;
      RETURN ok;
    END NewModuleDesc;

    PROCEDURE CheckFingerprint(mod : Module; name : Name; kind : CHAR; fprint : LONGINT);
      VAR
        i, nofexp, loadedfp : LONGINT;
        checkKind : CHAR;
    BEGIN
      checkKind := ExportUseMap[ORD(kind) - 1];
      loadedfp  := -1;
      i := 0;
      IF mod.exports = NIL THEN
        nofexp := 0
      ELSE
        nofexp := LEN(mod.exports^);
      END;

      WHILE (i < nofexp) & ((mod.exports[i].kind # ORD(checkKind)) OR
                            (name^ # mod.exports[i].name^)) DO
        INC(i);
      END;

      IF i < nofexp THEN
        IF kind = Upvstruc THEN
          loadedfp := mod.exports[i].pvfprint;
        ELSE
          loadedfp := mod.exports[i].fprint;
        END;
        IF fprint # loadedfp THEN
          object := name;
          imported := mod.name;
          res := fpMismatch;
        END;
      ELSE
        object := name;
        imported := mod.name;
        res := fpMismatch;
      END;

      IF dsFingerprint IN DiagSet THEN
        Console.Str('CheckFingerprint: ');
        Console.Str(mod.name^); Console.Str(' ');
        Console.Str(name^);
        Console.Str(' fp=');
        Console.Hex(fprint);
        Console.Str(' lfp=');
        Console.Hex(loadedfp);
        Console.Str(' i=');
        Console.Int(i, 3);
        Console.Str(' nofexp=');
        Console.Int(nofexp, 3);
        Console.Str(' kind=');
        Console.Int(ORD(kind), 3);
        Console.Str(' res=');
        Console.Int(res, 3);
        Console.Ln;
      END;
    END CheckFingerprint;

    PROCEDURE ImportBlock(VAR imports : ARRAY OF Module);
      VAR i, nofimports : LONGINT;
    BEGIN i := 0; nofimports := LEN(imports);
      WHILE (i < nofimports) & (res = done) DO
        ReadString(impname); Load(impname^, imports[i]); INC(i);
      END;
    END ImportBlock;

    PROCEDURE ExportBlock(VAR exp : ARRAY OF Export);
      VAR i, kind, nofexp : LONGINT; name : Name;
    BEGIN
      i := 0;
      nofexp := LEN(exp);
      WHILE i < nofexp DO
        Files.ReadNum(R, kind);
        exp[i].pvfprint := 0;
        exp[i].kind := SHORT(kind);
        CASE CHR(kind) OF
        | Econst:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);

        | Etype:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);

        | Evar:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);

        | Exproc, Ecproc:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);

        | Estruc:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);
          Files.ReadNum(R, exp[i].pvfprint);

        | Erectd, Edarraytd, Earraytd:
          ReadString(exp[i].name);
          Files.ReadNum(R, exp[i].fprint);
        END;
        INC(i);
      END;
    END ExportBlock;

    PROCEDURE TypeDescriptorInfoBlock(nofdesc : LONGINT); (* this block is read but ignored *)
      VAR
        kind, i, k, size, ancesmno, ancesfprint, elemform, elemmno : LONGINT;
        nofmeth, nofinhmeth, nofnewmeth, methno : LONGINT;
        methadr, nofptr, ptroffs, fprint, nofdim : LONGINT;
        name : Name;
        elem : CHAR;
    BEGIN i := 0;
      WHILE i < nofdesc DO
        Files.ReadNum(R, kind);
        CASE CHR(kind) OF
        | Trec:
          ReadString(name);
          Files.ReadNum(R, size);
          Files.ReadNum(R, ancesmno);
          IF ancesmno # -1 THEN
            ReadString(name);
            Files.ReadNum(R, ancesfprint);
          END;
          Files.ReadNum(R, nofmeth);
          Files.ReadNum(R, nofinhmeth);
          Files.ReadNum(R, nofnewmeth);
          Files.ReadNum(R, nofptr);
          k := 0;
          WHILE k < nofnewmeth DO
            Files.ReadNum(R, methno);
            Files.ReadNum(R, methadr);
            INC(k);
          END;
          k := 0;
          WHILE k < nofptr DO
            Files.ReadNum(R, ptroffs);
            INC(k);
          END;

        | Tdarray:
          ReadString(name); Files.ReadNum(R, fprint); Files.Read(R, elem);
          Files.ReadNum(R, nofdim);
          CASE elem OF
          | daSimple: Files.ReadNum(R, elemform);
          | daPointer: Files.ReadNum(R, elemform);
          | daRecord: Files.ReadNum(R, elemmno); ReadString(name); Files.ReadNum(R, fprint);
          | daArray: Files.Read(R, elem);
            CASE elem OF
            | daaSimple: Files.ReadNum(R, elemform);
            | daaPointer: Files.ReadNum(R, elemform);
            | daaRecord: Files.ReadNum(R, elemmno); ReadString(name); Files.ReadNum(R, fprint);
            END;
            Files.ReadNum(R, nofdim);
            k := 0; WHILE k < nofdim DO Files.ReadNum(R, ptroffs); INC(k); END; (* LEN(array, k) *)
          END;
        | Tarray:
          ReadString(name); Files.ReadNum(R, fprint); Files.Read(R, elem);
          ASSERT(ORD(elem) IN {ORD(aSimple), ORD(aPointer), ORD(aRecord)}, 1091);
          CASE elem OF
          | aSimple, aPointer: Files.ReadNum(R, elemform);
          | aRecord: Files.ReadNum(R, elemmno); ReadString(name); Files.ReadNum(R, fprint);
          ELSE ASSERT(FALSE, 1089);
          END;
          Files.ReadNum(R, nofdim);
          k := 0; WHILE k < nofdim DO Files.ReadNum(R, ptroffs); INC(k); END; (* LEN(array, k) *)
        ELSE ASSERT(FALSE, 1090);
        END;
        INC(i);
      END;
    END TypeDescriptorInfoBlock;

    PROCEDURE CommandBlock(VAR commands : ARRAY OF Cmd);
      VAR i, nofcmd : LONGINT;
    BEGIN
      i := 0;
      nofcmd := LEN(commands);
      WHILE i < nofcmd DO
        ReadString(commands[i].name);
        commands[i].adr := 0;
        INC(i);
      END;
    END CommandBlock;

    PROCEDURE PointerBlock(sb : LONGINT; VAR pointers : ARRAY OF LONGINT);
      VAR i, offset, nofptr : LONGINT;
    BEGIN i := 0; nofptr := LEN(pointers);
      WHILE i < nofptr DO Files.ReadNum(R, offset); pointers[i] := sb + offset; INC(i); END;
    END PointerBlock;

    PROCEDURE ConstantBlock(VAR data : ARRAY OF SYSTEM.BYTE; constx : LONGINT);
      VAR i, k : LONGINT;
    BEGIN k := mod.sb; i := 0; WHILE i < constx DO Files.Read(R, data[k]); INC(i); INC(k); END;
    END ConstantBlock;

    PROCEDURE TypeDescriptorDataBlock(VAR data : ARRAY OF SYSTEM.BYTE);
    BEGIN Files.ReadBytes(R, data, LEN(data));
    END TypeDescriptorDataBlock;

    PROCEDURE FixupTDescs(VAR tdescs : ARRAY OF LONGINT);
      VAR t : Kernel.TypeDesc; i : LONGINT; tdflags : SET;
    BEGIN i := 0;
      WHILE i < LEN(tdescs) DO
        t := SYSTEM.VAL(Kernel.TypeDesc, tdescs[i]);
        IF dsTypeDescriptors IN DiagSet THEN
          Indent;
          Console.Str('TD ptr: ');
          Console.Str(mod.name^);
          Console.Str(' i=');
          Console.Hex(i);
          Console.Str(' len=');
          Console.Hex(LEN(tdescs));
          Console.Str(' td=');
          Console.Hex(SYSTEM.VAL(LONGINT, t));
          Console.Ln;
        END;
        (* Only set the module field if the type of the descriptor is
         * one which has a module field (i.e. records, not arrays). *)
        SYSTEM.GET(SYSTEM.VAL(LONGINT, t), tdflags);
        IF tdflags * {0..8} = {} THEN
          (* It is a type descriptor for a record (see 'Descriptor
           * Flags' in compiler documentation) *)
          t.module := SYSTEM.VAL(LONGINT, mod);
        END;
        INC(i);
      END;
    END FixupTDescs;

    PROCEDURE CodeBlock(VAR code : ARRAY OF SYSTEM.BYTE);
    BEGIN
      Files.ReadBytes(R, code, LEN(code));
    END CodeBlock;

    PROCEDURE UsesBlock(VAR imports : ARRAY OF Module);
      VAR i, nofimp, fprint, nofuse : LONGINT; kind : CHAR; name : Name;
    BEGIN
      i := 0;
      nofuse := 0;
      nofimp := LEN(imports);
      WHILE i < nofimp DO
        REPEAT
          Files.Read(R, kind);
          CASE kind OF
          | Uconst:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Utype:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Uvar:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Uxproc:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Ucproc:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Upbstruc:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Upvstruc:
            ReadString(name);
            Files.ReadNum(R, fprint);

          | Urectd, Udarraytd, Uarraytd:
            ReadString(name);
            Files.ReadNum(R, fprint);
          ELSE (* 0X *)
          END;
          IF (kind # 0X) & (res = done) THEN
            CheckFingerprint(imports[i], name, kind, fprint);
            IF (kind # Upbstruc) & (kind # Upvstruc) THEN
              SaveUses(nofuse, i, name);
              INC(nofuse);
            END; (* save only major Uses for external fixups *)
          END;
        UNTIL kind = 0X;
        INC(i);
      END;
    END UsesBlock;

    PROCEDURE HelperFixups(nofhlp : LONGINT);
      VAR modName, procName : Name; i, codeAdr, procAdr : LONGINT; helperMod : Module;
    BEGIN
      i := 0;
      WHILE i < nofhlp DO
        ReadString(modName);
        ReadString(procName);
        Load(modName^, helperMod);
        IF res # done THEN
          RETURN;
        END;
        procAdr := SYSTEM.VAL(ADDRESS, ThisCommand(helperMod, procName^));
        Files.ReadNum(R, codeAdr);
        REPEAT
          Fixup(GetSegAddress(mod, segCode, codeAdr), fixAbs, procAdr);
          Files.ReadNum(R, codeAdr);
        UNTIL codeAdr = -1;
        INC(i);
      END;
    END HelperFixups;

    PROCEDURE FixupBlock(noffix : LONGINT);
      VAR
        i, mode, segment, targOffs, destOffs : LONGINT;
        destSeg, modno, targ, dest : LONGINT;
        kind : CHAR;
    BEGIN
      i := 0;
      WHILE i < noffix DO
        Files.ReadNum(R, mode);
        Files.ReadNum(R, segment);
        Files.ReadNum(R, targOffs);
        CASE mode OF
        | fixAbs, fixRel:
          Files.Read(R, kind);
          IF kind = fkSymbol THEN
            Files.ReadNum(R, destSeg);
            Files.ReadNum(R, modno);
            Files.ReadNum(R, destOffs);
            IF modno = 0 THEN (* local symbol *)
              dest := GetSegAddress(mod, destSeg, destOffs);
            ELSE (* imported symbol *)
              dest := GetImportedSymbolAddr(destOffs);
            END;
          ELSE (* fkLabel *)
            Files.ReadNum(R, destSeg);
            Files.ReadNum(R, destOffs);
            dest := GetSegAddress(mod, destSeg, destOffs);
          END;
          targ := GetSegAddress(mod, segment, targOffs);
          Fixup(targ, mode, dest);

        | fixBlk:
          Files.ReadNum(R, dest);
          targ := GetSegAddress(mod, segment, targOffs);
          Fixup(targ, mode, Kernel.AlignHeapSize(dest));
        END;
        INC(i);
      END;
    END FixupBlock;

    PROCEDURE RefBlock(VAR ref : ARRAY OF CHAR);
    BEGIN
      Files.ReadBytes(R, ref, LEN(ref));
    END RefBlock;

  BEGIN
    strings := NIL;
    uses := NIL;
    (* header *) Block(80X);
    Files.ReadLInt(R, refsize); Files.ReadLInt(R, nofexp);
    Files.ReadLInt(R, nofprv); Files.ReadLInt(R, nofdesc);
    Files.ReadLInt(R, nofcom); Files.ReadLInt(R, nofptr);
    Files.ReadLInt(R, nofhlp); Files.ReadLInt(R, noffix);
    Files.ReadLInt(R, pc); Files.ReadLInt(R, dsize);
    Files.ReadLInt(R, constx); Files.ReadLInt(R, typedescx);
    Files.ReadLInt(R, casex); Files.ReadLInt(R, exportx);
    Files.ReadLInt(R, nofimports); ReadString(modname);
    b := NewModuleDesc(mod);
    IF ~b THEN
      RETURN;
    END;

    (* imports *) Block(81X);
    IF res # done THEN RETURN;
    ELSIF mod.imports # NIL THEN
      ImportBlock(mod.imports^);
      IF (res # done) OR CyclicImport(modname) THEN
        RETURN;
      END;
    END;

    (* exports *) Block(82X);
    IF res # done THEN
      RETURN;
    ELSIF mod.exports # NIL THEN
      ExportBlock(mod.exports^);
    END;

    (* privates *) Block(83X);
    IF res # done THEN
      RETURN;
    ELSIF mod.privates # NIL THEN
      ExportBlock(mod.privates^);
    END;

    (* type desc info *) Block(84X);
    IF res # done THEN
      RETURN;
    END;
    TypeDescriptorInfoBlock(nofdesc);

    (* commands *) Block(85X);
    IF res # done THEN
      RETURN;
    ELSIF mod.commands # NIL THEN
      CommandBlock(mod.commands^);
    END;

    (* pointers *) Block(86X);
    IF res # done THEN
      RETURN;
    ELSIF mod.pointers # NIL THEN
      PointerBlock(SYSTEM.ADR(mod.data[0]) + mod.sb, mod.pointers^);
    END;

    (* constants *) Block(87X);
    IF res # done THEN
      RETURN;
    ELSIF mod.data # NIL THEN
      ConstantBlock(mod.data^, constx);
    END;

    (* type desc data *) Block(88X);
    IF res # done THEN
      RETURN;
    ELSIF mod.tddata # NIL THEN
      TypeDescriptorDataBlock(mod.tddata^);
    END;

    (* code *) Block(89X);
    IF res # done THEN
      RETURN;
    ELSIF mod.code # NIL THEN
      CodeBlock(mod.code^);
    END;

    (* uses *) Block(8AX);
    IF res # done THEN
      RETURN;
    ELSIF mod.imports # NIL THEN
      UsesBlock(mod.imports^);
    END;

    (* helper fixups *) Block(8BX);
    IF res # done THEN
      RETURN;
    ELSIF nofhlp > 0 THEN
      HelperFixups(nofhlp);
    END;

    (* fixups *) Block(8CX);
    IF res # done THEN
      RETURN;
    ELSIF noffix > 0 THEN
      FixupBlock(noffix);
    END;

    (* references *) Block(8DX);
    IF res # done THEN
      RETURN;
    ELSIF mod.refs # NIL THEN
      RefBlock(mod.refs^);
    END;

    IF mod.tddata # NIL THEN (* If there is td data, there must be tdescs. *)
      ASSERT(mod.tdescs # NIL);
      FixupTDescs(mod.tdescs^);
      (* Make td desc pointers address their actual type descriptor;
       * used by Types module. *)
    END;

    AddModule(mod);
    IF res = done THEN
      IF dsInitialize IN DiagSet THEN
        Indent;
        Console.Str('---initializing <');
        Console.Str(mod.name^);
        Console.Str('>');
        Console.Ln;
      END;
      init := ThisCommand(mod, mod.name^);
      init;
    END;
    strings := NIL;
    uses := NIL;
  END LoadModule;

  PROCEDURE FindObjFile(VAR (* R/O *) name : ARRAY OF CHAR) : Files.File;
    VAR
      info  : FileDir.PathInfo;
      fname : FileDir.Filename;
      f     : Files.File;
      i     : INTEGER;
      len   : LONGINT;
      path  : FileDir.Filename;
  BEGIN
    FileDir.Split(name, info);
    FileDir.SetFileComponent('.Obj', FileDir.piExtension, info);
    FileDir.Join(info, fname);
    RETURN FileUtils.FindAndOpenFile(SearchPath, fname);
  END FindObjFile;

  PROCEDURE Load(VAR (* R/O *) name: ARRAY OF CHAR; VAR mod : Module);
    VAR
      f : Files.File;
      R : Files.Rider;
      ch : CHAR;
      tag, version : LONGINT;

  BEGIN
    INC(indent);
    mod := modules;
    res := done;
    WHILE (mod # NIL) & (mod.name^ # name) DO
      mod := mod.next;
    END;

    IF mod = NIL THEN
      f := FindObjFile(name);
      IF f # NIL THEN
        IF dsDiskLoad IN DiagSet THEN
          Indent;
          Console.Str('---disk<');
          Console.Str(f.name);
          Console.Str('>');
          Console.Ln;
        END;
        Files.Set(R, f, 0);
        Files.ReadLInt(R, tag);
        IF tag = OFtag THEN
          Files.ReadLInt(R, version);
          IF version = OFversion THEN
            LoadModule(R, mod);
            IF dsDiskLoad IN DiagSet THEN
              Indent;
              Console.Str('---from disk<');
              Console.Str(f.name);
              Console.Str('>');
              Console.Str(' adr=');
              Console.Hex(SYSTEM.VAL(LONGINT, mod));
              CodeSeg(mod);
              Console.Ln;
            END;
          ELSE
            res := objVersionMismatch;
          END;
        ELSE
          res := notAnObj;
        END;
      ELSE
        res := fileNotFound;
      END;
    ELSE
      IF dsCacheLoad IN DiagSet THEN
        Indent;
        Console.Str('---cache<');
        Console.Str(name);
        Console.Str('>');
        Console.Str(' adr=');
        Console.Hex(SYSTEM.VAL(LONGINT, mod));
        CodeSeg(mod);
        Console.Ln;
      END;
    END;
    IF res # done THEN
      IF (importing = NIL) OR (importing = EmptyString) THEN
        importing := NewName(name);
      END;
    ELSE
      importing := NIL;
      imported := NIL;
      object := NIL;
    END;
    DEC(indent);
  END Load;

  PROCEDURE ThisMod*(name: ARRAY OF CHAR): Module;
    VAR
      mod : Module;
      afs : Kernel.AllocationFailStrategy;
  BEGIN
    Kernel.GetAFS(afs);
    Kernel.SetAFS(Kernel.afsNIL);
    IF dsLoading IN DiagSet THEN
      Indent;
      Console.Str('---Modules is loading <');
      Console.Str(name);
      Console.Ch('>');
      Console.Ln;
    END;
    Load(name, mod);
    IF dsLoading IN DiagSet THEN Indent;
      Console.Str('---Modules has loaded <');
      Console.Str(name);
      Console.Str('> success: ');
      Console.Bool(mod # NIL);
      CodeSeg(mod);
      Console.Ln;
    END;
    Kernel.SetAFS(afs);
    RETURN mod;
  END ThisMod;

  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
    VAR i : LONGINT;
  BEGIN
    IF mod.commands = NIL THEN i := 0; ELSE i := LEN(mod.commands^); END;
    WHILE i > 0 DO DEC(i);
      IF mod.commands[i].name^ = name THEN res := done;
        RETURN SYSTEM.VAL(Command, mod.commands[i].adr);
      END;
    END;
    importing := NewName(name); res := cmdNotFound;
    RETURN NIL;
  END ThisCommand;

  PROCEDURE Free* (name: ARRAY OF CHAR; all: BOOLEAN);
    VAR m, m1 : Module; i : LONGINT;
  BEGIN res := done;
    m := modules;
    WHILE (m # NIL) & (name # m.name^) DO m := m.next; END;
    IF m = NIL THEN importing := NewName(name); res := modNotFound;
    ELSIF m.refcnt # 0 THEN importing := m.name; res := refCntNotZero;
    ELSE IF m.imports = NIL THEN i := 0 ELSE i := LEN(m.imports^); END;
      WHILE i > 1 DO DEC(i); m1 := SYSTEM.VAL(Module, m.imports[i]); DEC(m1.refcnt) END ;
      IF all THEN
        IF m.imports = NIL THEN i := 0 ELSE i := LEN(m.imports^); END;
        WHILE i > 1 DO DEC(i); m1 := SYSTEM.VAL(Module, m.imports[i]); Free(m1.name^, TRUE) END ;
        res := done
      END ;
      m1 := modules;  (* recursive call may change list structure *)
      IF m1 = m THEN
        modules := m.next
      ELSE
        WHILE m1.next # m DO
          m1 := m1.next
        END;
        m1.next := m.next
      END;
      Kernel.mlist := SYSTEM.VAL(ADDRESS, modules);
    END;
  END Free;

  PROCEDURE SetFinalize*(name : ARRAY OF CHAR; finalize : PROCEDURE) : BOOLEAN;
    VAR
      mod : Module;
  BEGIN
    mod := modules;
    LOOP
      IF mod = NIL THEN
        RETURN FALSE;
      END;
      IF mod.name^ = name THEN
        mod.finalize := finalize;
        RETURN TRUE;
      END;
      mod := mod.next;
    END;
  END SetFinalize;

  (* pre: (Ei: 0 <= i < LEN(text): text[i] = 0X *)
  (* post: (module # NIL) & defined(module^) *)
  (* post: command = NIL -> unable to find command name *)
  (* post: command # NIL -> defined(command^) *)
  PROCEDURE ParseCommand*(text : ARRAY OF CHAR; VAR module, command : Name);
    VAR i, j : INTEGER; ch : CHAR;
  BEGIN i := 0;
    REPEAT ch := text[i]; INC(i); UNTIL (ch = 0X) OR (ch = '.') OR (i >= LEN(text));
    (* inv: i <-> number of characters in module name, including 0X *)

    (* copy original string to newly created array *)
    NEW(module, i); i := 0; j := 0;
    REPEAT ch := text[i]; module[j] := ch; INC(i); INC(j);
    UNTIL (ch = 0X) OR (ch = '.') OR (i >= LEN(text)) OR (j >= LEN(module^));
    module[j - 1] := 0X;

    ASSERT((ch = '.') OR (ch = 0X) OR (i >= LEN(text)), 1228); ASSERT(text[i - 1] = ch, 1229);
    IF (ch = '.') & (i < LEN(text)) THEN j := 0;
      REPEAT ch := text[i]; INC(i); INC(j); UNTIL (ch = 0X) OR (i >= LEN(text));
      (* inv: j <-> number of characters in command name, including 0X *)

      NEW(command, j); DEC(i, j); (* reset to starting index*) j := 0;
      (* copy to newly created command string *)
      REPEAT ch := text[i]; command[j] := ch; INC(i); INC(j);
      UNTIL (ch = 0X) OR (i >= LEN(text)) OR (j >= LEN(command^));
      command[j - 1] := 0X;
    ELSE command := NIL;
    END;
  END ParseCommand;

  PROCEDURE Terminate(exitcode : LONGINT);
    PROCEDURE finalize(m : Module); (* always finalize most recently loaded modules first *)
    BEGIN
      IF m # NIL THEN
        finalize(m.next);
        IF m.finalize # NIL THEN
          m.finalize;
        END;
      END;
      Kernel.TerminateOberon(exitcode);
    END finalize;

  BEGIN
    finalize(modules);
    exit(exitcode);
  END Terminate;

  PROCEDURE GetCommand(VAR mod, cmd : Name);
    VAR p : CommandLine.Parameter;
  BEGIN
    mod := NIL;
    cmd := NIL;
    (* See CommandLine for invariants about parameter handling *)
    IF CommandLine.ParameterCount > 1 THEN
      p := CommandLine.GetArg(1);
      ParseCommand(p^, mod, cmd);
    END;
    IF (mod = NIL) OR (cmd = NIL) THEN
      mod := OberonName;
      cmd := LoopName;
    END;
  END GetCommand;

  PROCEDURE Reason;
  BEGIN
    IF importing # NIL THEN
      Console.Str("Importing module '");
      Console.Str(importing^);
      Console.Ch("'");
      Console.Ln;
    END;
    IF imported # NIL THEN
      Console.Str("Imported module '");
      Console.Str(imported^);
      Console.Ch("'");
      Console.Ln;
    END;
    IF object # NIL THEN
      Console.Str("Imported object '");
      Console.Str(object^);
      Console.Ch("'");
      Console.Ln;
    END;
    CASE res OF
    | done: (* nop *)
    | fileNotFound: Console.Str('file not found');
    | notAnObj: Console.Str('not an object file');
    | fpMismatch: Console.Str('fingerprint mismatch');
    | corruptObj: Console.Str('corrupt object file');
    | cmdNotFound: Console.Str('command not found');
    | modNotFound: Console.Str('module not found');
    | notEnoughSpace: Console.Str('not enough space');
    | refCntNotZero: Console.Str('reference count not zero');
    | objNotFound: Console.Str('object file not found');
    | cyclicImport: Console.Str('cyclic import');
    | objVersionMismatch: Console.Str('version mismatch');
    | helperModNotFound: Console.Str('helper module not found');
    | special:
    ELSE Console.Str('res = '); Console.Int(res, 3);
    END;
    Console.Ln;
  END Reason;


  PROCEDURE Init;
    VAR
      b : BOOLEAN;
      mod : Module;
      loop : Command;
      m, c : Name;
  BEGIN
    SearchPath  := FileDir.GetEnvironmentPaths("SKL_SEARCH_PATH");
    EmptyString := NewName('');
    OberonName  := NewName('Oberon');
    LoopName    := NewName('Loop');

    indent := 0;
    ExportUseMap[ORD(Uconst) - 1] := Econst;
    ExportUseMap[ORD(Utype) - 1] := Etype;
    ExportUseMap[ORD(Uvar) - 1] := Evar;
    ExportUseMap[ORD(Uxproc) - 1] := Exproc; (* Uiproc <=> Eiproc *)
    ExportUseMap[ORD(Ucproc) - 1] := Ecproc;
    ExportUseMap[ORD(Upbstruc) - 1] := Estruc;
    ExportUseMap[ORD(Upvstruc) - 1] := Estruc;
    ExportUseMap[ORD(Urectd) - 1] := Erectd;
    ExportUseMap[ORD(Udarraytd) - 1] := Edarraytd;
    ExportUseMap[ORD(Uarraytd) - 1] := Earraytd;

    b := SetFinalize('FileDir', FileDir.terminate);
    Kernel.InstallTerminator(Terminate);

    (* FIXME: A module should be loaded by which will process
     * commandline arguments and determine if the Oberon system (or
     * some other specific module) should be loaded at startup - it should also
     * load things like device drivers for low-level modules
     * (eg: --display-driver XDisplay -vs- --display-driver MSWindows).  This
     * will make command line argument processing occur in one location and
     * provide a coherent place to put commandline arguments to the Oberon
     * system.
     *)

    GetCommand(m, c);
    mod := ThisMod(m^);
    IF (mod # NIL) & (res = done) THEN
      loop := ThisCommand(mod, c^);
      IF loop # NIL THEN
        loop; (* returns back to bootstrap loader *)
      ELSE
        Console.Str("unable to load command '");
        Console.Str(m^);
        Console.Ch('.');
        Console.Str(c^);
        Console.Ch("'");
        Console.Ln;
        Reason;
        Kernel.Terminate(1);
      END;
    ELSE
      Console.Str("unable to load module '");
      Console.Str(m^);
      Console.Ch("'");
      Console.Ln;
      Reason;
      Kernel.Terminate(1);
    END;
  END Init;

BEGIN
  SYSTEM.GETREG(1, modules);    (* R1 set by loader (initialize_modules()). *)
  Init;
END Modules.
