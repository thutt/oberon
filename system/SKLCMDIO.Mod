MODULE SKLCMDIO; (* Command Line IO *)
IMPORT
  SYSTEM, 
  Objects, 
  EL:=SKLERR, 
  FileDir, 
  Files, 
  Texts, 
  CommandLine, 
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
      argno- : INTEGER; (* argument number: 2 <= argno <= MAX(INTEGER) *)
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
  BEGIN info.pc := 0; info.beg := 0; info.source := NIL; info.name[0] := 0X; info.filename[0] := 0X;
  END InitSourceInfo;
  
  (* command line parsing
      Compiler command line syntax:
      
      Compiler.Compile [-{option}]... filename
      
      inv: Compiler.Compile <=> CommandLine.GetArg(1)
  *)
  PROCEDURE GetSourceInfo*(VAR FileInfo : SourceInfo; VAR noerr : BOOLEAN);
    VAR parm : CommandLine.Parameter; flag : INTEGER;
  BEGIN noerr := TRUE; InitSourceInfo(FileInfo); INC(CurrentArg);
    IF CurrentArg < CommandLine.ParameterCount THEN
      parm := CommandLine.GetArg(CurrentArg);
      FileInfo.argno := CurrentArg;

      (* gather options for the filename that follows *)
      WHILE noerr & (parm[0] = CommandLine.OptionChar) DO
        IF parm[1] = '?' THEN
          flag := OptBanner;
        ELSE
          CASE CAP(parm[1]) OF
          |  'A': flag := Assert; (* assertion evaluation *)
          |  'C': flag := OptPtrChk; (* NIL pointer check *)
          |  'D': flag := OptDumpNode; (* turn on node dumper *)
          |  'E': flag := ExtSF; (* symbol file extension *)
          |  'H':  flag := OptHashStats; (* hash table statistics *)
          |  'I':  flag := InxChk; (* index check *)
          |  'N': flag := NewSF; (* new symbol file *)
          |  'O': flag := OvflChk; (* overflow check *)
          |  'P': flag := PtrInit; (* pointer initialization *)
          |  'R': flag := RanChk; (* range checking *)
          |  'T': flag := TypChk; (* type checking *)
          ELSE
            noerr := FALSE;
          END;
        END;
        IF noerr THEN
          FileInfo.options := FileInfo.options / {flag};
          INC(CurrentArg);
          FileInfo.argno := CurrentArg;
          IF CurrentArg < CommandLine.ParameterCount THEN
            parm := CommandLine.GetArg(CurrentArg);
          ELSE
            noerr := FALSE;
          END;
        END;
      END;

      IF noerr THEN (* inv: parm is set to a non-option parameter; presumably the filename *)
          COPY(parm^, FileInfo.filename);
          COPY(parm^, FileInfo.name);
          Texts.New; FileInfo.source := Objects.NewObj(Texts.Text);
          Texts.Open(FileInfo.source, FileInfo.filename);
      END;
    ELSE
      noerr := FALSE;
    END;
  END GetSourceInfo;

  (* initialization *)
  PROCEDURE ModuleBegin*(VAR FileInfo : SourceInfo);
  BEGIN CFI.FileInfo := FileInfo;
  END ModuleBegin;

  PROCEDURE ModuleEnd*;
  BEGIN CFI.SymFile := NIL; CFI.RefFile := NIL; CFI.ObjFile := NIL; CFI.FileInfo.source := NIL;
  END ModuleEnd;
  
BEGIN CurrentArg := 1;
END SKLCMDIO.
