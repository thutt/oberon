MODULE O3Config;
  IMPORT
    SYSTEM,
    Console, (* for catastrophic errors *)
    Environment,
    Reals,
    FileDir,
    Files,
    Texts;

  CONST (* NIL *)
    NilValue* = 0;

  CONST (* unassigned address *)
    UndefAdr* = MAX(LONGINT);

  CONST
    HiddenNameSentinel*    = '@';      (* Sentinel for hidden names written to
                                        * symbol file (to make them unique &
                                        * inaccessible from source).
                                        *)

  CONST (* Register Information *)
    RegisterCount*  = 32;              (* Integer & Real registers are
                                        * symmetrical. *)
    RegisterParameter* = { 2..7 };     (* 6 parameters enregistered
                                        *   (integer & real).
                                        *
                                        * R5 /F5 : 1st register argument.
                                        * R6 /F6 : 2nd register argument.
                                        * R7 /F7 : 3rd register argument.
                                        * R8 /F8 : 4th register argument.
                                        * R9 /F9 : 5th register argument.
                                        * R10/F10: 6th register argument.
                                        *
                                        * All other arguments pushed on stack
                                        * from left to right.
                                        *
                                        * Caller saved, if value must be
                                        * preserved.
                                        *)
    RegisterReturn*    = { 1 };        (* Procedure return value.
                                        *
                                        * R1/F1: return value of procedure.
                                        *
                                        * Caller saved, if value must be
                                        * preserved.
                                        *)
    RegisterCallerSaved* = {  8..18 }; (* Temporaries for use in procedures.
                                        *
                                        * Caller saved if value needs to be
                                        * preserved.
                                        *
                                        * Integer & real registers.
                                        *)
    RegisterCalleeSaved* = { 19..28,   (* Procedure-local variables. *)
                             29, (* Stack frame pointer. *)
                             30, (* Stack pointer. *)
                             31  (* Procedure return address. *)
                           };


  CONST
    MinSysFlag*     = 0;
    MaxSysFlag*     = 2;
    DefaultSysFlag* = 0;

  CONST (*- Fingerprinting *)
    DefaultFP* = 0;        (* default finger print seed *)

  CONST (*- Import/Export *)
    (*
      MaxExportedTypes is used by the import/export system to denote which symbols are exported while
      still indicating that they have been referenced by the algorithm.

      inv MaxExportedTypes < MAX(INTEGER) DIV 2
      inv: MaxExportedTypes <= RecMaxPtrs DIV 2
    *)
    MaxExportedTypes* = 200;

  CONST (*- Scanner info *)
    MaxIdLen* = 24;  (* (Ei: 0 <= i < MaxIdLen: ident[i] = 0X *)
    EOT* = 0X; (* character returned from reading text files when
                * end-of-text is found (Files.Read returns this) *)

  CONST (*- compiler options: *)
    OptChkIndex*    = 0;  (* index check on *)
    OptChkOverflow* = 1;  (* overflow check on *)
    OptChkRange*    = 2;  (* range check on *)
    OptChkType*     = 3;  (* type check on *)
    OptNilChk*  = 4;  (* NIL pointer deref check (explicit & type guard) *)
    OptNewSF*       = 5;  (* generation of new symbol file allowed *)
    OptExtSF*       = 6;  (* extension of old symbol file allowed *)
    OptPointerInit* = 7;  (* pointer initialization *)
    OptAssert*      = 8;  (* assert evaluation *)
    OptTarget*      = 9;  (* target machine given *)
    OptDCE*         = 10; (* dead code elimination *)
    OptCopyProp*    = 11; (* copy propagation *)
    OptValueNumber* = 12; (* value numbering *)
    OptConstProp*   = 13; (* constant propagation *)
    OptSimpleSched* = 14; (* simple instruction scheduler *)

    (* default options *)
    DefaultOptions* = { OptChkIndex,
                        OptChkRange,
                        OptChkType,
                        OptNilChk,
                        OptPointerInit,
                        OptAssert,
                        OptDCE,
                        OptCopyProp,
                        OptConstProp,
                        OptValueNumber };

  TYPE (*- compilation source information *)
    SourceInfo* = RECORD
      source* : Texts.Text; (* source text, derived and opened from 'filename' *)
      beg* : LONGINT; (* offset in 'source' where parsing should begin *)
      options* : SET; (* command line options *)
      name* : ARRAY FileDir.FnLength OF CHAR; (* module name, if determinable; else [0] = 0X *)
      filename* : ARRAY 256 OF CHAR;
      target* : ARRAY MaxIdLen OF CHAR; (* code generator module *)
    END;

  TYPE
    (* size of the object file header; not allfields are exported but the size can still be used *)
    ObjHeader* = RECORD
      objtag*, objversion*, refoffs, nofexp*, nofprv* : LONGINT;
      nofdesc*, nofcom*, nofptr*, nofhlp*, noffix* : LONGINT;
    END;

    ObjHeaderInfo* = RECORD
      refblktag : CHAR; (* tag for reference block *)
      header : ObjHeader;
    END;

  CONST (*- ControlProc discriminator *)
    modulebegin* = 16;  moduleend* = -16;

  TYPE (*- module initialization record *)
    ControlProc = PROCEDURE (FileInfo : SourceInfo) : BOOLEAN;
    InitControl = POINTER TO InitControlDesc;
    InitControlDesc = RECORD
      prev, next : InitControl;
      begin, end : ControlProc;
    END;

  TYPE (*- File Handle *)
    File* = POINTER TO FileDesc;
    FileDesc* = RECORD
      err*  : BOOLEAN;  (* ~err -> last operation successful *)
      eof*  : BOOLEAN; (* eof -> end of file *)
      name* : FileDir.Filename;
    END;

  CONST (*- Invalid Handle *)
    InvalidHandle* = NIL; (* numeric representation of an invalid handle; used for error reporting *)

  CONST (*+ Number of file I/O procedures *)
    FileIONofProcs = 25;

  TYPE (*- File IO Descriptor *)
    FileIO* = POINTER TO FileIODesc;
    FileIODesc*  = RECORD
      x* : SHORTINT;
      opentext* : PROCEDURE (name : ARRAY OF CHAR; pos : LONGINT) : File;
      openbinary* : PROCEDURE (name : ARRAY OF CHAR; pos : LONGINT) : File;
      findandopenbinary* : PROCEDURE (name : ARRAY OF CHAR) : File;
      createbinary* : PROCEDURE (name : ARRAY OF CHAR) : File;
      createtext* : PROCEDURE (name : ARRAY OF CHAR) : File;
      close* : PROCEDURE (handle : File);
      delete* : PROCEDURE (handle : File);

      set* : PROCEDURE (handle : File; pos : LONGINT);
      pos* : PROCEDURE (handle : File) : LONGINT;
      makename* : PROCEDURE (srcPath : ARRAY OF CHAR;
                             name, ext : ARRAY OF CHAR;
                             VAR fname : ARRAY OF CHAR);
      register* : PROCEDURE (handle : File);

      write* : PROCEDURE (handle : File; ch : CHAR);
      writelint* : PROCEDURE (handle : File; l : LONGINT);
      writeset* : PROCEDURE (handle : File; s : SET);
      writenum* : PROCEDURE (handle : File; l : LONGINT);
      writereal* : PROCEDURE (handle : File; r : REAL);
      writelreal* : PROCEDURE (handle : File; r : LONGREAL);
      writebytes* : PROCEDURE (handle : File; VAR buf : ARRAY OF SYSTEM.BYTE; len : LONGINT);

      read* : PROCEDURE (handle : File; VAR ch : CHAR);
      readlint* : PROCEDURE (handle : File; VAR l : LONGINT);
      readset* : PROCEDURE (handle : File; VAR s : SET);
      readnum* : PROCEDURE (handle : File; VAR l : LONGINT);
      readreal* : PROCEDURE (handle : File; VAR r : REAL);
      readlreal* : PROCEDURE (handle : File; VAR r : LONGREAL);
      readbytes* : PROCEDURE (handle : File; VAR buf : ARRAY OF SYSTEM.BYTE; len : LONGINT);
    END;

  CONST (* Number of console procedures *)
    ConsoleNofProcs = 7;

  TYPE (*- Console Logging Descriptor *)
    ConsoleIO* = POINTER TO ConsoleIODesc;
    ConsoleIODesc* = RECORD
      x* : SHORTINT; (* number of procedures filled in *)
      bool* : PROCEDURE (b : BOOLEAN);
      ch* : PROCEDURE (ch : CHAR);
      str* : PROCEDURE (str : ARRAY OF CHAR);
      int* : PROCEDURE (x, digits : LONGINT);
      hex* : PROCEDURE (x : LONGINT);
      set* : PROCEDURE (s : SET);
      ln* : PROCEDURE;
    END;

  CONST
    (* XXX Maybe these should be in a low-level
     * code generator module? *)
    LProcParmOffset* = 12; (* Offset in stack of last pushed parameter --
                            * local procedures.  A static link is present on local
                            * procedures. *)
    XProcParmOffset* = 8;  (* Offset in stack of last pushed parameter for
                            * global procedures *)

  CONST (* number of command line argument parsing routines *)
    CommandlineNofProcs = 5;

  TYPE (*- Commandline Parsing Descriptor *)
    CompileArgument* = POINTER TO CompileArgumentDesc;
    CompileArgumentDesc* = RECORD
      x* : SHORTINT; (* number of procedures which were filled in *)
      arg* : PROCEDURE (VAR info : SourceInfo; VAR err : BOOLEAN);

      (* init: called prior to asking for next argument to initialize fields *)
      init* : PROCEDURE (VAR info : SourceInfo);

      (* defaultopt is called prior to obtain the default options *)
      defaultopt* : PROCEDURE (VAR info : SourceInfo);

      (* open is called prior to using the command line parser.  It is only called once *)
      open* : PROCEDURE (VAR info : SourceInfo);

      (* close is called to indicate the command line parser will no longer be used *)
      close* : PROCEDURE (VAR info : SourceInfo);
    END;

  CONST
    MachineInfoNofFields = 0;

  TYPE (*- Machine Information *)
    MachineInfo* = POINTER TO MachineInfoDesc;
    MachineInfoDesc* = RECORD
      x* : SHORTINT;
    END;

  CONST (*- Memory Allocation Block Size *)
    (*
      Changing this value requires intimate knowledge of the heap
      allocator and the type descriptor flags and is not something
      that should be undertaken lightly.  With the original design, it
      is a requirement to be a value that leaves the low-order 4 bits
      available for the garbage collector to use.

      Further, the heap allocator is set up to use this block size and
      changes to this value should also be reflected in the heap
      allocator in Kernel.Mod.
    *)
    AllocBlockSize* = 10H;

  CONST (*- Descriptor flags bits *)
    (*
      These descriptor flag bits are tightly coupled to the garbage
      collector.  See printed documentation for details on how these
      are used.

      These values are set here rather than being installed by the
      machine because they are designed to not require changing when
      creating a new backend.  Plus, changing them requires extensive
      changes to the Oberon Kernel module as well and that work should
      be discouraged.
    *)

    DescFlagsValidBit* = ASH(1, 30); (* indicates valid flags byte
                                      * and not pointer offset (see documentation) *)

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

  CONST (*- HALT: inclusive range of parameter of standard procedure *)
    HaltAssert* = 8;            (* anonymous ASSERT *)
    HaltRange* = 12;          (* value out of range *)
    HaltArray* = 13;            (* array bound failure *)
    HaltIGuard*  = 14;            (* implicit type guard failure *)
    HaltEGuard* = 15;            (* explicit type guard failure *)
    HaltCase* = 16;            (* ELSE-less CASE *)
    HaltFunc* = 17;            (* function procedure w/o RETURN *)
    HaltWith* = 18;            (* ELSE-less WITH *)
    HaltGuardCheck* = 19; (* NIL pointer used in type guard *)
    HaltPointerCheck* = 20; (* NIL pointer dereferenced *)
    MinHaltValue* = 1024;    (* value that is higher than the last Halt constant *)
    MaxHaltValue* = 16384;  (* maximum value for a HALT or ASSERT instruction *)

  CONST (*- flags for errors during initialization *)
    errConsole* = 0; errCommandLine* = 1; errFileIO* = 2; errMachine* = 3;

  VAR
    err- : BOOLEAN;
    machine- : MachineInfo;
    options- : SET; (* command line options *)

  VAR
    errflags : SET;
    init : InitControl;
    con : ConsoleIO;
    cmdline : CompileArgument;
    fileio : FileIO;
    srcF, symF, objF, refF : File;
    errobjname, errobjmod : POINTER TO ARRAY OF CHAR;

  (** MachineInfo setting *)
  PROCEDURE InstallMachine*(m : MachineInfo);
  BEGIN machine := m;
  END InstallMachine;

  (** Validation *)
  PROCEDURE ValidateConsole(VAR err : BOOLEAN);
  BEGIN
    IF (con = NIL) OR (con.x # ConsoleNofProcs) OR (con.bool = NIL)
       OR (con.ch = NIL) OR (con.str = NIL) OR (con.int = NIL)
       OR (con.hex = NIL) OR (con.set = NIL) OR (con.ln = NIL) THEN
      err := TRUE; INCL(errflags, errConsole);
    ELSE err := FALSE;
    END;
  END ValidateConsole;

  PROCEDURE ValidateCommandline(VAR err : BOOLEAN);
  BEGIN
    IF (cmdline = NIL) OR (cmdline.x # CommandlineNofProcs) OR (cmdline.arg = NIL) THEN
      err := TRUE; INCL(errflags, errCommandLine);
    ELSE err := FALSE;
    END;
  END ValidateCommandline;

  PROCEDURE ValidateFileIO(VAR err : BOOLEAN);
  BEGIN
    IF (fileio = NIL) OR (fileio.x # FileIONofProcs) OR
       (fileio.opentext = NIL) OR (fileio.openbinary = NIL) OR
       (fileio.findandopenbinary = NIL) OR (fileio.close = NIL) OR
       (fileio.read = NIL) THEN
      err := TRUE; INCL(errflags, errFileIO);
    ELSE err := FALSE;
    END;
  END ValidateFileIO;

  PROCEDURE ValidateMachine(VAR err : BOOLEAN);
  BEGIN
    IF (machine = NIL) OR (machine.x # MachineInfoNofFields) THEN
      err := TRUE; INCL(errflags, errMachine);
    ELSE err := FALSE;
    END;
  END ValidateMachine;

  (** Commandline Parsing *)
  PROCEDURE SetCommandline*(parser : CompileArgument);
  BEGIN cmdline := parser;
  END SetCommandline;

  (* Commandline arguments in the Oberon compiler have the following form:

      command line parsing
      Compiler command line syntax:

      Compiler.Compile [-{option}]... filename

      inv: Compiler.Compile <=> CommandLine.GetArg(1)
  *)
  PROCEDURE EnableOptions*(opt : SET);
  BEGIN options := options + opt;
  END EnableOptions;

  PROCEDURE DisableOptions*(opt : SET);
  BEGIN options := options - opt;
  END DisableOptions;

  PROCEDURE SourceInfoGetFile*(VAR info : SourceInfo; VAR err : BOOLEAN);
  BEGIN cmdline.arg(info, err);
  END SourceInfoGetFile;

  PROCEDURE SourceInfoInit*(VAR info : SourceInfo);
  BEGIN cmdline.init(info);
  END SourceInfoInit;

  PROCEDURE SourceInfoDefaultOpts*(VAR info : SourceInfo);
  BEGIN cmdline.defaultopt(info);
  END SourceInfoDefaultOpts;

  PROCEDURE SourceInfoOpen*(VAR info : SourceInfo);
  BEGIN cmdline.open(info);
  END SourceInfoOpen;

  PROCEDURE SourceInfoClose*(VAR info : SourceInfo);
  BEGIN cmdline.close(info);
  END SourceInfoClose;

  (** Console IO *)
  PROCEDURE SetConsole*(console : ConsoleIO);
  BEGIN con := console;
  END SetConsole;

  PROCEDURE LogWBool*(b : BOOLEAN);
  BEGIN con.bool(b);
  END LogWBool;

  PROCEDURE LogW*(ch : CHAR);
  BEGIN con.ch(ch);
  END LogW;

  PROCEDURE LogWStr*(s : ARRAY OF CHAR);
  BEGIN con.str(s);
  END LogWStr;

  PROCEDURE LogWNum*(x, digits : LONGINT);
  BEGIN con.int(x, digits);
  END LogWNum;

  PROCEDURE LogWPtr*(ptr : SYSTEM.PTR);
  BEGIN con.hex(SYSTEM.VAL(LONGINT, ptr));
  END LogWPtr;

  PROCEDURE LogWHex*(x : LONGINT);
  BEGIN con.hex(x);
  END LogWHex;

  PROCEDURE LogWSet*(s : SET);
  BEGIN  con.set(s);
  END LogWSet;

  PROCEDURE LogWLn*;
  BEGIN con.ln;
  END LogWLn;

  (** Error Message Handling *)

  PROCEDURE Message(v : INTEGER; msg : ARRAY OF CHAR);
  BEGIN
    LogWLn; LogWStr(msg); LogWNum(v, 8); LogW(' ');
    IF (srcF # NIL) & ~srcF.err THEN
      LogWStr(" pos"); LogWNum(fileio.pos(srcF), 6);
      IF errobjmod # NIL THEN LogW(' '); LogWStr(errobjmod^); errobjmod := NIL; END;
      IF errobjname # NIL THEN LogW(' '); LogWStr(errobjname^); errobjname := NIL; END;
    END;
  END Message;

  PROCEDURE Error*(e : INTEGER);
  BEGIN Message(e, "  err"); err := TRUE;
  END Error;

  PROCEDURE Hint*(h : INTEGER);
  BEGIN Message(h, "  hint");
  END Hint;

  PROCEDURE Warn*(w : INTEGER);
  BEGIN Message(w, "  warning");
  END Warn;

  PROCEDURE Fatal*(e : INTEGER);
  BEGIN Message(e, "  fatal"); HALT(151);
  END Fatal;

  (* set an object module name for improved error output *)
  PROCEDURE SetObjModule*(mod : ARRAY OF CHAR); (* pre: LEN(mod) <= LEN(objmod) *)
  BEGIN IF (errobjmod = NIL) OR (LEN(mod) > LEN(errobjmod^)) THEN NEW(errobjmod, LEN(mod)); END;
    COPY(mod, errobjmod^);
  END SetObjModule;

  (* set a symbol name for improved error output *)

  PROCEDURE SetObjName*(name : ARRAY OF CHAR); (* pre: LEN(name) <= LEN(objname) *)
  BEGIN IF (errobjname = NIL) OR (LEN(name) > LEN(errobjname^)) THEN NEW(errobjname, LEN(name)); END;
    COPY(name, errobjname^);
  END SetObjName;

  (** Source File IO *)

  PROCEDURE Get*(VAR ch : CHAR);
  BEGIN fileio.read(srcF, ch);
  END Get;

  PROCEDURE OpenSource*(name : ARRAY OF CHAR; pos : LONGINT; VAR err : BOOLEAN);
  BEGIN
    srcF := fileio.opentext(name, pos); (* 'name' contains full pathname. *)
    err := srcF = InvalidHandle;
  END OpenSource;

  PROCEDURE CloseSource*;
  BEGIN fileio.close(srcF);
  END CloseSource;

  (* sets the source file position for reporting errors *)
  PROCEDURE SetSourcePos*(pos : LONGINT);
  BEGIN fileio.set(srcF, pos);
  END SetSourcePos;

  PROCEDURE GetSourcePos*(VAR pos : LONGINT);
  BEGIN pos := fileio.pos(srcF);
  END GetSourcePos;

  (** Obj/Ref File IO *)

  PROCEDURE NewRefObj*(modname : ARRAY OF CHAR;
                       objext, refext : ARRAY OF CHAR;
                       VAR err : BOOLEAN);
    VAR
      refName, objName : FileDir.Filename;
  BEGIN
    fileio.makename(srcF.name, modname, objext, objName);
    objF := fileio.createbinary(objName);
    IF objF # InvalidHandle THEN
      fileio.set(objF, SIZE(ObjHeader)); (* leave room for Obj header *)
      fileio.makename(srcF.name, modname, refext, refName);
      refF := fileio.createbinary(refName);
      IF refF = InvalidHandle THEN
        err := TRUE;
      END;
    ELSE
      err := TRUE;
    END;
  END NewRefObj;

  PROCEDURE DeleteObj*;
  BEGIN ASSERT(objF # NIL, 1024); fileio.delete(objF);
  END DeleteObj;

  PROCEDURE DeleteRef*;
  BEGIN ASSERT(refF # NIL, 1025); fileio.delete(refF);
  END DeleteRef;

  PROCEDURE RegisterRefObj*(h : ObjHeaderInfo);
    VAR ch : CHAR;
  BEGIN
    (* objF is assumed to be positioned at the end *)
    ASSERT(FALSE); (* reference block tag must be initialized *)
    h.header.refoffs := fileio.pos(objF); (* offset in Obj file where reference block begins *)
    fileio.write(objF, h.refblktag);

    fileio.set(refF, 0); (* read the ref file & write it to the obj file *)
    WHILE ~refF.eof DO fileio.read(refF, ch); fileio.write(objF, ch); END;

    (* The documented structure of the object file format requires that
        the first two fields of the header be 4 bytes in size.  If the size
        of a LONGINT is not 4 bytes, then this code must be rewritten
        to output those two fields as 4-byte values.
    *)
    ASSERT(SIZE(LONGINT) = 4, 1024);

    (* write out the header block *)
    fileio.set(objF, 0); fileio.writebytes(objF, h.header, SIZE(ObjHeader));
    fileio.close(objF); fileio.register(objF);
    fileio.close(refF);  fileio.delete(refF);
  END RegisterRefObj;

  PROCEDURE RefW*(ch : CHAR);
  BEGIN fileio.write(refF, ch);
  END RefW;

  PROCEDURE RefWNum*(i: LONGINT);
  BEGIN fileio.writenum(refF, i);
  END RefWNum;

  PROCEDURE ObjW*(ch: CHAR);
  BEGIN fileio.write(objF, ch);
  END ObjW;

  PROCEDURE ObjWNum*(i: LONGINT);
  BEGIN fileio.writenum(objF, i);
  END ObjWNum;

  PROCEDURE ObjWLInt*(i: LONGINT);
  BEGIN fileio.writelint(objF, i);
  END ObjWLInt;

  PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
  BEGIN fileio.writebytes(objF, bytes, n);
  END ObjWBytes;

  (** Symbol File *)

  PROCEDURE SymWCh*(ch : CHAR);
  BEGIN
    fileio.write(symF, ch);
  END SymWCh;

  PROCEDURE SymWInt*(i : LONGINT);
  BEGIN
    fileio.writenum(symF, i);
  END SymWInt;

  PROCEDURE SymWBool*(VAR x : BOOLEAN);
  BEGIN
    IF x THEN
      SymWInt(1);
    ELSE
      SymWInt(0);
    END; (* see SymRBool *)
  END SymWBool;

  PROCEDURE SymWSet*(s : SET);
  BEGIN
    fileio.writeset(symF, s);
  END SymWSet;

  PROCEDURE SymWReal*(f : REAL);
  BEGIN
    fileio.writereal(symF, f);
  END SymWReal;

  PROCEDURE SymWLReal*(d : LONGREAL);
  BEGIN
    fileio.writelreal(symF, d);
  END SymWLReal;

  PROCEDURE SymRCh*(VAR x : CHAR; VAR eofSF : BOOLEAN);
  BEGIN
    fileio.read(symF, x);
    eofSF := symF.eof;
  END SymRCh;

  PROCEDURE SymRInt*(VAR x : LONGINT; VAR eofSF : BOOLEAN);
  BEGIN
    fileio.readnum(symF, x);
    eofSF := symF.eof;
  END SymRInt;

  PROCEDURE SymRBool*(VAR x : BOOLEAN; VAR eofSF : BOOLEAN);
    VAR i : LONGINT;
  BEGIN
    SymRInt(i, eofSF);
    x := i = 1; (* see SymWBool *)
  END SymRBool;

  PROCEDURE SymRSet*(VAR x : SET; VAR eofSF : BOOLEAN);
  BEGIN
    fileio.readset(symF, x);
    eofSF := symF.eof;
  END SymRSet;

  PROCEDURE SymRReal*(VAR x : REAL; VAR eofSF : BOOLEAN);
  BEGIN
    fileio.readreal(symF, x);
    eofSF := symF.eof;
  END SymRReal;

  PROCEDURE SymRLReal*(VAR x : LONGREAL; VAR eofSF : BOOLEAN);
  BEGIN
    fileio.readlreal(symF, x);
    eofSF := symF.eof;
  END SymRLReal;

  PROCEDURE NewSym*(modname, sfext : ARRAY OF CHAR;
                    sftag, sfversion : CHAR;
                    VAR err : BOOLEAN);
    VAR
      fname : FileDir.Filename;
  BEGIN
    fileio.makename(srcF.name, modname, sfext, fname);
    symF := fileio.createbinary(fname);
    IF symF # InvalidHandle THEN
      err := FALSE;
      fileio.write(symF, sftag);
      fileio.write(symF, sfversion);
    ELSE
      err := TRUE;
    END;
  END NewSym;

  PROCEDURE RegisterNewSym*;
  BEGIN
    fileio.close(symF);
    fileio.register(symF);
  END RegisterNewSym;

  PROCEDURE DeleteNewSym*;
  BEGIN
    fileio.close(symF);
    fileio.delete(symF);
    symF := NIL;
  END DeleteNewSym;

  (* post: err -> symF is not open *)
  (* post: ~err -> symF is open *)
  PROCEDURE OldSym*(modname, sfext : ARRAY OF CHAR;
                    sftag, sfversion : CHAR;
                    VAR err : BOOLEAN);
    VAR
      fname : FileDir.Filename;
      tag, version : CHAR;
  BEGIN
    ASSERT(symF = NIL, 1024);
    err := FALSE;
    fileio.makename(srcF.name, modname, sfext, fname);
    symF := fileio.openbinary(fname, 0);
    IF symF = NIL THEN
      symF := fileio.findandopenbinary(fname);
    END;

    IF symF # NIL THEN
      fileio.read(symF, tag);
      fileio.read(symF, version);
      IF symF.eof OR (tag # sftag) OR (version # sfversion) THEN
        err := TRUE;
        fileio.close(symF);
        symF := NIL;
      END;
    ELSE
      err := TRUE;
    END;
  END OldSym;

  PROCEDURE CloseOldSym*;
  BEGIN
    fileio.close(symF);
    symF := NIL;
  END CloseOldSym;

  (** Generic File Handling *)

  (* pre: ASCIIZ(name); *)
  (* post: handle = NIL -> error; file not opened *)
  (* post: handle # NIL -> success; defined(handle^)*)
  PROCEDURE CreateBinary*(name : ARRAY OF CHAR; VAR handle : File);
    VAR
      fname : FileDir.Filename;

  BEGIN
    fileio.makename(srcF.name, name, "", fname);
    handle := fileio.createbinary(fname);
  END CreateBinary;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: file associated with handle will be closed & deleted *)
  (* post: handle = NIL *)
  PROCEDURE Delete*(VAR handle : File);
  BEGIN fileio.close(handle); fileio.delete(handle); handle := NIL;
  END Delete;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: file associated with handle will be closed and registered in directory *)
  (* post: handle = NIL *)
  PROCEDURE Register*(VAR handle : File);
  BEGIN fileio.close(handle); fileio.register(handle); handle := NIL;
  END Register;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadCh*(handle : File; VAR x : CHAR; VAR eof : BOOLEAN);
  BEGIN fileio.read(handle, x); eof := handle.eof;
  END ReadCh;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadInt*(handle : File; VAR x : LONGINT; VAR eof : BOOLEAN);
  BEGIN fileio.readlint(handle, x); eof := handle.eof;
  END ReadInt;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadSet*(handle : File; VAR x : SET; VAR eof : BOOLEAN);
  BEGIN fileio.readset(handle, x); eof := handle.eof;
  END ReadSet;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadReal*(handle : File; VAR x : REAL; VAR eof : BOOLEAN);
  BEGIN fileio.readreal(handle, x); eof := handle.eof;
  END ReadReal;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadLReal*(handle : File; VAR x : LONGREAL; VAR eof : BOOLEAN);
  BEGIN fileio.readlreal(handle, x); eof := handle.eof;
  END ReadLReal;

  (* pre: handle # NIL & defined(handle^) *)
  (* pre: n <= LEN(x) *)
  (* post: eof -> failure & undefined(x) *)
  (* post: ~eof -> success & x = data read from file *)
  PROCEDURE ReadBytes*(handle : File; VAR x : ARRAY OF SYSTEM.BYTE; n : LONGINT; VAR eof : BOOLEAN);
  BEGIN fileio.readbytes(handle, x, n); eof := handle.eof;
  END ReadBytes;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: x is written to the file *)
  PROCEDURE WriteCh*(handle : File; x : CHAR);
  BEGIN fileio.write(handle, x);
  END WriteCh;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: x is written to the file *)
  PROCEDURE WriteInt*(handle : File; x : LONGINT);
  BEGIN fileio.writelint(handle, x);
  END WriteInt;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: x is written to the file *)
  PROCEDURE WriteSet*(handle : File; x : SET);
  BEGIN fileio.writeset(handle, x);
  END WriteSet;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: x is written to the file *)
  PROCEDURE WriteReal*(handle : File; x : REAL);
  BEGIN fileio.writereal(handle, x);
  END WriteReal;

  (* pre: handle # NIL & defined(handle^) *)
  (* post: x is written to the file *)
  PROCEDURE WriteLReal*(handle : File; x : LONGREAL);
  BEGIN fileio.writelreal(handle, x);
  END WriteLReal;

  (* pre: handle # NIL & defined(handle^) *)
  (* pre: n <= LEN(x) *)
  (* post: x is written to the file *)
  PROCEDURE WriteBytes*(handle : File; x : ARRAY OF SYSTEM.BYTE; n : LONGINT);
  BEGIN fileio.writebytes(handle, x, n);
  END WriteBytes;

  PROCEDURE WriteString*(handle : File; x : ARRAY OF CHAR);
    VAR i, l : LONGINT; ch : CHAR;
  BEGIN l := LEN(x); i := 0; ch := x[0];  WHILE (ch # 0X) & (i < l) DO WriteCh(handle, ch); INC(i); ch := x[i]; END;
  END WriteString;

  PROCEDURE WriteStringNum*(handle : File; x, n : LONGINT);
    VAR i: INTEGER; x0: LONGINT; a: ARRAY 11 OF CHAR;
  BEGIN i := 0;
    IF x < 0 THEN
      IF x = MIN(LONGINT) THEN WriteString(handle, " -2147483648"); RETURN
      ELSE DEC(n); x0 := -x
      END
    ELSE x0 := x
    END;
    REPEAT a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i) UNTIL x0 = 0;
    WHILE n > i DO WriteCh(handle,  " "); DEC(n) END;
    IF x < 0 THEN WriteCh(handle, "-") END;
    REPEAT DEC(i); WriteCh(handle, a[i]) UNTIL i = 0
  END WriteStringNum;

  PROCEDURE WriteStringHex*(handle : File; x : LONGINT);
    VAR  i: LONGINT; y: LONGINT; a: ARRAY 10 OF CHAR;
  BEGIN i := 0;
    REPEAT y := x MOD 10H;
      IF y < 10 THEN a[i] := CHR(y + 30H) ELSE a[i] := CHR(y + 37H) END;
      x := x DIV 10H; INC(i)
    UNTIL i = 8;
    a[i] := 0X;
    REPEAT DEC(i); WriteCh(handle, a[i]); UNTIL i = 0;
  END WriteStringHex;

  PROCEDURE WriteStringSet*(handle : File; s : SET);
    VAR i, j: INTEGER; notfirst: BOOLEAN;
  BEGIN
    i := 0; notfirst := FALSE; WriteCh(handle, "{");
    WHILE i <= MAX(SET) DO
      IF i IN s THEN
        IF notfirst THEN WriteString(handle, ", ")
        ELSE notfirst := TRUE
        END ;
        j := i; WriteStringNum(handle, i, 1); INC(i);
        WHILE (i <= MAX(SET)) & (i IN s) DO INC(i) END ;
        IF i - 1 > j THEN
          IF i - 2 = j THEN WriteString(handle, ", ") ELSE WriteString(handle, "..") END ;
          WriteStringNum(handle, i - 1, 1)
        END
      END ;
      INC(i)
    END ;
    WriteCh(handle, "}");
  END WriteStringSet;

  PROCEDURE WriteStringLReal*(handle : File; x : LONGREAL; n : LONGINT);
    VAR e, h, l, i: LONGINT; z: LONGREAL; d: ARRAY 16 OF CHAR;
  BEGIN
    e:= Reals.ExpoL(x);
    IF e = 2047 THEN
      WHILE n > 9 DO WriteCh(handle, " "); DEC(n) END;
      WriteString(handle, "      NaN")
    ELSE
      IF n <= 9 THEN n:= 1 ELSE DEC(n, 8) END;
      REPEAT WriteCh(handle, " "); DEC(n) UNTIL n <= 15; (* 0 <= n <= 15 fraction digits *)
      IF (e # 0) & (x < 0) THEN WriteCh(handle, "-"); x:= - x ELSE WriteCh(handle, " ") END;
      IF e = 0 THEN h:= 0; l:= 0 (* no denormals *)
      ELSE e:= (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
        z:= Reals.TenL(SHORT(e+1));
        IF x >= z THEN x:= x / z; INC(e); ELSE x:= x * Reals.Ten(SHORT(-e)); END;
       IF x >= 10 THEN x:= x * Reals.TenL(-1) + 0.5D0 / Reals.TenL(SHORT(n)); INC(e);
        ELSE x:= x + 0.5D0 / Reals.Ten(SHORT(n));
    IF x >= 10 THEN x:= x * Reals.Ten(-1); INC(e); END;
        END;
        x:= x * Reals.Ten(7); h:= ENTIER(x); x:= (x-h) * Reals.Ten(8); l:= ENTIER(x);
      END;
      i:= LEN(d)-1; WHILE i > 7 DO d[i]:= CHR(l MOD 10 + ORD("0")); l:= l DIV 10; DEC(i) END;
      WHILE i >= 0 DO
      d[i]:= CHR(h MOD 10 + ORD("0")); h:= h DIV 10; DEC(i) END;
      WriteCh(handle, d[0]); WriteCh(handle, "."); i:= 1; WHILE i <= n DO WriteCh(handle, d[i]); INC(i) END;
      IF e < 0 THEN WriteString(handle, "D-"); e:= - e ELSE WriteString(handle, "D+") END;
      WriteCh(handle, CHR(e DIV 100 + ORD("0"))); e:= e MOD 100;
      WriteCh(handle, CHR(e DIV 10 + ORD("0"))); WriteCh(handle, CHR(e MOD 10 + ORD("0")));
    END;
  END WriteStringLReal;

  PROCEDURE WriteStringReal*(handle : File; x  : REAL; n : LONGINT);
  VAR e : INTEGER; h, i: LONGINT; y: LONGREAL; z: REAL; d: ARRAY 8 OF CHAR;
  BEGIN
    e:= Reals.Expo(x);
    IF e = 255 THEN
      WHILE n > 8 DO WriteCh(handle, " "); DEC(n) END;
      WriteString(handle, "     NaN")
    ELSE
      IF n <= 8 THEN n := 1 ELSE DEC(n, 7) END;
      REPEAT WriteCh(handle, " "); DEC(n) UNTIL n <= 7; (* 0 <= n <= 7 fraction digits *)
      IF (e # 0) & (x < 0) THEN WriteCh(handle, "-"); x := - x ELSE WriteCh(handle, " ") END;
      IF e = 0 THEN h := 0 (* no denormals *)
      ELSE e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
        IF e < 38 THEN z := Reals.Ten(e+1);
          IF x >= z THEN y := LONG(x)/LONG(z); INC(e) ELSE y := x * Reals.Ten(-e) END
        ELSE y := x * Reals.Ten(-38) END;
        IF y >= 10 THEN y := y * Reals.Ten(-1) + 0.5D0 / Reals.Ten(SHORT(n)); INC(e)
        ELSE y := y + 0.5D0 / Reals.Ten(SHORT(n));
          IF y >= 10 THEN y := y * Reals.Ten(-1); INC(e) END
        END;
        y := y * Reals.Ten(7); h := ENTIER(y)
      END;
      i := 7;
      WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
      WriteCh(handle, d[0]); WriteCh(handle, "."); i := 1; WHILE i <= n DO WriteCh(handle, d[i]); INC(i) END;
      IF e < 0 THEN WriteString(handle, "E-"); e := - e ELSE WriteString(handle, "E+") END;
      WriteCh(handle, CHR(e DIV 10 + ORD("0")));
      WriteCh(handle, CHR(e MOD 10 + ORD("0")));
    END;
  END WriteStringReal;

  (** Alignment *)

  PROCEDURE PositiveAlign*(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    CASE align OF
    |  1: (* alignment always ok *)
    | 2: INC(offset, (-offset) MOD 2);
    | 4: INC(offset, (-offset) MOD 4);
    | 8: INC(offset, (-offset) MOD 8);
    | 16: INC(offset, (-offset) MOD 16);
    | 32: INC(offset, (-offset) MOD 32);
    | 64: INC(offset, (-offset) MOD 64);
    | 128: INC(offset, (-offset) MOD 128);
    END
  END PositiveAlign;

  PROCEDURE NegativeAlign*(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    CASE align OF
    |  1: (* alignment always ok *)
    | 2: DEC(offset, offset MOD 2)
    | 4: DEC(offset, offset MOD 4)
    | 8: DEC(offset, offset MOD 8)
    | 16: DEC(offset, offset MOD 16);
    | 32: DEC(offset, offset MOD 32);
    | 64: DEC(offset, offset MOD 64);
    | 128: DEC(offset, offset MOD 128);
    END
  END NegativeAlign;

  (** File IO *)

  PROCEDURE SetFileIO*(io : FileIO);
  BEGIN fileio := io;
  END SetFileIO;

  (** Pre- and post- compilation housekeeping *)
  PROCEDURE ModuleBegin(FileInfo : SourceInfo) : BOOLEAN;
  BEGIN err := FALSE;
    (* if an error occurs during this particular module's
      pre-compilation process, then an error message cannot be
      reliably be output because they may be
      nothing on which the message can be displayed.
    *)
    ValidateConsole(err);
    ValidateCommandline(err);
    ValidateFileIO(err);
    ValidateMachine(err);
    options := {};
    IF err OR (errflags # {}) THEN Console.Ln;
      Console.Ln; Console.Str("Subsystem Initialization Failure. "); Console.Ch(7X);
      Console.Ln; Console.Str("Configuration error flags are: "); Console.Set(errflags);
      Console.Ln; Console.Str("Refer to Config.errorflags");
      Console.Ln;
      Fatal(-1024);
    END;
    RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : SourceInfo) : BOOLEAN;
  BEGIN srcF := InvalidHandle; symF := InvalidHandle; objF := InvalidHandle; refF := InvalidHandle; RETURN TRUE;
  END ModuleEnd;

  PROCEDURE DoControlProc*(which : SHORTINT; FileInfo : SourceInfo);
    VAR c : InitControl; b : BOOLEAN;
  BEGIN
    CASE which OF
    | modulebegin:
      c := init.next;
      WHILE c # init DO
        ASSERT(c.begin # NIL, 128);
        b := c.begin(FileInfo);
        IF ~b THEN
          Console.Str("module initialization failure");
          Fatal(-1025);
        END;
        c := c.next;
      END;
    | moduleend:
      c := init.prev;
      WHILE c # init DO
        ASSERT(c.end # NIL, 129);
        b := c.end(FileInfo);
        IF ~b THEN
          Console.Str("module finalization failure");
          Fatal(-1025);
        END;
        c := c.prev;
      END;
    END;
  END DoControlProc;

  PROCEDURE ControlModule*(b, e : ControlProc);
    VAR r, c : InitControl;
  BEGIN
    NEW(c);
    c.begin := b;
    c.end := e;
    init.prev.next := c;
    c.prev := init.prev;
    init.prev := c;
    c.next := init;
  END ControlModule;

  (** Internal housekeeping *)
  PROCEDURE NILGlobalPointers;
  BEGIN
    con := NIL;
    cmdline := NIL;
    fileio := NIL;
    errobjname := NIL;
    errobjmod := NIL;
    machine := NIL;
  END NILGlobalPointers;

  (* occurs prior to any other programmed (non-module initialization) function for a compile *)
  PROCEDURE Initialize*;
  BEGIN err := FALSE; errflags := {};
  END Initialize;

  (* occurs after any other programmed function for a compile *)
  PROCEDURE Finalize*;
  BEGIN NILGlobalPointers;
  END Finalize;

  PROCEDURE Init;
  BEGIN
    NILGlobalPointers;
    NEW(init);
    init.begin := NIL;
    init.end := NIL;
    init.prev := init;
    init.next := init; (* dummy list header *)
    ControlModule(ModuleBegin, ModuleEnd);
  END Init;

BEGIN
  Init;
END O3Config.
