(* Simple Instruction Scheduler

   This instruction scheduler simply outputs instructions when they
   are deemed to be ready.  'Ready' means that all the operands of the
   instruction have been emitted.

   The 'generic' field is used for instruction scheduling.

   Instruction
     inv: generic.a >= 0
     inv: generic.a = 0 -> all operands have been scheduled
     inv: generic.a > 0 -> 'generic' operands remain to be scheduled

   Region
     inv: Invariants of Instruction apply
     inv: generic.b >= 0
     inv: generic.b = 0 -> all instructions in region have been scheduled
     inv: generic.b > 0 -> 'generic' instructions remain to be scheduled

   inv: the first instruction in a global region will always be $enter
   inv: the last instruction in a global region will always be $exit
*)

MODULE O3GSASimpleSchedule;
IMPORT
  Config := O3Config,
  E := O3Errors,
  Symtab := O3Symtab,
  GSANames := O3GSANames,
  GSAOpcode := O3GSAOpcode,
  GSAData := O3GSAData,
  GSADump := O3GSADump;

CONST
  dfProgress = 0;
  dfDumpWorklist = 1;
  diagnostics = {};

TYPE
  (* Worklist/WorklistDesc:
   *
   * head: instruction after which a newly scheduled instruction should be inserted
   *)
  Worklist = POINTER TO WorklistDesc;
  WorklistDesc = RECORD (GSAData.InstructionDesc)
    head : GSAData.Instruction;
  END;

  PROCEDURE output(i : GSAData.Instruction);
  BEGIN
    Config.LogWNum(i.dfo, 3); 
    Config.LogWStr(' [');
    IF i IS GSAData.Merge THEN
      Config.LogWNum(i.generic.a, 1); Config.LogW('/');
      Config.LogWNum(i.generic.b, 1);
    ELSIF i IS GSAData.Region THEN
      Config.LogWNum(i.generic.a, 1); Config.LogW('/');
      Config.LogWNum(i.generic.b, 1);
    ELSE
      Config.LogWNum(i.generic.a, 1); Config.LogW('/');
      Config.LogWNum(i.generic.b, 1);
    END;
    Config.LogWStr('] '); GSANames.WDecode(i); Config.LogWLn;
  END output;

  PROCEDURE dumpworklist(worklist : Worklist);
    PROCEDURE dump(w : Worklist);
      VAR i : GSAData.Instruction; l : INTEGER;
    BEGIN i := w.inlink;
      WHILE i # w DO
        output(i);
        IF i IS GSAData.Region THEN 
          IF i.info # NIL THEN
            ASSERT(i.info # NIL, 1023);
            dump(i.info(Worklist));
          END;
        END;
        i := i.inlink;
      END;
    END dump;

  BEGIN
    Config.LogWStr('instruction scheduling worklist'); Config.LogWLn;
    dump(worklist);
  END dumpworklist;

  PROCEDURE append(worklist : GSAData.Instruction; i : GSAData.Instruction);
  BEGIN
    i.inlink := worklist; i.iplink := worklist.iplink;
    worklist.iplink.inlink := i; worklist.iplink := i;
  END append;

  PROCEDURE remove(instr : GSAData.Instruction);
  BEGIN
    instr.iplink.inlink := instr.inlink;
    instr.inlink.iplink := instr.iplink;
    instr.iplink := NIL; instr.inlink := NIL;
  END remove;

  (* InitializeRegion: initialize count of operands which are not ready
   *)
  PROCEDURE InitializeWorklist(r : GSAData.Region);
  VAR
    worklist : Worklist;
    instr : GSAData.Instruction; 
    op : GSAData.Operand; rgn : GSAData.Region;
    nofOperands, nofInstructions : INTEGER; 

  BEGIN NEW(worklist); worklist.head := r.instructions;
    worklist.inlink := worklist; worklist.iplink := worklist;
    r.info := worklist; nofInstructions := 0; instr := r.instructions.finst;
    WHILE instr # r.instructions DO ASSERT(instr.region # NIL, 1025);
      append(worklist, instr); INC(nofInstructions);
      op := instr.operands.fop; nofOperands := 0;
      WHILE (op # instr.operands) DO
        IF (op.def IS GSAData.Result) THEN INC(nofOperands); END;
        op := op.fop;
      END;
      instr.generic.a := nofOperands; instr := instr.finst;
    END;
    r.generic.b := nofInstructions; rgn := r.regions.freg;
    WHILE rgn # r.regions DO InitializeWorklist(rgn); rgn := rgn.freg; END;
  END InitializeWorklist;

  PROCEDURE UpdateReady(instr : GSAData.Instruction);
    VAR res : GSAData.Result; use : GSAData.Operand;
  BEGIN res := instr.results.fres; (* instructions themselves are the first result *)
    WHILE res # instr.results DO
      use := res.uses.fuses;
      WHILE use # res.uses DO ASSERT(use.owner.generic.a > 0);
        DEC(use.owner.generic.a); 
        use := use.fuses;
      END;
      res := res.fres;
    END;
  END UpdateReady;

  PROCEDURE EmitInstruction(worklist : Worklist; instr : GSAData.Instruction);
  BEGIN
    IF dfProgress IN diagnostics THEN Config.LogWStr("emit "); output(instr); END;
    remove(instr); UpdateReady(instr);
    GSAData.InstructionReposition(worklist.head, instr);
    worklist.head := instr;
  END EmitInstruction;

  PROCEDURE Schedule(r : GSAData.Region) : INTEGER;
    VAR instr : GSAData.Instruction; worklist : Worklist;
        n, nofInstructions : INTEGER; op : GSAData.Operand;

  BEGIN ASSERT(r.info # NIL);
    worklist := r.info(Worklist); instr := worklist.inlink;
    nofInstructions := 0;
    WHILE instr # worklist DO
      IF instr IS GSAData.Region THEN
        n := Schedule(instr(GSAData.Region));
        DEC(instr.generic.b, LONG(n)); ASSERT(instr.generic.b >= 0, 1200);
        IF (instr.generic.a = 0) & (instr.generic.b = 0) THEN
          EmitInstruction(worklist, instr); instr := worklist.inlink;
          nofInstructions := 1;
        ELSE instr := instr.inlink; nofInstructions := 0;
        END;
      ELSIF instr.generic.a = 0 THEN INC(nofInstructions);
        EmitInstruction(r.info(Worklist), instr); instr := worklist.inlink;
      ELSE instr := instr.inlink;
      END;
    END;
    RETURN nofInstructions;
  END Schedule;

  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR nofInstructions : INTEGER;
  BEGIN
    GSAData.RegionClearInfo(r);
    GSAData.RegionClearLinks(r);
    IF dfProgress IN diagnostics THEN
      Config.LogWStr("Simple Instruction Scheduler"); Config.LogWLn;
    END;
    InitializeWorklist(r);
    IF dfDumpWorklist IN diagnostics THEN
      dumpworklist(r.info(Worklist));
    END;
    nofInstructions := Schedule(r);
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
END O3GSASimpleSchedule.
