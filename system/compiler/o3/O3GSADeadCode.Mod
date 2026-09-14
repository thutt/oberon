(* Dead Code Elimination
 *
 * Dead Code elimination is nothing more than a mark & sweep
 * garbage collection on the code region.
 *)
MODULE O3GSADeadCode; (* GSA Dead Code Elimination *)
  IMPORT
    Config := O3Config,
    GSAName := O3GSANames,
    GSAOpcode := O3GSAOpcode,
    GSAData := O3GSAData;

  CONST
    dfProgress = 0;
    dfDumpRegion = 1;
    diagnostics = { };
    live = MAX(SET); (* instruction is live and cannot be removed *)

  VAR
    deleted : LONGINT;

  PROCEDURE progress(s : ARRAY OF CHAR);
  BEGIN
    IF dfProgress IN diagnostics THEN
      Config.LogWStr(s);
      Config.LogWLn;
    END;
  END progress;


  PROCEDURE output(instr : GSAData.Instruction);
  BEGIN
    Config.LogWNum(instr.dfo, 3);
    Config.LogW(' ');
    GSAName.WDecode(instr);
    Config.LogWStr(' live: ');
    Config.LogWBool({live, GSAData.raLive} * instr.attrib # { });
    Config.LogWLn;
  END output;


  PROCEDURE dumpregion(r : GSAData.Region);
    VAR
      instr : GSAData.Instruction;
      op : GSAData.Operand;
      rgn : GSAData.Region;
  BEGIN
    IF dfDumpRegion IN diagnostics THEN
      instr := r.instructions.finst;
      WHILE instr # r.instructions DO
        ASSERT(instr.region # NIL, 1025);
        output(instr);
        instr := instr.finst;
      END;

      rgn := r.regions.freg;
      WHILE rgn # r.regions DO
        dumpregion(rgn);
        rgn := rgn.freg;
      END;
    END;
  END dumpregion;


  (* MarkLive: mark an instruction as live
   *
   * pre: results = TRUE  -> mark uses of instruction results live
   * pre: results = FALSE -> do not mark uses of instruction results live
   *
   * The results of the $enter instruction should not be marked as live.
   * As an explanation, consider why using an operand or local variable
   * would force another instruction to be live?
   *)
  PROCEDURE MarkLive(enter, i : GSAData.Instruction);
    VAR
      o : GSAData.Operand;
      res : GSAData.Result;
   BEGIN
     IF ~(live IN i.attrib) THEN
       INCL(i.attrib, live);
       IF i.region # NIL THEN
         MarkLive(enter, i.region);
       END;

      o := i.operands.fop;
      WHILE o # i.operands DO
        IF o.def IS GSAData.Result THEN
          (* Mark instruction which produced operand as 'live' *)
          MarkLive(enter, o.def(GSAData.Result).owner);
        ELSIF (o.def IS GSAData.Addressable) THEN
          IF (o.def(GSAData.Addressable).currvalue # NIL)
             & (o.def(GSAData.Addressable).currvalue IS GSAData.Result) THEN
            (* NOP: The operand is an addressable whose value was
             * produced by an instruction; no need to mark an addressable
             * as live. *)
          END;
        END;
        o := o.fop;
      END;

      IF i # enter THEN
        res := i.results.bres;
        ASSERT(i # GSAData.InstructionEnter(i.region), 1024);
        WHILE res # i.results.fres DO
          o := res.uses.fuses;
          WHILE o # res.uses DO
            MarkLive(enter, o.owner);
            o := o.fuses;
          END;
          res := res.bres;
        END;
      END;
    END;
  END MarkLive;


  (* Set all 'raLive' instructions as live *)
  PROCEDURE MarkForceAlive(r : GSAData.Region);
  VAR
    instr, enter : GSAData.Instruction;
    op : GSAData.Operand;
    rgn : GSAData.Region;
  BEGIN
    instr := r.instructions.finst;
    enter := GSAData.InstructionEnter(r);
    WHILE instr # r.instructions DO
      ASSERT(instr.region # NIL, 1025);
      IF GSAData.raLive IN instr.attrib THEN
        MarkLive(enter, instr);
      END;
      instr := instr.finst;
    END;

    rgn := r.regions.freg;
    WHILE rgn # r.regions DO
      MarkForceAlive(rgn);
      rgn := rgn.freg;
    END;
  END MarkForceAlive;


  PROCEDURE DeleteDeadCode(i : GSAData.Instruction);
    VAR
      ni, j : GSAData.Instruction;
      r, rgn, nr : GSAData.Region;
  BEGIN
    IF ~(live IN i.attrib) THEN
      GSAData.InstructionDelete(i);
      INC(deleted);
    ELSIF i IS GSAData.Region THEN
      r := i(GSAData.Region);
      j := r.instructions.finst;
      WHILE j # r.instructions DO
        ni := j.finst;
        DeleteDeadCode(j);
        j := ni;
      END;
      rgn := r.regions.freg;
      WHILE rgn # r.regions DO
        nr := rgn.freg;
        DeleteDeadCode(rgn);
        rgn := nr;
      END;
    END;
  END DeleteDeadCode;


  PROCEDURE MarkOperandsDead(instr : GSAData.Instruction);
    VAR
      op : GSAData.Operand;
  BEGIN
    (* Mark all operands which are GSAData.Result as dead
     * (although, they should also be instructions in the
     * region and marked through that facility.
     *)
    op := instr.operands.fop;
    WHILE (op # instr.operands) DO
      IF (op.def IS GSAData.Result) THEN
        EXCL(op.def(GSAData.Result).attrib, live);
      END;
      op := op.fop;
    END;
  END MarkOperandsDead;


  (* Mark all instructions after a trap as unreachable.
   *
   *  Because a trap, when executed, will terminate the program,
   *  all instructions following a trap in a region will be unreachable
   *  and can be removed.
   *)
  PROCEDURE MarkDeadAfterTrap(region : GSAData.Region);
    VAR
      instr : GSAData.Instruction;
      rgn : GSAData.Region;
  BEGIN
    instr := region.instructions.finst;
    WHILE (instr # region.instructions) & (instr.class # GSAOpcode.Ttrap) DO
      instr := instr.finst;
    END;

    IF instr # region.instructions THEN
      instr := instr.finst; (* Instruction after Ttrap. *)
      WHILE instr # region.instructions DO
        IF ~(instr IS GSAData.Region) THEN
          EXCL(instr.attrib, live);
        END;
        MarkOperandsDead(instr);
        instr := instr.finst;
      END;
    END;

    rgn := region.regions.freg;
    WHILE rgn # region.regions DO
      MarkDeadAfterTrap(rgn);
      rgn := rgn.freg;
    END;
  END MarkDeadAfterTrap;


  (* Mark all intructions as dead prior to the mark phase. *)
  PROCEDURE MarkDead(region: GSAData.Region);
    VAR
      instr : GSAData.Instruction;
      op : GSAData.Operand;
      rgn : GSAData.Region;
  BEGIN
    EXCL(region.attrib, live);
    instr := region.instructions.finst;
    WHILE instr # region.instructions DO
      ASSERT(instr.region # NIL, 1025);
      IF ~(instr IS GSAData.Region) THEN
        EXCL(instr.attrib, live);
      END;

      MarkOperandsDead(instr);
      instr := instr.finst;
    END;

    rgn := region.regions.freg;
    WHILE rgn # region.regions DO
      MarkDead(rgn);
      rgn := rgn.freg;
    END;
  END MarkDead;


  (* Perform: Dead Code Elimination *)
  (* pre : r # NIL *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR
      enter : GSAData.Instruction;
  BEGIN
    progress("Dead Code Elimination");
    enter := GSAData.InstructionEnter(r);
    REPEAT
      deleted := 0;
      progress("mark-dead");
      MarkDead(r);

      progress("mark-force");
      MarkForceAlive(r);

      progress("mark $enter");
      MarkLive(enter, enter);

      progress("mark $exit");
      MarkLive(enter, GSAData.InstructionExit(r));

      progress("mark dead after Trap");
      MarkDeadAfterTrap(r);

      progress("delete dead");
      DeleteDeadCode(r);
      dumpregion(r);
   UNTIL deleted = 0;
  END Perform;


  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN
  END NILGlobalPointers;


  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    NILGlobalPointers;
    RETURN TRUE;
  END ModuleBegin;


  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    NILGlobalPointers;
    RETURN TRUE;
  END ModuleEnd;


  PROCEDURE Init;
  BEGIN
    Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;

BEGIN
  Init;
END O3GSADeadCode.
