(* Value Numbering System

Value Numbering is a process which finds instructions in a program
which compute the same value, the result being that the duplicated
instructions can be removed from the code stream; it is a good
technique for eliminating common-subexpressions (CSE).

This implementation of an optimistic value numbering assumes, until
proven different, that all instruction which might be congruent are
actually congruent.  To accomplish this, the algorithm repetitively
partitions the data into groups which are assumed to be congruent.

The instructions are paritioned by grouping the same opcodes (i.e.,
$add, $mult, $deref) into the same set, and then further partitioning
each opcode set by the operands.

Upon termination of the algorithm, there are a number of sets of
instruction, and all members of each set have the same opcode, the
same results, the same number of operands and each enumerated operand
is identical.

Instructions which do not have the same opcode (in which case, they
would not be in the same partition) or which have corresponding
operands appearing in different partitions are not congruent.

At the end of the algorithm, all instructions appearing in the same
partition are congruent; instructions which do not appear in the same
partition are not congruent.
*)
MODULE O3GSAValueNumber;
  IMPORT
    Config:=O3Config,
    GSANames := O3GSANames,
    GSAOpcode := O3GSAOpcode,
    GSADCE := O3GSADeadCode,
    GSACAN := O3GSACanon,
    GSAData := O3GSAData;

  CONST (* diagnostic flags *)
    dfBanner = 0;
    dfDumpClasses = 1;
    dfSplitByUses = 2;
    dfSplitByClass = 3;
    dfSplitByWorklist = 4;
    dfSplitByResult = 5;
    dfSplitByConst = 6;
    diagnostics = {};

  CONST
    StackSize = 512;
    UndefinedInst = -1;
    nofOpcodeClasses = 0 + GSAOpcode.OpcodeClassEnd - GSAOpcode.OpcodeClassBegin;
    ArithmeticSubclasses = ((1 + GSAOpcode.asST - GSAOpcode.asST) +
                            (1 + GSAOpcode.asR4 - GSAOpcode.asR8) +
                            (1 + GSAOpcode.asU4 - GSAOpcode.asS1));

  TYPE
    Class = POINTER TO ClassDesc;
    ClassDesc = RECORD (GSAData.InfoDesc)
      next : Class;
      nlink, plink : Class; (* next & previous links for worklist handling *)
      instr : GSAData.Instruction; (* linked by inlink, iplink *)
      split : Class;
      replacement : GSAData.Instruction;
      nofuses : LONGINT;
      number : INTEGER;
    END;

    ClassArray = POINTER TO ARRAY OF Class;

  VAR
    opclass : POINTER TO ARRAY nofOpcodeClasses OF ClassArray;
    worklist : Class;
    classes : Class;
    stamp : INTEGER; (* class/partition number *)

  VAR (* stack of partition *)
    sp: INTEGER;
    stack: POINTER TO ARRAY StackSize OF Class;

  PROCEDURE Push(class: Class);
  BEGIN
    stack[sp] := class;
    INC(sp);
  END Push;

  PROCEDURE DumpClasses(r : GSAData.Region);
    VAR
      class: Class;
      instr: GSAData.Instruction;

  BEGIN
    Config.LogWLn;
    Config.LogWStr("DumpClasses");
    Config.LogWLn;
    Config.LogWLn;
    class := classes;
    WHILE class # NIL DO
      instr := class.instr;
      Config.LogWStr("class #");
      Config.LogWNum(class.number, 0);
      IF instr # NIL THEN
        Config.LogWStr(" uses ");
        Config.LogWNum(class.nofuses, 0);
        Config.LogWLn;
        REPEAT
          Config.LogW("(");
          Config.LogWNum(instr.dfo, 0);
          Config.LogWStr(") ");
          instr := instr.inlink(GSAData.Instruction)
        UNTIL instr = class.instr;
      ELSE
        Config.LogWStr(" empty");
      END;
      Config.LogWLn;
      class := class.next
    END;
    Config.LogWLn
  END DumpClasses;

  (* HashArithmeticSubcl: Transform the subclass of an arithmetic node to a unique
                          partition number.
  *)
  PROCEDURE HashArithmeticSubcl(i : INTEGER) : INTEGER;
  BEGIN
    CASE i OF
    | GSAOpcode.asS1..GSAOpcode.asU4: (* nop *)

    | GSAOpcode.asR8, GSAOpcode.asR4:
      i := 1 + GSAOpcode.asU4 + (i - GSAOpcode.asR8);

    | GSAOpcode.asST:
      i := 1 + GSAOpcode.asU4
           + (1 + GSAOpcode.asR4 - GSAOpcode.asR8)
           + (i - GSAOpcode.asST);
    END;

    (* ensure hash has not violated bounds of the arithmetic arrays *)
    ASSERT((i >= 0) & (i < LEN(opclass[GSAOpcode.Aabs]^)));
    RETURN i;
  END HashArithmeticSubcl;

  (* InstructionsNumberOf: returns number of instructions in a class *)
  PROCEDURE InstructionsNumberOf(c : Class) : INTEGER;
    VAR
      i : GSAData.Instruction;
      num : INTEGER;
  BEGIN
    i := c.instr;
    num := 0;
    REPEAT
      i := i.inlink;
      INC(num);
    UNTIL i = c.instr;
    RETURN num;
  END InstructionsNumberOf;

  PROCEDURE ResultsMaxNumberOf(c : Class) : INTEGER;
    VAR
      max, num : INTEGER;
      i : GSAData.Instruction;
  BEGIN
    max := 0;
    i := c.instr;
    REPEAT
      num := GSAData.ResultsNumberOf(i);
      IF num > max THEN
        max := num;
      END;
      i := i.inlink;
    UNTIL i = c.instr;
    RETURN max;
  END ResultsMaxNumberOf;

  (* Add an instruction to a class *)
  PROCEDURE AppendToClass(c : Class; i : GSAData.Instruction);
    VAR
      head: GSAData.Instruction;
  BEGIN
    IF c.instr = NIL THEN
      c.instr := i;
      i.inlink := i;
      i.iplink := i;
    ELSE
      (* append `i' to the end of the doubly-linked circular list
       * using `i.inlink' and `i.iplink'
       *)
      head := c.instr;
      i.inlink := head;
      i.iplink := head.iplink;
      head.iplink.inlink := i;
      head.iplink := i;
    END;
    i.info := c;
    INC(c.nofuses, i.generic.a);
  END AppendToClass;

  (* Add a class to the worklist *)
  PROCEDURE AppendToWorklist(c : Class);
  BEGIN
    c.plink := worklist;
    c.nlink := worklist;
    worklist.plink.nlink := c;
    worklist.plink := c;
  END AppendToWorklist;

  PROCEDURE NewClass() : Class;
    VAR
      c : Class;
  BEGIN
    NEW(c);
    c.next := classes;
    classes := c;
    c.number := stamp;
    INC(stamp);
    AppendToWorklist(c);
    c.ref := UndefinedInst;
    c.reg := UndefinedInst;
    RETURN c;
  END NewClass;

  (* BuildParitions: produce a first-cut `separation set' of Instructions
   *                 based on their opcode class and subclass.
   * pre: r # NIL
   *
   * Traverses over all instructions & regions within the region `r',
   * splitting them into paritions based on their instruction class &
   * subclass.
   *)
  PROCEDURE BuildParitions(r : GSAData.Region);
    VAR
      i     : GSAData.Instruction;
      rgn   : GSAData.Region;
      subcl : INTEGER;
      class : Class;
  BEGIN
    i := r.instructions.finst;
    WHILE i # r.instructions DO
      (* loops not in the same region are never part of the same class *)
      (* classify this instruction *)
      CASE i.class OF
      | GSAOpcode.Mbegin..GSAOpcode.Mend - 1,
        GSAOpcode.Tbegin..GSAOpcode.Tend - 1,
        GSAOpcode.Gbegin..GSAOpcode.Gend - 1,
        GSAOpcode.Pbegin..GSAOpcode.Pend - 1:
        subcl := i.subcl;

      | GSAOpcode.Abegin..GSAOpcode.Aend - 1,
        GSAOpcode.Lbegin..GSAOpcode.Lend - 1,
        GSAOpcode.Hbegin..GSAOpcode.Hend - 1,
        GSAOpcode.Cbegin..GSAOpcode.Cend - 1,
        GSAOpcode.Sbegin..GSAOpcode.Send - 1:
        subcl := HashArithmeticSubcl(i.subcl);
      END;
      ASSERT((i.class >= 0) & (i.class < LEN(opclass^)), 1024);
      ASSERT((subcl >= 0) & (subcl < LEN(opclass[i.class]^)), 1025);

      IF opclass[i.class][subcl] = NIL THEN
        class := NewClass();
        opclass[i.class][subcl] := class;
      END;
      AppendToClass(opclass[i.class][subcl], i);
      i := i.finst;
    END;

    rgn := r.regions.freg;
    WHILE rgn # r.regions DO
      BuildParitions(rgn);
      rgn := rgn.freg;
    END;
  END BuildParitions;

  (* CountUses: Determine number of uses of each instruction in the region
   *            which was just paritiioned
   *)
  PROCEDURE CountUses;
    VAR
      i, j, count: LONGINT;
      c: Class;
      instr : GSAData.Instruction;

    PROCEDURE CountInstrUses(i: GSAData.Instruction);
      VAR
        count: LONGINT;
        opnd: GSAData.Operand;
        res: GSAData.Result;
    BEGIN
      count := 0;
      (* for all results of this instruction
       *   for all uses of the result
       *      tally uses of the instruction
       *)
      res := i.results.bres;
      WHILE res # i.results DO
        opnd := res.uses.fuses;
        WHILE opnd # res.uses DO
          INC(count);
          opnd := opnd.fuses;
        END;
        res := res.bres;
      END;
      i.generic.a := count;
    END CountInstrUses;

  BEGIN
    i := 0;
    WHILE i < LEN(opclass^) DO
      j := 0;
      WHILE j < LEN(opclass[i]^) DO
        c := opclass[i][j];
        IF c # NIL THEN
          instr := c.instr;
          count := 0;
          REPEAT
            CountInstrUses(instr);
            count := count + instr.generic.a;
            instr := instr.inlink;
          UNTIL instr = c.instr;
          c.nofuses := count;
        END;
        INC(j);
      END;
      INC(i);
    END;
  END CountUses;

  (* Remove an instruction form a class *)
  PROCEDURE RemoveFromClass (instr: GSAData.Instruction);
    VAR
      c: Class;
  BEGIN
    c := instr.info(Class);
    IF c.instr = instr THEN
      c.instr := instr.inlink;
      IF c.instr = instr THEN
        c.instr := NIL
      END;
    END;
    instr.inlink.iplink := instr.iplink;
    instr.iplink.inlink := instr.inlink;
    instr.iplink := NIL;
    instr.inlink := NIL;
    instr.info := NIL;
    DEC(c.nofuses, instr.generic.a);
  END RemoveFromClass;

  (* Set new classes to worklist *)
  PROCEDURE CommitClasses;
    VAR
      class, split: Class;
      instr: GSAData.Instruction;
  BEGIN
    WHILE sp > 0 DO
      DEC(sp);
      split := stack[sp];
      class := split.split;
      class.split := NIL;
      split.split := NIL;
      IF class.instr = NIL THEN
        (* no more instructions in this `class'; just put the instructions
         * back into the original class. *)
        class.instr := split.instr;
        class.nofuses := split.nofuses;
        split.instr := NIL;
        split.nofuses := 0;
        instr := class.instr;
        REPEAT
          instr.info := class;
          instr := instr.inlink;
        UNTIL instr = class.instr;
      ELSE
        IF class.nlink # NIL THEN
          AppendToWorklist(split);
        ELSIF class.nofuses < split.nofuses THEN
          AppendToWorklist(class);
        ELSE
          AppendToWorklist(split);
        END;
      END;
    END;
  END CommitClasses;

  (* Split classes by uses of an object, constant, or result - pos = operand position
   *
   * pre : head # NIL
   * pre : head <-> dummy head of uses list
   * pre : pos >= 0
   * pre : pos <-> operand position
   * post: max <-> maximal operand position at which this `head' was found
   *
   * This function receives the dummy head of a uses list
   * and it traverses the list in turn looking for places where
   * the `use' is in the operand position denoted by `pos'.
   * When finished, all instructions having `head' as the `pos'-th
   * operand will be partitioned into their own class.
   *)
  PROCEDURE SplitByUses(head: GSAData.Operand; pos: INTEGER; VAR max: INTEGER);
    VAR
      use: GSAData.Operand;
      instr: GSAData.Instruction;
      class, split: Class;
  BEGIN (* inv: head <-> dummy list head *)
    use := head.fuses;
    WHILE use # head DO
      IF use.opnum = pos THEN
        instr := use.owner;
        class := instr.info(Class);
        IF dfSplitByUses IN diagnostics THEN
          Config.LogWStr('SplitByUse: op=');
          Config.LogWNum(pos, 0);
          Config.LogWStr(' use=');
          GSANames.WDecode(use);
          Config.LogWStr(' instr=');
          GSANames.WDecode(instr);
          Config.LogWStr(" class [");
          Config.LogWNum(stamp, 0);
          Config.LogWStr("] ");
          Config.LogWStr(" pos:");
          Config.LogWNum(pos, 0);
          Config.LogWStr(" dfo:");
          Config.LogWNum(instr.dfo, 0);
          Config.LogWLn;
        END;

        (* The operand number matches.  Split this instruction by removing it from
         * its current partition, and appending it to the new parition.  The new
         * paritition will be processed when the classes are committed.
         *)
        IF class.split = NIL THEN
          IF dfSplitByUses IN diagnostics THEN
            Config.LogWStr("SplitByUse: new partition: ");
            Config.LogWNum(stamp, 3);
            Config.LogWLn;
          END;
          NEW(split);
          class.split := split;
          split.split := class;
          Push(split);
          split.next := classes;
          classes := split;
          split.number := stamp;
          INC(stamp);
        ELSE
          IF dfSplitByUses IN diagnostics THEN
              Config.LogWStr("SplitByUse: old partition: ");
              Config.LogWNum(class.split.number, 3);
              Config.LogWLn;
          END;
        END;
        RemoveFromClass(instr);
        AppendToClass(class.split, instr);
      ELSIF use.opnum > max THEN
        max := use.opnum;
      END;
      use := use.fuses;
    END;
  END SplitByUses;

  (* SplitByClass: Split partition based on results & operands
   *)
  PROCEDURE SplitByClass(class: Class);
  VAR
    results: POINTER TO ARRAY OF GSAData.Result;
    inst : GSAData.Instruction;
    i, rmax, pos, max: INTEGER;
    rpos : INTEGER; (* result position being examined *)
  BEGIN
    NEW(results, InstructionsNumberOf(class));
    rmax := ResultsMaxNumberOf(class);

    (* inv: rmax <-> number of results from instruction
     * All instructions in this class should have `rmax' results
     *)
    rpos := 0;
    REPEAT  (* Partition for each $result *)
      pos := 0;
      max := 0;
      REPEAT
        inst := class.instr;
        i := 0;
        REPEAT
          results[i] := GSAData.ResultNth(rpos, inst);
          INC(i);
          inst := inst.inlink
        UNTIL inst = class.instr;

        WHILE i > 0 DO
          DEC(i);
          IF dfSplitByResult IN diagnostics THEN
            Config.LogWStr("SplitByResult");
            Config.LogWStr(" class=");
            Config.LogWNum(class.number, 0);
            Config.LogWStr(" i=");
            Config.LogWNum(i, 0);
            Config.LogWStr(" rmax=");
            Config.LogWNum(rmax, 3);
            Config.LogWStr(" rpos=");
            Config.LogWNum(rpos, 0);
            Config.LogWStr(" max=");
            Config.LogWNum(max, 0);
            Config.LogWStr(" pos=");
            Config.LogWNum(pos, 0);
            Config.LogWStr(" result exists=");
            Config.LogWBool(results[i] # NIL);
            Config.LogWLn;
          END;

          IF results[i] # NIL THEN
            SplitByUses(results[i].uses, pos, max);
          END;
        END;
        CommitClasses;
        INC(pos);
      UNTIL pos > max;
      INC(rpos);
    UNTIL rpos > rmax;
    results := NIL;
  END SplitByClass;

  (* SplitByWorklist: Further split partitions based on the contents
   *                  of the existing partitions (based on opcodes).
   *                  The new split is based on the operands & results.
   *)
  PROCEDURE SplitByWorklist;
    VAR
      class: Class;
  BEGIN
    WHILE worklist.nlink # worklist DO
      class := worklist.nlink;
      class.plink.nlink := class.nlink;
      class.nlink.plink := class.plink;
      class.nlink := NIL;
      class.plink := NIL;
      IF dfSplitByWorklist IN diagnostics THEN
        Config.LogWStr("SplitByWorklist");
        Config.LogWStr(" class=");
        Config.LogWNum(class.number, 0);
        Config.LogWLn;
      END;
      SplitByClass(class);
    END
  END SplitByWorklist;

  PROCEDURE SplitByAddressable(r : GSAData.GlobalRegion);
    VAR
      pos, max : INTEGER;
      a : GSAData.Addressable;
  BEGIN
    a := r.addressables.faddr;
    WHILE a # r.addressables DO
      pos := 0;
      max := 0;
      REPEAT
        SplitByUses(a.uses, pos, max);
        CommitClasses;
        INC(pos);
      UNTIL pos > max;
      a := a.faddr;
    END;
  END SplitByAddressable;

  PROCEDURE SplitByConst(r : GSAData.GlobalRegion);
    VAR
      p: GSAData.Const;
      pos, max: INTEGER;
  BEGIN
    p := r.constants.fcon;
    WHILE p # r.constants DO
      pos := 0;
      max := 0;
      IF dfSplitByConst IN diagnostics THEN
        Config.LogWStr("const=");
        GSANames.WDecode(p);
        Config.LogWStr(" ");
        GSANames.WDecode(p.uses);
        Config.LogWStr(" ");
        Config.LogWNum(pos, 3);
        Config.LogWStr(" ");
        Config.LogWNum(pos, max);
        Config.LogWLn;
      END;
      REPEAT
        SplitByUses(p.uses, pos, max);
        CommitClasses;
        INC(pos);
      UNTIL pos > max;
      p := p.fcon;
    END;
  END SplitByConst;

  (* Put loops into different classes (they are not congruent?) *)
  PROCEDURE SplitByLoops;
    VAR
      i : INTEGER;
      p, next: GSAData.Instruction;
      class: Class;
  BEGIN
    IF opclass[GSAOpcode.Gmerge][GSAOpcode.Gloop] # NIL THEN
      p := opclass[GSAOpcode.Gmerge][GSAOpcode.Gloop].instr;
      IF (p # NIL) & (p.inlink # p) THEN
        p := p.inlink;
        REPEAT
          next := p.inlink;
          class := NewClass();
          RemoveFromClass(p);
          AppendToClass(class, p);
          p := next;
        UNTIL p = opclass[GSAOpcode.Gmerge][GSAOpcode.Gloop].instr;
      END;
    END;
  END SplitByLoops;

  (* Split all instruction classes which have raUniqueResult.
   *
   * The conversion to GSA guarantees that if one instruction in a
   * class has raUniqueResult set, then all instructions in that
   * class will have it set.
   *
   * This routine traverses all opcode classes, which in theory is
   * time consuming.  Additional information could be provided indicating
   * which opcode classes have unique results, but that would place
   * additional burden on the maintenance of the translation to GSA -
   * any time a new instruction is set to 'raUniqueResult' it would
   * require a change in this module; that is a fragility I am not
   * willing to assume.
   *)
  PROCEDURE SplitByUniqueResult;
    VAR
      p, next: GSAData.Instruction;
      c, class: Class;
  BEGIN
    c := classes;
    WHILE c # NIL DO
      IF GSAData.raUniqueResult IN c.instr.attrib THEN
        p := c.instr;
        IF p.inlink # p THEN
          p := p.inlink;
          REPEAT
            next := p.inlink;
            class := NewClass();
            RemoveFromClass(p);
            AppendToClass(class, p);
            p := next;
          UNTIL p = c.instr;
        END;
      END;
      c := c.next;
    END;
  END SplitByUniqueResult;

  (* Replace: replace congruent instructions with a single instance *)
  PROCEDURE Replace(r : GSAData.GlobalRegion);
    VAR
      SP : INTEGER;
      changes : POINTER TO ARRAY OF Class;

    PROCEDURE traverse(r : GSAData.Region);
      VAR
        oldSP : INTEGER;
        i : GSAData.Instruction;
        class : Class;
        r0, r1 : GSAData.Result;
        rgn : GSAData.Region;
    BEGIN
      oldSP := SP;
      i := r.instructions.finst;
      WHILE i # r.instructions DO
        IF ~(i IS GSAData.Region) THEN
          class := i.info(Class);
          IF class.replacement = NIL THEN
            (* No instruction of this class seen yet.  Use the
             * current instruction as a replacement for all other
             * instructions in the class. *)
            changes[SP] := class;
            INC(SP);
            class.replacement := i;
          ELSE
            r0 := i;
            r1 := class.replacement;
            (* An instruction of this class already has been processed.
             * Use the 'replacement instruction' to do a replacement *)
            REPEAT
              GSAData.UseReplace(r0, r1);
              IF r0.bres # i THEN
                r0 := r0.bres;
                r1 := r1.bres;
              ELSE
                r0 := NIL;
              END;
            UNTIL r0 = NIL;
          END;
        END;
        i := i.finst;
      END;

      rgn := r.regions.freg;
      WHILE rgn # r.regions DO
        traverse(rgn);
        rgn := rgn.freg;
      END;

      (* drop definitions *)
      WHILE SP > oldSP DO
        DEC(SP);
        changes[SP].replacement := NIL;
      END;
    END traverse;

  BEGIN
    NEW(changes, 1024);
    SP := 0;
    traverse(r);
  END Replace;

  (* Creates initial partitions *)
  PROCEDURE SetupDataStructures;
  BEGIN
    NEW(opclass);
    NEW(opclass[GSAOpcode.Maccess], 1 + GSAOpcode.Mvarparm - GSAOpcode.Mfield);
    NEW(opclass[GSAOpcode.Mupdate], 1 + GSAOpcode.Mvarparm - GSAOpcode.Mfield);
    NEW(opclass[GSAOpcode.Mmemory], 1 + GSAOpcode.Mnewdynarray - GSAOpcode.Madr);
    NEW(opclass[GSAOpcode.Mregion], 1 + GSAOpcode.Mbody - GSAOpcode.Mgreg);
    NEW(opclass[GSAOpcode.Aabs], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Aneg], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Aadd], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Asub], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Adiv], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Amul], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Amod], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Aodd], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Aconvert], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Anot], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Lrol], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Lror], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Llsl], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Llsr], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Lasl], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Lasr], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hget], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hput], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hgetreg], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hputreg], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hmemr], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Hmemw], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Ceql], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Cneq], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Clss], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Cleq], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Cgtr], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Cgeq], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sdiff], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sunion], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Ssub], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sintersection], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sneg], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sincl], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sexcl], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Srange], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Selement], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Sconvert], ArithmeticSubclasses);
    NEW(opclass[GSAOpcode.Ttrap], 1 + GSAOpcode.Tnil - GSAOpcode.Tindex);
    NEW(opclass[GSAOpcode.Gmisc], 1 + GSAOpcode.Gcap - GSAOpcode.Gcall);
    NEW(opclass[GSAOpcode.Gsystem], 1 + GSAOpcode.Gcondcode - GSAOpcode.Gbit);
    NEW(opclass[GSAOpcode.Gguard], 1 + GSAOpcode.Gexit - GSAOpcode.Gtrue);
    NEW(opclass[GSAOpcode.Gmerge], 1 + GSAOpcode.Gcase - GSAOpcode.Gif);
    NEW(opclass[GSAOpcode.Gtypedesc], 1 + GSAOpcode.Ginitdarr - GSAOpcode.Ginitrec);
    NEW(opclass[GSAOpcode.Palias], 1 + GSAOpcode.Paliasasgn - GSAOpcode.Pnoalias);
    NEW(opclass[GSAOpcode.Phwdreg], 1 + GSAOpcode.Pmovefromreg - GSAOpcode.Pmovetoreg);
    NEW(opclass[GSAOpcode.Pnlm], 1 + GSAOpcode.Pctor - GSAOpcode.Pdtor);
    NEW(opclass[GSAOpcode.Pmisc], 1 + GSAOpcode.Pimport - GSAOpcode.Pgate);

    NEW(worklist);
    worklist.nlink := worklist;
    worklist.plink := worklist;
    NEW(stack);
  END SetupDataStructures;

  (* Ensure the entire array is initalized *)
  PROCEDURE InitializeStructures;
    VAR
      i, j : INTEGER;
  BEGIN
    ASSERT(opclass # NIL);
    i := 0;
    WHILE i < LEN(opclass^) DO
      j := 0;
      WHILE j < LEN(opclass[i]^) DO
        opclass[i][j] := NIL;
        INC(j);
      END;
      INC(i);
    END;
    classes := NIL;
  END InitializeStructures;

  (* post: (Ai: i IN r.instructions: clobbered(i.info)) *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
  BEGIN
    IF dfBanner IN diagnostics THEN
      Config.LogWStr('Value Numbering');
      Config.LogWLn;
    END;
    classes := NIL;
    stamp := 0;
    GSACAN.Perform(r); (* canonicalize operands for better splitting *)
    InitializeStructures;
    BuildParitions(r);
    CountUses;
    SplitByUniqueResult;
    SplitByLoops;
    sp := 0;
    SplitByConst(r);
    SplitByAddressable(r);
    SplitByWorklist;
    IF dfDumpClasses IN diagnostics THEN
      DumpClasses(r);
    END;
    Replace(r);

    IF dfBanner IN diagnostics THEN
      Config.LogWStr('Value Numbering complete');
      Config.LogWLn;
    END;
  END Perform;

  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN
    opclass := NIL;
    classes := NIL;
    worklist := NIL;
    stack := NIL;
  END NILGlobalPointers;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN
    NILGlobalPointers;
    SetupDataStructures;
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
END O3GSAValueNumber.
