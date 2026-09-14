MODULE O3;

  IMPORT
    Config := O3Config,
    E      := O3Errors,
    Parser := O3Parser,
    AST    := O3TreeNode,
    IE     := O3SymFile,
    Symtab := O3Symtab,
    TA     := O3TypeAllocate,
    Modules,
    FileDir,
    Texts,
    Kernel;

  CONST
    SignOnMessage = "O3 (Oberon-3 compiler thutt 2022.09)";

  VAR
    source : Config.SourceInfo;
    TreeHandler : AST.TreeTraversalProc;
    CodeGenerator : Modules.Module;

  PROCEDURE UninstallCodeGenerator;
    VAR
      final : Modules.Command;
  BEGIN
    IF CodeGenerator # NIL THEN
      final := Modules.ThisCommand(CodeGenerator, "UninstallMachine");
      IF final # NIL THEN final;
      ELSE
        Config.LogWStr("Machine finalization for'");
        Config.LogWStr(CodeGenerator.name^);
        Config.LogWStr("' not found"); Config.LogWLn;
        Config.Fatal(E.MachineFinalNotFound);
      END;
      AST.SetTreeTraversalProc(NIL);
      CodeGenerator := NIL;
    END;
  END UninstallCodeGenerator;

  PROCEDURE Module*(FileInfo : Config.SourceInfo; VAR error: BOOLEAN);
    VAR
      ext, new: BOOLEAN;
      err : BOOLEAN;
      ch : CHAR;
      mod : AST.Node;

    PROCEDURE ModuleOpen;
    BEGIN
      Symtab.OpenScopeModule(0, NIL);
      Symtab.GlbMod[0] := Symtab.topScope(Symtab.SymbolModuleScope);
      Symtab.nofGmod := 1;
    END ModuleOpen;

    PROCEDURE ModuleClose;
      VAR
        scope : Symtab.SymbolScope;
    BEGIN
      scope := Symtab.CloseScope();
    END ModuleClose;

    PROCEDURE AllocateTypes(VAR mod : AST.Node);
      VAR
        inittd : AST.InitTD;
        node : AST.Node;
    BEGIN
      TA.AllocateScope(Symtab.topScope, inittd);
      ASSERT((mod.class = AST.Nstmt) & (mod.subcl = AST.Senter), 1024);
      ASSERT(AST.main IN mod(AST.Enter).flags, 1025);
      ASSERT(mod(AST.Enter).inittd = NIL, 1026);
      mod(AST.Enter).inittd := inittd;
    END AllocateTypes;

  BEGIN
    Config.DoControlProc(Config.modulebegin, FileInfo);
    Config.EnableOptions(FileInfo.options);
    Config.OpenSource(FileInfo.filename, 0, err);
    IF ~err THEN
      ModuleOpen;
      Parser.Module(mod); (* syntactically parse & create AST *)
      Config.CloseSource;
      IF ~Config.err THEN
        AllocateTypes(mod);
        err := ~AST.Module(mod); (* generate code *)
        IF ~err THEN
          IE.Export(mod(AST.Enter).info.name^, new, ext); (* generate symbol file *)
        END;
        ModuleClose;
      END;
      UninstallCodeGenerator;
    END;
    Config.DoControlProc(Config.moduleend, FileInfo);
    error := Config.err
  END Module;

  PROCEDURE Compile*;
    VAR 
      err : BOOLEAN;

    PROCEDURE Do(VAR FileInfo : Config.SourceInfo);
      VAR
        S1: Texts.Scanner;
    BEGIN
      Config.LogWStr(FileInfo.filename);
      Config.LogWStr(" compiling (for ");
      Config.LogWStr(FileInfo.target);
      Config.LogWStr(') ');

      IF FileInfo.source # NIL THEN
        (*
          open the given input source and check if the first token is 'MODULE'; if
          so, output the second token as the name of the module being compiled.
          This is used when a single text file contains many small Oberon programs
          and the compiler is given an 'offset' in the file as the place where
          compilation should begin.
        *)
        Texts.OpenScanner(S1, FileInfo.source, FileInfo.beg);
        Texts.Scan(S1);
        IF (S1.class = Texts.Name) & (S1.s = "MODULE") THEN
          Texts.Scan(S1);
          IF S1.class = Texts.Name THEN
            Config.LogWStr(S1.s)
          END;
        END ;

        Module(FileInfo, err);
      END ;

      IF ~Config.err THEN
        Config.LogWStr('  (mem ');
        Config.LogWNum(Kernel.heap.allocated DIV 1024, 3);
        Config.LogW('K');
      END;

      Kernel.GC;
      IF ~Config.err THEN
        Config.LogWStr("/");
        Config.LogWNum(Kernel.heap.allocated DIV 1024, 3);
        Config.LogWStr("K)");
      END;
      Config.LogWLn;
    END Do;

    PROCEDURE LoadTargetMachine(options : Config.SourceInfo);
      VAR
        mname : FileDir.Filename;
        i : INTEGER;
        ch : CHAR;
        init : Modules.Command;
    BEGIN
      COPY("O3M", mname);
      i := 0;
      REPEAT
        ch := options.target[i];
        mname[3 + i] := ch;
        INC(i);
      UNTIL ch = 0X;
      CodeGenerator := Modules.ThisMod(mname);
      IF CodeGenerator # NIL THEN
        init := Modules.ThisCommand(CodeGenerator, "InstallMachine");
        IF init # NIL THEN
          init;
        ELSE
          Config.LogWStr("Machine initialization for'");
          Config.LogWStr(mname);
          Config.LogWStr("' not found");
          Config.LogWLn;
          Config.Fatal(E.MachineInitNotFound);
        END;
      ELSE
        Config.LogWStr("Machine configuration for '");
        Config.LogWStr(options.target);
        Config.LogWStr(" ["); Config.LogWStr(mname);
        Config.LogWStr("]");
        Config.LogWStr("' not found");
        Config.LogWLn;
        Config.Fatal(E.TargetMachineNotFound);
      END;
    END LoadTargetMachine;

  BEGIN
    Config.Initialize;
    Config.SourceInfoDefaultOpts(source);
    Config.SourceInfoOpen(source);
    LOOP
      Config.SourceInfoInit(source);
      Config.SourceInfoGetFile(source, err);
      Config.EnableOptions(source.options);

      IF Config.OptTarget IN Config.options THEN
        LoadTargetMachine(source);
        IF ~err & ~Config.err THEN
          Do(source);
        END;
      ELSE
        Config.Fatal(E.NoTargetMachine);
      END;
      IF err OR Config.err THEN
        EXIT;
      END;
    END;
    Config.SourceInfoClose(source);
    Config.Finalize;
  END Compile;

  PROCEDURE Init;
    VAR
      mod : Modules.Module;
  BEGIN
    (* stand-alone command line or Oberon System command line *)
    mod := Modules.ThisMod("O3IOCommand");
    IF mod = NIL THEN
      HALT(999);
    END; (* the host-OS subsystem could not be loaded *)

    (* standard file I/O subsystem *)
    mod := Modules.ThisMod("O3FileIO");
    IF mod = NIL THEN
      HALT(1000);
    END; (* file I/O subsystem could not be loaded *)
    Config.LogWStr(SignOnMessage);
    Config.LogWLn;
  END Init;

BEGIN Init;
END O3.
