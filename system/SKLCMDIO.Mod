MODULE SKLCMDIO; (* Command Line IO *)
IMPORT
  SYSTEM, 
  Objects, 
  EL:=SKLERR, 
  FileDir, 
  Files, 
  Texts, 
  CommandLine, 
  GetOpt,
  Kernel,
  Console;

  CONST (* compiler options: *)
    InxChk* = 0;  (* index check on *)
    OvflChk* = 1;  (* overflow check on *)
    RanChk* = 2;  (* range check on *)
    TypChk* = 3;  (* type check on *)
    NewSF* = 4;  (* generation of new symbol file allowed *)
    ExtSF* = 5;  (* extension of old symbol file allowed *)
    PtrInit* = 6;  (* pointer initialization *)
    Assert* = 7;  (* assert evaluation *)
    FindPC* = 8;  (* find text position of breakpc *)
    OptPtrChk* = 9; (* NIL pointer deref check (explicit & type guard) *)
    OptDumpNode* = 10; (* when enabled, dumps out the AST *)
    OptBanner* = 11; (* OptBanner IN options => print banner & exit *)
    OptHashStats* = 12; (* HashStats IN options => print hash table statistics *)
    DefaultOptions* = {InxChk, RanChk, TypChk, PtrInit, Assert, OptPtrChk};  (* default options *)

  TYPE
    SourceInfo* = RECORD
      source- : Texts.Text; (* source text, derived and opened from 'filename' *)
      beg- : LONGINT; (* offset in 'source' where parsing should begin *)
      options- : SET; (* command line options *)
      pc- : LONGINT; (* pc used for finding runtime errors *)
      name- : ARRAY FileDir.FnLength OF CHAR; (* module name, if determinable; else [0] = 0X *)
      filename- : ARRAY 24 OF CHAR; (* OPM.MaxIdLen *)
    END;

    CurrentSourceInfo = RECORD
      FileInfo : SourceInfo;
      ModF : Texts.Reader;
      SymF, RefF, ObjF : Files.Rider;
      SymFile, RefFile, ObjFile : Files.File;
      lastpos : LONGINT;
      curpos : LONGINT;
    END;
    
    ObjHeader* = RECORD
      nofexp*, nofprv*, nofdesc*, nofcom*, nofptr*, nofhlp*, noffix* : LONGINT;
    END;

  VAR
    objname, objmod : ARRAY 24 OF CHAR;
    CFI : CurrentSourceInfo; (* CurrentFileInfo *)

    (* current command line parameter *)    
    CurrentArg : INTEGER; (* inv: 1 <= CurrentParm <= MAX(INTEGER) (index into CommandLine arguments; 0-based) *)

    handle : GetOpt.Handle;
    
  PROCEDURE MakeFilename(VAR name, FName: ARRAY OF CHAR; ext: ARRAY OF CHAR);
    VAR i, j: INTEGER; ch: CHAR;
  BEGIN i := 0;
    LOOP ch := name[i];
      IF ch = 0X THEN EXIT END ;
      FName[i] := ch; INC(i);
    END ;
    j := 0;
    REPEAT ch := ext[j]; FName[i] := ch; INC(i); INC(j)
    UNTIL ch = 0X
  END MakeFilename;
  
  (* ------------------------- Log Output ------------------------- *)

  PROCEDURE LogWSet*(s : SET);
  BEGIN  Console.Set(s);
  END LogWSet;

  PROCEDURE LogW*(ch : CHAR);
  BEGIN Console.Ch(ch);
  END LogW;

  PROCEDURE LogWStr*(s : ARRAY OF CHAR);
  BEGIN Console.Str(s);
  END LogWStr;

  PROCEDURE LogWBool*(b : BOOLEAN);
  BEGIN
    IF b THEN LogWStr("TRUE");
    ELSE LogWStr("FALSE");
    END;
  END LogWBool;

  PROCEDURE LogWNum*(x, digits : LONGINT);
  BEGIN Console.Int(x, digits);
  END LogWNum;
  
  PROCEDURE LogWHex*(x : LONGINT);
  BEGIN Console.Hex(x);
  END LogWHex;

  PROCEDURE LogWLn*;
  BEGIN Console.Ln;
  END LogWLn;

  PROCEDURE Mark*(n: INTEGER; pos: LONGINT; VAR noerr : BOOLEAN);
  BEGIN noerr := FALSE;
    IF (pos < CFI.lastpos) OR (CFI.lastpos + 9 < pos) THEN CFI.lastpos := pos;
      LogWLn; LogWStr("  pos"); LogWNum(pos, 6); LogWStr("  err"); LogWNum(n, 4); LogW(' ');
      IF objmod[0] # 0X THEN LogWStr(objmod); LogW('.'); objmod[0] := 0X; END;
      IF objname[0] # 0X THEN LogWStr(objname); objname[0] := 0X; END;
    END ;
    IF n = 255 THEN HALT(132) END
  END Mark;
  
  PROCEDURE err*(n: INTEGER; VAR noerr : BOOLEAN);
  BEGIN Mark(n, CFI.curpos, noerr)
  END err;
  
  PROCEDURE SetSourceTextPos*(pos : LONGINT);
  BEGIN CFI.curpos := pos;
  END SetSourceTextPos;

  (* ------------------------- Scanner Input ------------------------- *)

  PROCEDURE Get*(VAR ch: CHAR);  (* read next character from source text, Eot if no more *)
  BEGIN Texts.Read(CFI.ModF, ch); INC(CFI.curpos);
  END Get;

  PROCEDURE OpenSource*(VAR FileInfo : SourceInfo; VAR noerr : BOOLEAN);
  BEGIN noerr := TRUE;
    Texts.OpenReader(CFI.ModF, FileInfo.source, FileInfo.beg); CFI.curpos := Texts.Pos(CFI.ModF);
    CFI.lastpos := CFI.curpos - 10;
  END OpenSource;

  PROCEDURE  CloseSource*(VAR FileInfo : SourceInfo);
  END CloseSource;

  (* ------------------ Object / Reference File ------------------ *)

  PROCEDURE RefW*(ch: CHAR);
  BEGIN Files.Write(CFI.RefF, ch);
  END RefW;

  PROCEDURE RefWNum*(i: LONGINT);
  BEGIN Files.WriteNum(CFI.RefF, i);
  END RefWNum;
  
  PROCEDURE ObjW*(ch: CHAR);
  BEGIN Files.Write(CFI.ObjF, ch);
  END ObjW;

  PROCEDURE ObjWNum*(i: LONGINT);
  BEGIN Files.WriteNum(CFI.ObjF, i);
  END ObjWNum;

  PROCEDURE ObjWLInt*(i: LONGINT);
  BEGIN Files.WriteBytes(CFI.ObjF, i, SIZE(LONGINT));
  END ObjWLInt;

  PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
  BEGIN Files.WriteBytes(CFI.ObjF, bytes, n);
  END ObjWBytes;

  PROCEDURE NewRefObj*(VAR modName (* r/o *) : ARRAY OF CHAR; OFext, RFext : ARRAY OF CHAR; OFtag, OFversion : LONGINT; VAR noerr : BOOLEAN);
    VAR objName, refName: FileDir.Filename;
  BEGIN
    MakeFilename(modName, objName, OFext); MakeFilename(modName, refName, RFext);
    CFI.ObjFile := Files.New(objName);
    IF CFI.ObjFile # NIL THEN
      Files.Set(CFI.ObjF, CFI.ObjFile, 0); Files.WriteLInt(CFI.ObjF, OFtag); Files.WriteLInt(CFI.ObjF, OFversion);
    ELSE err(EL.CannotOpenObjFile, noerr);
    END;
    
    CFI.RefFile := Files.New(refName);
    IF CFI.RefFile # NIL THEN Files.Set(CFI.RefF, CFI.RefFile, 0);
    ELSE err(EL.CannotOpenRefFile, noerr);
    END;
  END NewRefObj;

  PROCEDURE DeleteRefObj*;
  BEGIN Files.Purge(CFI.RefFile); Files.Purge(CFI.ObjFile);
  END DeleteRefObj;

  PROCEDURE RegisterRefObj*(VAR header : ObjHeader);
    VAR ch : CHAR;
  BEGIN
    Files.Write(CFI.ObjF,  8DX); (* reference block tag *)
    Files.Set(CFI.RefF,CFI.RefFile, 0);
    WHILE ~CFI.RefF.eof DO
      Files.Read(CFI.RefF, ch);
      Files.Write(CFI.ObjF, ch);
    END;
    Files.Set(CFI.ObjF, CFI.ObjFile, 9); (* MagicBlk size + header block tag *)
    Files.WriteLInt(CFI.ObjF, Files.Length(CFI.RefFile));
    Files.WriteLInt(CFI.ObjF, header.nofexp);
    Files.WriteLInt(CFI.ObjF, header.nofprv);
    Files.WriteLInt(CFI.ObjF, header.nofdesc);
    Files.WriteLInt(CFI.ObjF, header.nofcom);
    Files.WriteLInt(CFI.ObjF, header.nofptr);
    Files.WriteLInt(CFI.ObjF, header.nofhlp);
    Files.WriteLInt(CFI.ObjF, header.noffix);
    Files.Register(CFI.ObjFile);
    Files.Purge(CFI.RefFile);
  END RegisterRefObj;

  PROCEDURE SetObjModule*(mod : ARRAY OF CHAR); (* pre: LEN(mod) <= LEN(objmod) *)
  BEGIN COPY(mod, objmod);
  END SetObjModule;

  PROCEDURE SetObjName*(name : ARRAY OF CHAR); (* pre: LEN(name) <= LEN(objname) *)
  BEGIN COPY(name, objname);
  END SetObjName;

  (* ------------------ Symbol File ------------------ *)

  PROCEDURE SymWCh*(ch : CHAR);
  BEGIN Files.Write(CFI.SymF, ch);
  END SymWCh;

  PROCEDURE SymWInt*(i : LONGINT);
  BEGIN Files.WriteNum(CFI.SymF, i);
  END SymWInt;

  PROCEDURE SymWSet*(s : SET);
  BEGIN Files.WriteBytes(CFI.SymF, s, SIZE(SET));
  END SymWSet;

  PROCEDURE SymWReal*(f : REAL);
  BEGIN Files.WriteBytes(CFI.SymF, f, SIZE(REAL));
  END SymWReal;

  PROCEDURE SymWLReal*(d : LONGREAL);
  BEGIN Files.WriteBytes(CFI.SymF, d, SIZE(LONGREAL));
  END SymWLReal;

  PROCEDURE RegisterNewSym*;
  BEGIN Files.Register(CFI.SymFile); CFI.SymFile := NIL;
  END RegisterNewSym;

  PROCEDURE DeleteNewSym*;
  BEGIN Files.Purge(CFI.SymFile); CFI.SymFile := NIL;
  END DeleteNewSym;
  
  PROCEDURE DiscardNewSym*;
  BEGIN Files.Purge(CFI.SymFile); CFI.SymFile := NIL;
  END DiscardNewSym;

  PROCEDURE NewSym*(modName : ARRAY OF CHAR; SFext : ARRAY OF CHAR; SFtag, SFversion : CHAR; VAR noerr : BOOLEAN);
    VAR symName : FileDir.Filename;
  BEGIN ASSERT(CFI.SymFile = NIL, 200); (* cannot occur when a symfile is already open *)
    MakeFilename(modName, symName, SFext); CFI.SymFile := Files.New(symName);
    IF CFI.SymFile # NIL THEN Files.Set(CFI.SymF, CFI.SymFile, 0); SymWCh(SFtag); SymWCh(SFversion);
    ELSE err(EL.CannotOpenSymfile, noerr);
    END;
  END NewSym;

  PROCEDURE SymRCh*(VAR x : CHAR; VAR eofSF : BOOLEAN);
  BEGIN Files.Read(CFI.SymF, x); eofSF := CFI.SymF.eof;
  END SymRCh;

  PROCEDURE SymRInt*(VAR x : LONGINT; VAR eofSF : BOOLEAN);
  BEGIN Files.ReadNum(CFI.SymF, x); eofSF := CFI.SymF.eof;
  END SymRInt;

  PROCEDURE SymRSet*(VAR x : SET; VAR eofSF : BOOLEAN);
  BEGIN Files.ReadBytes(CFI.SymF, x, SIZE(SET)); eofSF := CFI.SymF.eof;
  END SymRSet;

  PROCEDURE SymRReal*(VAR x : REAL; VAR eofSF : BOOLEAN);
  BEGIN Files.ReadBytes(CFI.SymF, x, SIZE(REAL)); eofSF := CFI.SymF.eof;
  END SymRReal;

  PROCEDURE SymRLReal*(VAR x : LONGREAL; VAR eofSF : BOOLEAN);
  BEGIN Files.ReadBytes(CFI.SymF, x, SIZE(LONGREAL)); eofSF := CFI.SymF.eof;
  END SymRLReal;

  PROCEDURE OldSym*(modName : ARRAY OF CHAR; SFext : ARRAY OF CHAR; SFtag, SFversion : CHAR; VAR done : BOOLEAN);
    VAR tag, vers : CHAR; symName : FileDir.Filename; eof : BOOLEAN;
  BEGIN ASSERT(CFI.SymFile = NIL); (* cannot occur when a symfile is already open *)
    MakeFilename(modName, symName, SFext);
    done := FALSE; CFI.SymFile := Files.Old(symName);
    IF CFI.SymFile # NIL THEN Files.Set(CFI.SymF, CFI.SymFile, 0); SymRCh(tag, eof);
      SymRCh(vers, eof); done := ~eof & (tag = SFtag) & (vers = SFversion);
    END;
  END OldSym;

  PROCEDURE CloseOldSym*;
  BEGIN Files.Close(CFI.SymFile); CFI.SymFile := NIL;
  END CloseOldSym;

  PROCEDURE GetCurrentSourcePos*(VAR pos : LONGINT);
  BEGIN pos := CFI.curpos;
  END GetCurrentSourcePos;

  PROCEDURE InitSourceInfoOptions*(VAR info : SourceInfo);
  BEGIN info.options := DefaultOptions;
  END InitSourceInfoOptions;
  
  PROCEDURE InitSourceInfo(VAR info : SourceInfo);
  BEGIN
    info.pc := 0;
    info.beg := 0;
    info.source := NIL;
    info.name[0] := 0X;
    info.filename[0] := 0X;
  END InitSourceInfo;
  
  PROCEDURE InitializeOptions;
    PROCEDURE AddOption(h      : GetOpt.Handle;
                        value  : INTEGER; (* Option value when matched *)
                        flags  : SET;
                        short  : CHAR;
                        name   : ARRAY OF CHAR;
                        help   : ARRAY OF CHAR);
      VAR
        r : BOOLEAN;
    BEGIN
      r := GetOpt.AddOption(h, value, flags, short, name, help);
      ASSERT(r);
    END AddOption;

  BEGIN
    handle := GetOpt.Create();
    AddOption(handle,
              GetOpt.ValueMin + 0,
              { },
              'A',
              "no-assert",
              "Disable ASSERT code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 1,
              { },
              'a',
              "assert",
              "Enable ASSERT code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 2,
              { },
              'C',
              "no-nil-check",
              "Disable NIL check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 3,
              { },
              'c',
              "nil-check",
              "Enable NIL check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 4,
              { },
              'd',
              "dump-ast",
              "Dump AST to console.");

    AddOption(handle,
              GetOpt.ValueMin + 5,
              { },
              'E',
              "no-symbol-extend",
              "Disallow Symbol file extension.");

    AddOption(handle,
              GetOpt.ValueMin + 6,
              { },
              'e',
              "symbol-extend",
              "Allow Symbol file extension.");

    AddOption(handle,
              GetOpt.ValueMin + 7,
              { },
              0X,
              "hash-stats",
              "Dump hash table statistics to console.");

    AddOption(handle,
              GetOpt.ValueMin + 8,
              { },
              'I',
              "no-index-check",
              "Disable Index Check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 9,
              { },
              'i',
              "index-check",
              "Enable Index Check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 10,
              { },
              'N',
              "no-new-symbol",
              "Disable new Symbol file creation.");

    AddOption(handle,
              GetOpt.ValueMin + 11,
              { },
              'n',
              "new-symbol",
              "Enable new Symbol file creation.");

    AddOption(handle,
              GetOpt.ValueMin + 12,
              { },
              'O',
              "no-overflow-check",
              "Disable arithmetic overflow checking.");

    AddOption(handle,
              GetOpt.ValueMin + 13,
              { },
              'o',
              "overflow-check",
              "Enable arithmetic overflow checking.");

    AddOption(handle,
              GetOpt.ValueMin + 14,
              { },
              'P',
              "no-pointer-init",
              "Disable NIL pointer initialization code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 15,
              { },
              'p',
              "pointer-init",
              "Enable NIL pointer initialization code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 16,
              { },
              'R',
              "no-range-check",
              "Enable arithmetic range check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 17,
              { },
              'r',
              "range-check",
              "Enable arithmetic range check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 18,
              { },
              'T',
              "no-type-check",
              "Disable runtime type checking code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 19,
              { },
              't',
              "type-check",
              "Enable runtime type checking code generation.");
  END InitializeOptions;

  (* command line parsing
      Compiler command line syntax:
      
      Compiler.Compile [-{option}]... filename
      
      inv: Compiler.Compile <=> CommandLine.GetArg(1)
  *)
  PROCEDURE GetSourceInfo*(VAR FileInfo : SourceInfo; VAR noerr : BOOLEAN);
    VAR
      parm : CommandLine.Parameter;
      flag : INTEGER;
      arg  : GetOpt.ArgumentDesc;
      r    : GetOpt.Status;
  BEGIN
    noerr := TRUE;
    InitSourceInfo(FileInfo);

    REPEAT
      r := GetOpt.Parse(handle, arg);
      IF r = GetOpt.Success THEN
        CASE arg.value OF
        | GetOpt.ValueHelp:
          GetOpt.Help(handle);
          Kernel.Terminate(0);

        | GetOpt.ValueArgument:
          COPY(arg.argument^, FileInfo.filename);
          COPY(arg.argument^, FileInfo.name);
          Texts.New;
          FileInfo.source := Objects.NewObj(Texts.Text);
          Texts.Open(FileInfo.source, FileInfo.filename);
          RETURN;               (* Return to compile file. *)

        | GetOpt.ValueMin +  0: (* Disable assert. *)
          EXCL(FileInfo.options, Assert);

        | GetOpt.ValueMin +  1: (* Enable assert. *)
          INCL(FileInfo.options, Assert);

        | GetOpt.ValueMin +  2: (* Disable NIL check. *)
          EXCL(FileInfo.options, OptPtrChk);

        | GetOpt.ValueMin +  3: (* Enable NIL check. *)
          INCL(FileInfo.options, OptPtrChk);

        | GetOpt.ValueMin +  4: (* Dump AST. *)
          INCL(FileInfo.options, OptDumpNode);

        | GetOpt.ValueMin +  5: (* Disable symbol file extension. *)
          EXCL(FileInfo.options, ExtSF);

        | GetOpt.ValueMin +  6: (* Enable symbol file extension. *)
          INCL(FileInfo.options, ExtSF);

        | GetOpt.ValueMin +  7: (* Hash table stats. *)
          EXCL(FileInfo.options, OptHashStats);

        | GetOpt.ValueMin +  8: (* Disable index check. *)
          EXCL(FileInfo.options, InxChk);

        | GetOpt.ValueMin +  9: (* Enable index check. *)
          INCL(FileInfo.options, InxChk);

        | GetOpt.ValueMin + 10: (* Disable new symbol file. *)
          EXCL(FileInfo.options, NewSF);

        | GetOpt.ValueMin + 11: (* Enable new symbol file. *)
          INCL(FileInfo.options, NewSF);

        | GetOpt.ValueMin + 12: (* Disable overflow check. *)
          EXCL(FileInfo.options, OvflChk);

        | GetOpt.ValueMin + 13: (* Enable overflow check. *)
          INCL(FileInfo.options, OvflChk);

        | GetOpt.ValueMin + 14: (* Disable pointer initialization. *)
          EXCL(FileInfo.options, PtrInit);

        | GetOpt.ValueMin + 15: (* Enable pointer initialization. *)
          INCL(FileInfo.options, PtrInit);

        | GetOpt.ValueMin + 16: (* Disable arithmetic overflow check. *)
          EXCL(FileInfo.options, RanChk);

        | GetOpt.ValueMin + 17: (* Enable arithmetic overflow check. *)
          INCL(FileInfo.options, RanChk);

        | GetOpt.ValueMin + 18: (* Disable runtime type checking. *)
          EXCL(FileInfo.options, TypChk);

        | GetOpt.ValueMin + 19: (* Enable runtime type checking. *)
          INCL(FileInfo.options, TypChk);
        END;
      ELSE
        noerr := FALSE;
      END;
    UNTIL ~noerr OR (r = GetOpt.Done);
  END GetSourceInfo;

  (* initialization *)
  PROCEDURE ModuleBegin*(VAR FileInfo : SourceInfo);
  BEGIN CFI.FileInfo := FileInfo;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN CFI.SymFile := NIL; CFI.RefFile := NIL; CFI.ObjFile := NIL; CFI.FileInfo.source := NIL;
  END ModuleEnd;
  
BEGIN
  InitializeOptions;
  CurrentArg := 1;
END SKLCMDIO.
