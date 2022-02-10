MODULE SKL;

  IMPORT FileDir, Texts,
    ST := SKLST,
    SP := SKLSP,
    OPS:=SKLOS,
    TT := SKLTT,
    T := SKLT,
    CGL := SKLCGL,
    CGH := SKLCGH,
    OPM := SKLMD,
    TU:=SKLTU,
    IE:=SKLIE,
    DN:=SKLDN,
    TH:=SKLTH,
    Kernel;
  
  CONST
    SignOnMessage = "LMSO SKL Compiler  TWH 2020.11.16";

  VAR
    source : OPM.SourceInfo;

  PROCEDURE Module*(FileInfo : OPM.SourceInfo; VAR error: BOOLEAN);
    VAR ext, new: BOOLEAN; mod: T.Node; inittd : T.InitTD; err : BOOLEAN;
  BEGIN
    OPM.ModuleBegin(FileInfo);
    OPS.ModuleBegin;
    ST.ModuleBegin;
    SP.ModuleBegin;
    T.ModuleBegin(TH.SameDesignSet);
    TH.ModuleBegin; (* SKLTH must follow SKLT *)
    IE.ModuleBegin;
    SP.Module(mod);
    OPM.CloseSource(FileInfo);
    IF OPM.noerr THEN
      CGL.ModuleBegin;
      CGH.ModuleBegin;
      TT.ModuleBegin; (* before allocation *)
      
      OPM.NewRefObj(mod(T.Enter).info.name^);
      ASSERT((mod.class = T.Nstmt) & (mod.subcl = T.Senter));
      ASSERT(ST.topScope # NIL);
      TU.Allocate(ST.topScope, inittd);
      IE.Export(mod(T.Enter).info.name^, new, ext);
      IF OPM.noerr THEN
        IF OPM.OptDumpNode IN FileInfo.options THEN
          DN.Dump(mod);
        END;

        TT.Module(mod, inittd, err);
        
        IF ~err THEN
          CGL.OutCode(mod(T.Enter).info.name^);
          IF new THEN OPM.LogWStr(" new symbol file")
          ELSIF ext THEN OPM.LogWStr(" extended symbol file")
          END ;
          OPM.LogWNum(CGL.pc, 8); OPM.LogWStr(' bytes code '); 
          OPM.LogWNum(-ST.topScope(ST.SymbolScope).dsize, 8); OPM.LogWStr(' bytes data');
        ELSE OPM.DeleteNewSym; OPM.DeleteRefObj;
        END;
      END;

      TT.ModuleEnd;
      CGH.ModuleEnd;
      CGL.ModuleEnd;
    END;
    IE.ModuleEnd;
    TH.ModuleEnd;
    T.ModuleEnd;
    SP.ModuleEnd;
    ST.ModuleEnd;
    OPS.ModuleEnd;
    OPM.ModuleEnd;
    error := ~OPM.noerr
  END Module;

  PROCEDURE Compile*;
    VAR err : BOOLEAN;

    PROCEDURE Do(VAR FileInfo : OPM.SourceInfo);
      VAR S1: Texts.Scanner;
    BEGIN
      OPM.LogWStr(FileInfo.filename); OPM.LogWStr(" compiling  ");
      IF FileInfo.source # NIL THEN
        Texts.OpenScanner(S1, FileInfo.source, FileInfo.beg); Texts.Scan(S1);

        IF (S1.class = Texts.Name) & (S1.s = "MODULE") THEN Texts.Scan(S1);
          IF S1.class = Texts.Name THEN OPM.LogWStr(S1.s) END
        END ;
        Module(FileInfo, err);
      END ;
      IF OPM.noerr THEN
        OPM.LogWStr('  (mem ');
        OPM.LogWNum(Kernel.heap.allocated DIV 1024, 3);
        OPM.LogW('K');
      END;
      Kernel.GC;
      IF OPM.noerr THEN
        OPM.LogWStr("/");
        OPM.LogWNum(Kernel.heap.allocated DIV 1024, 3);
        OPM.LogWStr("K)");
      END;
      OPM.LogWLn;
    END Do;

    PROCEDURE OnOff(b : BOOLEAN);
    BEGIN
      OPM.LogWStr(' (');
      IF b THEN
        OPM.LogWStr('on');
      ELSE
        OPM.LogWStr('off');
      END;
      OPM.LogW(')');
    END OnOff;
    
    PROCEDURE Banner;
    BEGIN
      OPM.LogWStr('A: assertion evaluation'); OnOff(OPM.Assert IN source.options); OPM.LogWLn;
      OPM.LogWStr('C: NIL pointer check'); OnOff(OPM.OptPtrChk IN source.options); OPM.LogWLn;
      OPM.LogWStr('D: dump nodes'); OnOff(OPM.OptDumpNode IN source.options); OPM.LogWLn;
      OPM.LogWStr('E: symbol file extension'); OnOff(OPM.ExtSF IN source.options); OPM.LogWLn;
      OPM.LogWStr('H: hash table stats'); OnOff(OPM.OptHashStats IN source.options); OPM.LogWLn;
      OPM.LogWStr('I: index checking'); OnOff(OPM.InxChk IN source.options); OPM.LogWLn;
      OPM.LogWStr('N: new symbol file'); OnOff(OPM.NewSF IN source.options); OPM.LogWLn;
      OPM.LogWStr('O: overflow check'); OnOff(OPM.OvflChk IN source.options); OPM.LogWLn;
      OPM.LogWStr('P: pointer initialization'); OnOff(OPM.PtrInit IN source.options); OPM.LogWLn;
      OPM.LogWStr('R: range checking'); OnOff(OPM.RanChk IN source.options); OPM.LogWLn;
      OPM.LogWStr('T: type checking'); OnOff(OPM.TypChk IN source.options); OPM.LogWLn;
      OPM.LogWStr('?: print this banner'); OPM.LogWLn;
    END Banner;

  BEGIN
    OPM.InitSourceInfoOptions(source);
    LOOP
      OPM.GetSourceInfo(source); (* post: noerr <=> success or not *)
      IF OPM.OptBanner IN source.options THEN
        Banner;
        EXIT;
      END;
      IF OPM.noerr THEN
        Do(source);
      END;
      IF err OR ~OPM.noerr THEN
        EXIT;
      END;
    END;
  END Compile;

BEGIN
  OPM.LogWStr(SignOnMessage);
  OPM.LogWLn;
END SKL.
