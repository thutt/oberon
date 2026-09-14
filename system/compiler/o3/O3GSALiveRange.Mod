(* Copyright (c) 2023 Logic Magicians Software *)
MODULE O3GSALiveRange;
IMPORT
  Config   := O3Config,
  GSAData  := O3GSAData,
  GSANames := O3GSANames;

CONST
  SetDivisor = MAX(SET) + 1;

TYPE
  VirtualRegister = POINTER TO ARRAY OF SET;
  Instructions = POINTER TO ARRAY OF VirtualRegister;
  (* InstRegMap:
   *
   *   Maps virtual registers to instructions (and then) to instructions
   *   where they are live.
   *)
  InstRegMap = RECORD
    nVreg : INTEGER;
    map   : POINTER TO ARRAY OF VirtualRegister;
  END;

  LiveRanges = RECORD
    nInst  : INTEGER; (* Number of instructions. *)
    ireg   : InstRegMap;
    rreg   : InstRegMap;

    (* XXX remove below this. *)
    nVreg  : INTEGER; (* Number of virtual registers. *)
    ranges : Instructions;
  END;
  

(*
(* Need configuration constants for number of registers? *)

CONST (* Graph Kinds *)
  integer* = 0;                 (* Integer registers. *)
  real*    = 1;                 (* Floating point registers. *)

TYPE
  RegisterSet* = POINTER TO ARRAY OF SET;
  Graph* = POINTER TO GraphDesc;
  GraphDesc = RECORD
    graph : POINTER TO ARRAY OF RegisterSet;
  END;

PROCEDURE Dump*(g : Graph; label : ARRAY OF CHAR);
  VAR
    i, j: INTEGER;
BEGIN
  Config.LogWStr(label);
  Config.LogWLn;

  i := 0;
  WHILE i < S.usedcolors DO
    j := 0;
    WHILE j < S.usedcolors DO
      IF Interfere(S, i, j) THEN
        Out.Char("*")
      ELSE
        Out.Char("-")
      END;
      Out.Char(" "); INC(j)
    END;
    Config.LogWLn;
    INC(i);
  END;
  Out.Ln
END Dump;


PROCEDURE Interfere(S: RegionSummary; x, y: INTEGER): BOOLEAN;
BEGIN
  IF (x # noColor) & (y # noColor) & (x # y) THEN
    RETURN (InRegisterSet(S.interfere[y], x)) OR (InRegisterSet(S.interfere[x], y))
  ELSE
    RETURN FALSE
  END;
END Interfere;
*)

PROCEDURE decode(inst : GSAData.Instruction);
BEGIN
  Config.LogWNum(inst.reg, 3);
  Config.LogWStr(".");
  Config.LogWNum(inst.ref, 3);
  Config.LogWStr(": ");
  GSANames.WDecode(inst);
  Config.LogWLn;
END decode;

PROCEDURE Set(VAR map : InstRegMap;
              inst    : INTEGER;
              vreg    : INTEGER;
              value   : BOOLEAN);
  VAR
    bit   : LONGINT;
    index : LONGINT;
BEGIN
  IF map.map[inst] = NIL THEN
    (* First time a register is live for this instruction. *)
    NEW(map.map[inst], (map.nVreg + MAX(SET) + 1) DIV SetDivisor);
  END;
  bit   := vreg MOD SetDivisor;
  index := vreg DIV SetDivisor;
  IF value THEN
    INCL(map.map[inst][index], bit);
  ELSE
    EXCL(map.map[inst][index], bit);
  END;
END Set;


PROCEDURE Get(VAR vector : InstRegMap;
              inst       : INTEGER;
              vreg       : INTEGER) : BOOLEAN;
  VAR
    bit   : LONGINT;
    index : LONGINT;
BEGIN
  IF vector.map[inst] = NIL THEN
    RETURN FALSE;
  ELSE
    bit   := vreg MOD SetDivisor;
    index := vreg DIV SetDivisor;
    RETURN bit IN vector.map[inst][index];
  END;
END Get;

PROCEDURE DumpRanges(vector : LiveRanges);

  PROCEDURE dump(map   : InstRegMap;
                 nInst : INTEGER;
                 label : ARRAY OF CHAR);
  VAR
    inst, vreg : INTEGER;
  BEGIN
    Config.LogWStr(label);
    Config.LogWStr(" Registers: [inst: ");
    Config.LogWNum(nInst, 3);
    Config.LogWStr("  vreg:  ");
    Config.LogWNum(map.nVreg, 3);
    Config.LogWStr("]");
    Config.LogWLn;

    inst := 0;
    WHILE inst < nInst DO
      Config.LogWNum(inst, 3);
      Config.LogWStr(":  ");
      vreg := 0;
      WHILE vreg < map.nVreg DO
        IF Get(map, inst, vreg) THEN
          Config.LogWStr("+ ");
        ELSE
          Config.LogWStr("- ");
        END;
        INC(vreg);
        IF vreg MOD 5 = 0 THEN
          Config.LogWStr(" ");
        END;
      END;
      INC(inst);
      Config.LogWLn;
    END;
  END dump;

BEGIN
  dump(vector.ireg, vector.nInst, "Integer");
  dump(vector.rreg, vector.nInst, "Real");
END DumpRanges;

PROCEDURE SetLiveRange(vector : LiveRanges;
                       ibeg   : INTEGER;
                       iend   : INTEGER;
                       vreg   : GSAData.VirtualReg;
                       value  : BOOLEAN);
  VAR
    beg : INTEGER;
    end : INTEGER;
    i   : INTEGER;

  PROCEDURE set(map   : InstRegMap;
                ibeg  : INTEGER;
                iend  : INTEGER;
                vreg  : INTEGER;
                value : BOOLEAN);
  BEGIN
    IF FALSE THEN
      Config.LogWStr("SetLiveRange: inst [");
      Config.LogWNum(beg, 3);
      Config.LogWStr("  ");
      Config.LogWNum(end, 3);
      Config.LogWStr("]  vreg: ");
      Config.LogWNum(vreg, 3);
      Config.LogWStr("  val: ");
      Config.LogWBool(value);
      Config.LogWLn;
    END;
    ASSERT(end >= 0);
    i := beg;
    WHILE i >= end DO
      Set(map, i, vreg, value);
      DEC(i);
    END;
  END set;

BEGIN
  ASSERT((ibeg >= 0) & (iend >= 0), 1024);
  IF ibeg >= iend THEN
    beg := ibeg;
    end := iend;
  ELSE
    end := ibeg;
    beg := iend;
  END;
  IF vreg.rkind = GSAData.VRegInteger THEN
    set(vector.ireg, beg, end, vreg.ireg, value);
  ELSE
    ASSERT(vreg.rkind = GSAData.VRegReal);
    set(vector.rreg, beg, end, vreg.rreg, value);
  END;
END SetLiveRange;

PROCEDURE ProcessRegion(r : GSAData.Region; vector : LiveRanges);
  VAR
    inst : GSAData.Instruction;
    res  : GSAData.Result;
    oper : GSAData.Operand;
    i    : INTEGER;
    beg  : INTEGER;
    end  : INTEGER;
BEGIN
  inst := r.instructions.binst;
  WHILE inst # r.instructions DO
    decode(inst);
    i := 0;
    oper := inst.operands.fop;
    WHILE oper # inst.operands DO
      ASSERT((oper.def.dfo >= 0) OR (oper.def IS GSAData.Addressable), 1024);

      (* If the dfo of the operand's definition is negative, it's an
         Addressable; it does not have an instruction.  Since the live
         range cannot be computed based on where the operand was
         defined, the live range will be marked as just this
         instruction. *)
      beg := inst.dfo;
      IF oper.def.dfo >= 0 THEN
        beg := oper.def.dfo;
      END;
      SetLiveRange(vector, beg, inst.dfo, oper.def.vreg, TRUE);
      oper := oper.fop;
      INC(i);
    END;


    IF inst IS GSAData.Region THEN
      ProcessRegion(inst(GSAData.Region), vector);
    END;
    inst := inst.binst;
  END;
END ProcessRegion;


PROCEDURE CreateLiveRange(VAR v : LiveRanges;
                          nInst : INTEGER;
                          vreg  : GSAData.VirtualReg);
BEGIN
  v.nInst := nInst;
  v.ireg.nVreg := vreg.ireg;
  NEW(v.ireg.map, nInst);

  v.rreg.nVreg := vreg.rreg;
  NEW(v.rreg.map, nInst);
END CreateLiveRange;


PROCEDURE Perform*(r : GSAData.Region);
  VAR
    vector  : LiveRanges;
    nofInst : INTEGER;
    vreg    : GSAData.VirtualReg;
BEGIN
  GSAData.AssignRegisters(r, nofInst, vreg);

  Config.LogWLn;
  Config.LogWStr("Live Range: inst: ");
  Config.LogWNum(nofInst, 3);
  Config.LogWStr("  vregs: int: ");
  Config.LogWNum(vreg.ireg, 3);
  Config.LogWStr("  real: ");
  Config.LogWNum(vreg.rreg, 3);
  Config.LogWLn;
  CreateLiveRange(vector, nofInst, vreg);

  ProcessRegion(r, vector);
  DumpRanges(vector);

  Config.LogWStr('-------'); Config.LogWLn;
END Perform;

END O3GSALiveRange.
