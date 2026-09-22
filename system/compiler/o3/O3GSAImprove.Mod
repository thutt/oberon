(* Copyright (c) 1999-2026 Logic Magicians Software *)
MODULE O3GSAImprove; (* Code Improvement *)
  IMPORT
    Config       := O3Config,
    Symtab       := O3Symtab,
    GSAVN        := O3GSAValueNumber,
    GSADCE       := O3GSADeadCode,
    GSACP        := O3GSACopyPropagate,
    GSACPUC      := O3GSAConstPropagate,
    GSAAA        := O3GSAAliasAnalysis,
    GSASS        := O3GSASimpleSchedule,
    GSADump      := O3GSADump,
    GSAData      := O3GSAData,
    GSALiveRange := O3GSALiveRange,
    GSAOpcode    := O3GSAOpcode;

  CONST
    dfProgress = 1;
    diagnostics = {};

  PROCEDURE dump(module : ARRAY OF CHAR;
                 r : GSAData.GlobalRegion;
                 ext : ARRAY OF CHAR;
                 header : ARRAY OF CHAR);
  BEGIN
    GSAData.RegionNumber(r);
    GSADump.OpenFile(module, r.proc.name^, ext, header);
    GSADump.Region(r);
    GSADump.CloseFile;
  END dump;

  (* inv: r is a dummy circular list header *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR rgn : GSAData.Region; module : Symtab.SymbolName;
  BEGIN
    rgn := r.freg;
    module := rgn(GSAData.GlobalRegion).proc.name;
    WHILE rgn # r DO
      WITH rgn:GSAData.GlobalRegion DO
        IF dfProgress IN diagnostics THEN
          Config.LogWStr("Improving ");
          Config.LogWStr(rgn(GSAData.GlobalRegion).proc.name^);
          Config.LogWLn;
        END;
        dump(module^, rgn, ".gsa.00000", "Initial GSA");

        IF Config.OptAliasAnalysis IN Config.options THEN
          GSAData.RegionNumber(rgn);
          dump(module^, rgn, ".gsa.00100", "Alias Analysis");
          GSAAA.Perform(rgn);
          dump(module^, rgn, ".gsa.00199", "Alias Analysis");
        END;

        IF Config.OptCopyProp IN Config.options THEN
          dump(module^, rgn, ".gsa.00200", "Copy Propagation");
          GSACP.Perform(rgn);
          dump(module^, rgn, ".gsa.00299", "Copy Propagation");
        END;

        IF Config.OptValueNumber IN Config.options THEN
          dump(module^, rgn, ".gsa.00300", "Value Numbering");
          GSAVN.Perform(rgn);
          dump(module^, rgn, ".gsa.00399", "Value Numbering");
        END;

        IF Config.OptDCE IN Config.options THEN
          dump(module^, rgn, ".gsa.00400", "Dead Code Elimination");
          GSADCE.Perform(rgn);
          dump(module^, rgn, ".gsa.00499", "Dead Code Elimination");
        END;

        IF Config.OptConstProp IN Config.options THEN
          dump(module^, rgn, ".gsa.00500", "Const Prop & Unreachable Code");
          GSACPUC.Perform(rgn);
          dump(module^, rgn, ".gsa.00599", "Const Prop & Unreachable Code");
        END;

        IF Config.OptDCE IN Config.options THEN
          dump(module^, rgn, ".gsa.00600", "Dead Code Elimination");
          GSADCE.Perform(rgn);
          dump(module^, rgn, ".gsa.00699", "Dead Code Elimination");
        END;

        IF Config.OptSimpleSched IN Config.options THEN
          dump(module^, rgn, ".gsa.00700", "Simple Scheduler");
          GSASS.Perform(rgn);
          dump(module^, rgn, ".gsa.00799", "Simple Scheduler");
        END;

        IF Config.OptLiveRange IN Config.options THEN
          dump(module^, rgn, ".gsa.00800", "Live Range Analysis");
          GSALiveRange.Perform(rgn);
          dump(module^, rgn, ".gsa.00899", "Live Range Analysis");
        END;

        dump(module^, rgn, ".gsa.99999", "Final GSA");
      END;
      rgn := rgn.freg;
    END;
  END Perform;

  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN
  END NILGlobalPointers;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;

  PROCEDURE Init;
  BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;

BEGIN Init;
END O3GSAImprove.
