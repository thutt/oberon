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
    CullTrapInstructions = FALSE;

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


  PROCEDURE output(instr  : GSAData.Instruction;
                   prefix : ARRAY OF CHAR);
    VAR
      alive : BOOLEAN;
  BEGIN
    alive := live IN instr.attrib;
    Config.LogWNum(instr.dfo, 3);
    Config.LogW(' ');
    IF alive THEN
      Config.LogWStr(' live: T ');
    ELSE
      Config.LogWStr(' live: F ');
    END;
    Config.LogWStr(prefix);
    Config.LogW(' ');
    GSAName.WDecode(instr);
    Config.LogWStr("  attrib: ");
    Config.LogWSet(instr.attrib);
    Config.LogWLn;
  END output;


  PROCEDURE dumphelper(r      : GSAData.Region;
                        label  : ARRAY OF CHAR;
                        prefix : ARRAY OF CHAR);
    VAR
      instr : GSAData.Instruction;
      op    : GSAData.Operand;
      rgn   : GSAData.Region;
      irgn  : GSAData.Region; (* Instruction's region. *)
  BEGIN
    IF dfDumpRegion IN diagnostics THEN
      IF label[0] # 0X THEN
        Config.LogWStr(label); Config.LogWLn;
      END;
      instr := r.instructions.finst;
      WHILE instr # r.instructions DO
        ASSERT(instr.region # NIL, 1025);
        output(instr, prefix);
        IF instr IS GSAData.Region THEN
          (* It is more efficient to process the instructions,
           * each of which can be a Region, in two phases than
           * recursively, like here.   The recursive solution
           * requires another function call.
           *
           * To process the regions in a parent Region, after
           * the instructions are processed:
           *
           *    rgn := r.regions.freg;
           *    WHILE rgn # r.regions DO
           *       ...
           *    END;
           *)
          rgn := instr(GSAData.Region);
          dumphelper(rgn, "", " ");
        END;
        instr := instr.finst;
      END;
    END;
  END dumphelper;

  PROCEDURE dumpregion(r : GSAData.Region;
                       label : ARRAY OF CHAR);
  BEGIN dumphelper(r, label, "");
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

    PROCEDURE MarkOperandsLive(i : GSAData.Instruction);
      VAR
        o : GSAData.Operand;
    BEGIN
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
    END MarkOperandsLive;

    PROCEDURE MarkResultsLive(i : GSAData.Instruction);
      VAR
        res : GSAData.Result;
        o   : GSAData.Operand;
    BEGIN
      res := i.results.bres;
      ASSERT(i # GSAData.InstructionEnter(i.region), 1024);

      (* No need to process i.result.fres, because it's 'i'. *)
      ASSERT(i = i.results.fres, 1025);
      WHILE res # i.results.fres DO
        o := res.uses.fuses;
        WHILE o # res.uses DO
          MarkLive(enter, o.owner);
          o := o.fuses;
        END;
        res := res.bres;
      END;
    END MarkResultsLive;

   BEGIN
     IF ~(live IN i.attrib) THEN
       INCL(i.attrib, live);
       IF i.region # NIL THEN
         (* Region owner is live => everything in the Region is live. *)
         MarkLive(enter, i.region);
       END;

       MarkOperandsLive(i);

       IF i # enter THEN
         (* The Result values of $enter are not live automatically. *)
         MarkResultsLive(i);
       END;
     END;
  END MarkLive;


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
    (* Mark all operands which are GSAData.Result as dead. *)
    op := instr.operands.fop;
    WHILE (op # instr.operands) DO
      (* Mark all GSAData.Result operands that are not required as dead. *)
      IF (op.def IS GSAData.Result) THEN
        EXCL(op.def(GSAData.Result).attrib, live);
      END;
      op := op.fop;
    END;
  END MarkOperandsDead;


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

  (* TrapCull
   *
   *  A $trap instruction that is executed effectively marks all instructions
   *  following it in the same region as dead code.
   *
   *  This procedure uses the $trapsink instruction to process each $trap
   *  instruction in the region.  Every instruction that a trap dominates is
   *  implicitly unexecutable, and can be marked as dead.
   *
   *  If an operand's definition is not marked live, it has already been
   *  marked dead, and will be removed on the next removal phase.
   *  The operand is deleted.
   *
   *
   *)

  PROCEDURE TrapCull(exit : GSAData.Region);
    VAR
      trapsink  : GSAData.Instruction;
      instr     : GSAData.Instruction;
      trap      : GSAData.Instruction;
      oper      : GSAData.Operand;
      dominates : BOOLEAN;
      exitUses  : BOOLEAN;

    (* Returns TRUE iff any uses of 'instr' are in the $exit region. *)
    PROCEDURE ExitUses(exit     : GSAData.Region;
                       trapsink : GSAData.Instruction;
                       instr    : GSAData.Instruction) : BOOLEAN;
      VAR
        use : GSAData.Operand;
    BEGIN
      use := instr.uses.fuses;
      WHILE use # instr.uses DO
        IF (use.owner.region = exit) & (use.owner # trapsink) THEN
          RETURN TRUE;
        END;
        use := use.fuses;
      END;
      RETURN FALSE;
    END ExitUses;

  BEGIN
    GSAData.RegionNumber(exit.region); (* GSAData.Dominates() prerequisite. *)
    instr := exit.instructions.finst;
    WHILE (trapsink = NIL) & (instr # exit.instructions) DO
      IF (instr.class = GSAOpcode.Pmisc) &
         (instr.subcl = GSAOpcode.Ptrapsink) THEN
        trapsink := instr;
      END;
      instr := instr.finst;
    END;
    (* inv: trapsink = NIL OR (trapsink is a { Pmisc, Ptrapsink }). *)
    IF trapsink # NIL THEN
      (* Initially, all operand's definitions will be marked 'live'.
       * After the first trap is processed, any subsequent operand's
       * definition can have 'live' removed.  If the definition is
       * not live, delete the operand and continue.
       *)
      oper := trapsink.operands.fop;
      WHILE oper # trapsink.operands DO
        trap := oper.def(GSAData.Instruction);
        ASSERT((trap.class = GSAOpcode.Ttrap) &
               (trap.subcl IN { GSAOpcode.Tindex, GSAOpcode.Trange,
                                GSAOpcode.Teguard, GSAOpcode.Tiguard,
                                GSAOpcode.Treturn, GSAOpcode.Tcase,
                                GSAOpcode.Tassert, GSAOpcode.Thalt,
                                GSAOpcode.Twith, GSAOpcode.Tnil}), 1024);
        IF ~(live IN trap.attrib) THEN
          (* Skip this operand.
           *
           * Delete the operand because the instruction that defines the
           * operand is already marked dead.
           *)
          oper := oper.fop;
          GSAData.OperandDelete(oper.bop);
        ELSE
          (* Mark all instructions, to the end of the Region,
           * dominated by this $trap as dead.
           *
           * If the $trap is in the global region, $exit can be encountered;
           * never process $exit.
           *
           * If the Instruction to be marked dead is in the $exit region,
           * do not mark it dead, because $exit is special.
           *)
          instr := trap.finst;
          WHILE (instr # exit) & (instr # trap.region.instructions) DO
            dominates := GSAData.Dominates(trap, instr);
            exitUses  := ExitUses(exit, trapsink, instr);
            IF dominates & ~exitUses THEN
              EXCL(instr.attrib, live);
              IF instr IS GSAData.Region THEN
                MarkDead(instr(GSAData.Region));
              END;
            END;
            instr := instr.finst;
          END;
          oper := oper.fop;
        END;
      END;

      (* If $trapsink has no operands, all the $trap instructions have been
       * removed. That should not be possible, because the $trap instructions
       * are specifically marked live as part of $exit processing.
       *
       * At least one $trap is assumed to be reachable.
       *)
      ASSERT(trapsink.operands.fop # trapsink.operands, 1025);
    END;
  END TrapCull;


  PROCEDURE ProcessExit(enter : GSAData.Region;
                        exit  : GSAData.Region);
  BEGIN
    MarkLive(enter, exit);
    IF CullTrapInstructions THEN
      (* Culling all instructions dominated by a $trap instruction
       * seems like a pretty simple thing.  However many special cases abound.
       * For example, instructions that are used by $dtor-nlm can also be
       * removed, but their uses will not be automatically removed.
       * This leaves operands refering to instructions that have been removed.
       *
       * Could GSAData.InstructionDelete automatically remove all uses?
       * Would that even be a correct thing to do?
       *
       * So, for now, this complicated subject is disabled.
       *)
      TrapCull(exit);
    END;
  END ProcessExit;


  (* Perform: Dead Code Elimination *)
  (* pre : r # NIL *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR
      enter : GSAData.Region;
      iter  : INTEGER;
  BEGIN
    iter := 0;
    progress("Dead Code Elimination");
    enter := GSAData.InstructionEnter(r);
    REPEAT
      IF dfProgress IN diagnostics THEN
        Config.LogWStr("***** Iteration "); Config.LogWNum(iter, 3); Config.LogWLn;
        INC(iter);
      END;
      deleted := 0;

      progress("MarkDead");
      MarkDead(r);
      dumpregion(r, "MarkDead");

      progress("MarkLive $enter");
      MarkLive(enter, enter);
      dumpregion(r, "MarkLive $enter");

      progress("Process $exit");
      ProcessExit(enter, GSAData.InstructionExit(r));
      dumpregion(r, "Process $exit");

      progress("Delete Dead Code");
      DeleteDeadCode(r);
      dumpregion(r, "DeleteDeadCode");
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
