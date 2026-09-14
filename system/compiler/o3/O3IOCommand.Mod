MODULE O3IOCommand; (* Command Line IO *)
  IMPORT
    SYSTEM,
    Kernel,
    Config:=O3Config,
    Objects,
    FileDir,
    Files,
    Texts,
    CommandLine,
    GetOpt,
    Console;

  CONST
    debug = FALSE;

  TYPE
    CurrentSourceInfo = RECORD
      FileInfo : Config.SourceInfo;
      lastpos : LONGINT;
      curpos : LONGINT;
    END;

  VAR
    objname, objmod : ARRAY Config.MaxIdLen OF CHAR;
    CFI : CurrentSourceInfo; (* CurrentFileInfo *)
    handle : GetOpt.Handle;
  (* ------------------------- Log Output ------------------------- *)

  PROCEDURE LogWSet(s : SET);
  BEGIN  Console.Set(s);
  END LogWSet;

  PROCEDURE LogW(ch : CHAR);
  BEGIN Console.Ch(ch);
  END LogW;

  PROCEDURE LogWStr(s : ARRAY OF CHAR);
  BEGIN Console.Str(s);
  END LogWStr;

  PROCEDURE LogWNum(x, digits : LONGINT);
  BEGIN Console.Int(x, digits);
  END LogWNum;

  PROCEDURE LogWHex(x : LONGINT);
  BEGIN Console.Hex(x);
  END LogWHex;

  PROCEDURE LogWLn;
  BEGIN Console.Ln;
  END LogWLn;

  PROCEDURE LogWBool(b : BOOLEAN);
  BEGIN Console.Bool(b);
  END LogWBool;

  PROCEDURE SetConsole*;
    VAR x : Config.ConsoleIO;
  BEGIN NEW(x); x.x := 7;
    x.bool := LogWBool;
    x.ch := LogW; x.str := LogWStr;
    x.int := LogWNum; x.hex := LogWHex; x.set := LogWSet;
    x.ln := LogWLn;
    Config.SetConsole(x);
  END SetConsole;

  PROCEDURE sourceinfoopen(VAR info : Config.SourceInfo);
  BEGIN
  END sourceinfoopen;

  PROCEDURE sourceinfoclose(VAR info : Config.SourceInfo);
  BEGIN
    info.beg := 0;
    info.source := NIL;
    info.name[0] := 0X;
    info.filename[0] := 0X;
  END sourceinfoclose;

  PROCEDURE sourceinfodefaultopts(VAR info : Config.SourceInfo);
  BEGIN
    info.options := Config.DefaultOptions;
  END sourceinfodefaultopts;

  PROCEDURE sourceinfoinit(VAR info : Config.SourceInfo);
  BEGIN
    info.beg := 0;
    info.source := NIL;
    info.name[0] := 0X;
    info.filename[0] := 0X;
  END sourceinfoinit;

  PROCEDURE sourceinfogetfile(VAR FileInfo : Config.SourceInfo;
                              VAR err : BOOLEAN);
    VAR
      arg : GetOpt.ArgumentDesc;
      r   : GetOpt.Status;
  BEGIN
    err := FALSE;
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
          EXCL(FileInfo.options, Config.OptAssert);

        | GetOpt.ValueMin +  1: (* Enable assert. *)
          INCL(FileInfo.options, Config.OptAssert);

        | GetOpt.ValueMin +  2: (* Code generation module. *)
          INCL(FileInfo.options, Config.OptTarget);
          COPY(arg.argument^, FileInfo.target);

        | GetOpt.ValueMin +  3: (* Disable symbol file extension. *)
          EXCL(FileInfo.options, Config.OptExtSF);

        | GetOpt.ValueMin +  4: (* Enable symbol file extension. *)
          INCL(FileInfo.options, Config.OptExtSF);

        | GetOpt.ValueMin +  5: (* Disable index check. *)
          EXCL(FileInfo.options, Config.OptChkIndex);

        | GetOpt.ValueMin +  6: (* Enable index check. *)
          INCL(FileInfo.options, Config.OptChkIndex);

        | GetOpt.ValueMin +  7: (* Disable new symbol file. *)
          EXCL(FileInfo.options, Config.OptNewSF);

        | GetOpt.ValueMin +  8: (* Enable new symbol file. *)
          INCL(FileInfo.options, Config.OptNewSF);

        | GetOpt.ValueMin +  9: (* Disable overflow check. *)
          EXCL(FileInfo.options, Config.OptChkOverflow);

        | GetOpt.ValueMin + 10: (* Enable overflow check. *)
          INCL(FileInfo.options, Config.OptChkOverflow);

        | GetOpt.ValueMin + 11: (* Disable pointer initialization. *)
          EXCL(FileInfo.options, Config.OptPointerInit);

        | GetOpt.ValueMin + 12: (* Enable pointer initialization. *)
          INCL(FileInfo.options, Config.OptPointerInit);

        | GetOpt.ValueMin + 13: (* Disable arithmetic overflow check. *)
          EXCL(FileInfo.options, Config.OptChkRange);

        | GetOpt.ValueMin + 14: (* Enable arithmetic overflow check. *)
          INCL(FileInfo.options, Config.OptChkRange);

        | GetOpt.ValueMin + 15: (* Disable runtime type checking. *)
          EXCL(FileInfo.options, Config.OptChkType);

        | GetOpt.ValueMin + 16: (* Enable runtime type checking. *)
          INCL(FileInfo.options, Config.OptChkType);

        | GetOpt.ValueMin + 17: (* Disable NIL check. *)
          EXCL(FileInfo.options, Config.OptNilChk);

        | GetOpt.ValueMin + 18: (* Enable NIL check. *)
          INCL(FileInfo.options, Config.OptNilChk);

        | GetOpt.ValueMin + 19: (* Enable DCE. *)
          INCL(FileInfo.options, Config.OptDCE);

        | GetOpt.ValueMin + 20: (* Disable DCE. *)
          EXCL(FileInfo.options, Config.OptDCE);

        | GetOpt.ValueMin + 21: (* Enable Copy Propagation. *)
          INCL(FileInfo.options, Config.OptCopyProp);

        | GetOpt.ValueMin + 22: (* Disable Copy Propagation. *)
          EXCL(FileInfo.options, Config.OptCopyProp);

        | GetOpt.ValueMin + 23: (* Enable Value Numbering. *)
          INCL(FileInfo.options, Config.OptValueNumber);

        | GetOpt.ValueMin + 24: (* Disable Value Numbering. *)
          EXCL(FileInfo.options, Config.OptValueNumber);

        | GetOpt.ValueMin + 25: (* Enable Constant Propagation. *)
          INCL(FileInfo.options, Config.OptConstProp);

        | GetOpt.ValueMin + 26: (* Disable Constant Propagation. *)
          EXCL(FileInfo.options, Config.OptConstProp);

        | GetOpt.ValueMin + 29: (* Enable Simple Scheduling. *)
          INCL(FileInfo.options, Config.OptSimpleSched);

        | GetOpt.ValueMin + 30: (* Disable Simple Scheduling. *)
          EXCL(FileInfo.options, Config.OptSimpleSched);
        ELSE
          err := TRUE;
        END;
      ELSE
        err := TRUE;
      END;
    UNTIL err OR (r = GetOpt.Done);
  END sourceinfogetfile;

  PROCEDURE SetCommandline;
    VAR x : Config.CompileArgument;
  BEGIN NEW(x); x.x := 0;
    INC(x.x); x.arg := sourceinfogetfile;
    INC(x.x); x.init := sourceinfoinit;
    INC(x.x); x.open := sourceinfoopen;
    INC(x.x); x.close := sourceinfoclose;
    INC(x.x); x.defaultopt := sourceinfodefaultopts;
    Config.SetCommandline(x);
  END SetCommandline;

  (* initialization *)
  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN CFI.FileInfo := FileInfo; RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    CFI.FileInfo.source := NIL;
    RETURN TRUE;
  END ModuleEnd;

  PROCEDURE InitializeGetOpt;
    PROCEDURE AddOption(h     : GetOpt.Handle;
                        value : INTEGER; (* Option value when matched. *)
                        flags : SET;
                        short : CHAR;
                        name  : ARRAY OF CHAR;
                        help  : ARRAY OF CHAR);

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
              "Disable ASSERT code generation");

    AddOption(handle,
              GetOpt.ValueMin + 1,
              { },
              'a',
              "assert",
              "Enable ASSERT code generation");

    AddOption(handle,
              GetOpt.ValueMin + 2,
              { GetOpt.ValueNeeded },
              'c',
              "target-machine",
              "Select code generation module.");

    AddOption(handle,
              GetOpt.ValueMin + 3,
              { },
              'E',
              "no-symbol-extend",
              "Disallow Symbol file extension.");

    AddOption(handle,
              GetOpt.ValueMin + 4,
              { },
              'e',
              "symbol-extend",
              "Allow Symbol file extension.");

    AddOption(handle,
              GetOpt.ValueMin + 5,
              { },
              'I',
              "no-index-check",
              "Disable array index check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 6,
              { },
              'i',
              "index-check",
              "Enable array index check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 7,
              { },
              'N',
              "no-new-symbol",
              "Disallow new Symbol file creation.");

    AddOption(handle,
              GetOpt.ValueMin + 8,
              { },
              'n',
              "new-symbol",
              "Allow new Symbol file creation.");

    AddOption(handle,
              GetOpt.ValueMin + 9,
              { },
              'O',
              "no-overflow-check",
              "Disable arithmetic overflow checking.");

    AddOption(handle,
              GetOpt.ValueMin + 10,
              { },
              'o',
              "overflow-check",
              "Enable arithmetic overflow checking.");

    AddOption(handle,
              GetOpt.ValueMin + 11,
              { },
              'P',
              "no-pointer-init",
              "Disable NIL pointer initialization code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 12,
              { },
              'p',
              "pointer-init",
              "Enable NIL pointer initialization code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 13,
              { },
              'R',
              "no-range-check",
              "Disable arithmetic range check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 14,
              { },
              'r',
              "range-check",
              "Enable arithmetic range check code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 15,
              { },
              'T',
              "no-type-check",
              "Disable runtime type checking code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 16,
              { },
              't',
              "type-check",
              "Enable runtime type checking code generation.");

    AddOption(handle,
              GetOpt.ValueMin + 17,
              { },
              'L',
              "no-nil-check",
              "Disable runtime type checking of NIL dereference.");

    AddOption(handle,
              GetOpt.ValueMin + 18,
              { },
              'l',
              "nil-check",
              "Enable runtime type checking of NIL dereference.");

    AddOption(handle,
              GetOpt.ValueMin + 19,
              { },
              0X,
              "opt-dce",
              "Enable GSA Dead Code Elimination.");

    AddOption(handle,
              GetOpt.ValueMin + 20,
              { },
              0X,
              "opt-no-dce",
              "Disable GSA Dead Code Elimination.");

    AddOption(handle,
              GetOpt.ValueMin + 21,
              { },
              0X,
              "opt-copy-prop",
              "Enable GSA Copy Propagation.");

    AddOption(handle,
              GetOpt.ValueMin + 22,
              { },
              0X,
              "opt-no-copy-prop",
              "Disable GSA Copy Propagation.");

    AddOption(handle,
              GetOpt.ValueMin + 23,
              { },
              0X,
              "opt-vn",
              "Enable GSA Value Numbering.");

    AddOption(handle,
              GetOpt.ValueMin + 24,
              { },
              0X,
              "opt-no-vn",
              "Disable GSA Value Numbering.");

    AddOption(handle,
              GetOpt.ValueMin + 25,
              { },
              0X,
              "opt-const-prop",
              "Enable GSA Constant Propagation.");

    AddOption(handle,
              GetOpt.ValueMin + 26,
              { },
              0X,
              "opt-no-const-prop",
              "Disable GSA Constant Propagation.");

    (* Index 27 is free *)
    (* Index 28 is free *)

    AddOption(handle,
              GetOpt.ValueMin + 29,
              { },
              0X,
              "opt-ss",
              "Enable GSA Simple Scheduler Phase.");

    AddOption(handle,
              GetOpt.ValueMin + 30,
              { },
              0X,
              "opt-no-ss",
              "Disable GSA Simple Scheduler Phase.");
  END InitializeGetOpt;

  PROCEDURE Initialize;
  BEGIN
    IF debug THEN
      Console.Str("loaded command line parser"); Console.Ln;
    END;
    Config.ControlModule(ModuleBegin, ModuleEnd);
    SetConsole;
    SetCommandline;
    InitializeGetOpt;
  END Initialize;

BEGIN Initialize;
END O3IOCommand.
