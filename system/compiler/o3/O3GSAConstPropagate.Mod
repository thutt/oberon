MODULE O3GSAConstPropagate;
IMPORT
  SYSTEM,
  Config := O3Config,
  E := O3Errors,
  Symtab := O3Symtab,
  GSANames := O3GSANames,
  GSAOpcode := O3GSAOpcode,
  GSAData := O3GSAData,
  GSADump := O3GSADump;

CONST (* diagnostic flags *)
  dfDumpLattice = 0;
  dfDumpWorklist = 1;
  dfCaseProgress = 2;
  dfInitialize = 3;
  dfReplaceByConst = 4;
  dfProgress = 5;
  diagnostics = {};

CONST (* classification states
       * These states are designed so that the algorithm will produce
       * smaller 'state' values as an instruction becomes more classified.
       * inv: states will only get smaller; if a state value gets larger,
       *      after a call to NewLattice, then the compiler has an internal
       *      error.
       *)
  csUnclass = 20;
  csConst = 19;
  csOperand = 18; (* constant value; use operand specified in 'op' field *)
  csNonconst = 17;
  csUnreachable = 16;

TYPE
  Lattice = POINTER TO LatticeDesc;
  LatticeDesc = RECORD (GSAData.UsableDesc)
    const : GSAData.Const;
    state : INTEGER;
    op    : INTEGER;
  END;

  OperandArray = POINTER TO ARRAY OF Lattice;

VAR
  worklist : GSAData.Instruction; (* worklist; with dummy head *)
  unclassified : Lattice;
  nonconst : Lattice;
  unreachable : Lattice;
  gFalse : Lattice;         (* lattice for Guard; never executed *)
  gTrue : Lattice;          (* lattice for Guard; always executed *)
  operands : OperandArray; (* operands for an instruction *)
  loopsimplified : BOOLEAN;

  PROCEDURE outlattice(l : Lattice);
  BEGIN
    IF l = unclassified THEN
      Config.LogWStr('unclassified');
    ELSIF l = nonconst THEN
      Config.LogWStr('nonconst');
    ELSIF l = unreachable THEN
      Config.LogWStr('unreachable');
    ELSIF l = gTrue THEN
      Config.LogWStr('true');  (* Always executed. *)
    ELSIF l = gFalse THEN
      Config.LogWStr('false'); (* Never executed. *)
    ELSIF l.state = csOperand THEN
      Config.LogWStr('operand-');    (* Guard; use specific operand. *)
      Config.LogWNum(l(Lattice).op, 0);
    ELSE
      Config.LogWStr('const');
    END;
  END outlattice;

  PROCEDURE output(i : GSAData.Instruction);
  BEGIN
    Config.LogWStr("(");
    Config.LogWNum(i.dfo, 3);
    Config.LogWStr(')  [');
    IF i.info # NIL THEN
      outlattice(i.info(Lattice));
    ELSE
      Config.LogWStr('none');
    END;
    Config.LogWStr('] ');
    GSANames.WDecode(i);
    Config.LogWLn;
  END output;

  PROCEDURE dumplattice(r : GSAData.GlobalRegion);

    PROCEDURE dl(r : GSAData.Region);
      VAR
        i : GSAData.Instruction;
        rgn : GSAData.Region;
        c : INTEGER;
    BEGIN
      output(r);
      i := r.instructions.finst;
      WHILE i # r.instructions DO
        IF i IS GSAData.Region THEN
          dl(i(GSAData.Region));
        ELSE
          output(i);
        END;
        i := i.finst;
      END;
    END dl;

  BEGIN
    Config.LogWLn;
    Config.LogWStr('const propagate lattice for ');
    Config.LogWStr(r.proc.name^);
    Config.LogWLn;
    dl(r);
  END dumplattice;

  PROCEDURE dumpworklist;
    VAR
      i : GSAData.Instruction;
  BEGIN
    i := worklist.inlink;
    Config.LogWStr('const propagate worklist');
    Config.LogWLn;
    WHILE i # worklist DO
      output(i);
      i := i.inlink;
    END;
  END dumpworklist;

  PROCEDURE HasLattice(u : GSAData.Usable) : BOOLEAN;
  BEGIN
    RETURN (u.info # NIL) & (u.info IS Lattice);
  END HasLattice;

  (* OperandLattice: Returns a lattice which represents operand 'op'
   *
   * To reduce memory usage, all operand lattices are stored in a
   * module array and all references to the same operand number receive
   * the same physical operand lattice.
   *)
  PROCEDURE OperandLattice(op : INTEGER) : Lattice;
    VAR
      i, len : LONGINT;
      t : OperandArray;
      l : Lattice;
  BEGIN
    len := LEN(operands^);
    IF op >= len THEN
      NEW(t, op + 1);
      i := 0;
      WHILE i < len DO
        t[i] := operands[i];
        INC(i);
      END;
      WHILE i < op + 1 DO
        t[i] := NIL;
        INC(i);
      END;
      operands := t;
    END;
    IF operands[op] = NIL THEN
      NEW(l);
      l.const := NIL;
      l.state := csOperand;
      l.op := op;
      operands[op] := l;
    END;
    RETURN operands[op];
  END OperandLattice;

  PROCEDURE ConstLattice(c : GSAData.Const) : Lattice;
    VAR l : Lattice;
  BEGIN
    IF ~HasLattice(c) THEN
      NEW(l);
      l.state := csConst;
      l.const := c;
      l.op := 0;
      c.info := l;
    END;
    RETURN c.info(Lattice);
  END ConstLattice;

  (* result = TRUE -> instruction can be folded by constant folding *)
  (* result = FALSE -> instruction cannot be folded by constant folding *)
  PROCEDURE CanFold(inst : GSAData.Instruction) : BOOLEAN;
    VAR
      class, subcl : SHORTINT;
  BEGIN
    class := inst.class;
    subcl := inst.subcl;
    IF (class >= GSAOpcode.Mbegin) & (class < GSAOpcode.Mend) THEN
      RETURN FALSE;
    ELSIF (class >= GSAOpcode.Abegin) & (class < GSAOpcode.Aend) THEN
      RETURN ~(subcl IN {GSAOpcode.asR8, GSAOpcode.asR4, GSAOpcode.asST});
    ELSIF (class >= GSAOpcode.Lbegin) & (class < GSAOpcode.Lend) THEN
      RETURN ~(subcl IN {GSAOpcode.asR8, GSAOpcode.asR4, GSAOpcode.asST});
    ELSIF (class >= GSAOpcode.Hbegin) & (class < GSAOpcode.Hend) THEN
      RETURN FALSE;
    ELSIF (class >= GSAOpcode.Cbegin) & (class < GSAOpcode.Cend) THEN
      RETURN TRUE;
    ELSIF (class >= GSAOpcode.Sbegin) & (class < GSAOpcode.Send) THEN
      RETURN TRUE;
    ELSIF (class >= GSAOpcode.Tbegin) & (class < GSAOpcode.Tend) THEN
      RETURN FALSE;
    ELSIF (class >= GSAOpcode.Pbegin) & (class < GSAOpcode.Pend) THEN
      RETURN FALSE;
    ELSIF (class >= GSAOpcode.Gbegin) & (class < GSAOpcode.Gend) THEN
      CASE class OF
      | GSAOpcode.Gmisc:
        RETURN subcl IN {GSAOpcode.Gcap};

      | GSAOpcode.Gguard, GSAOpcode.Gmerge:
        Config.Fatal(-1); (* handled as Region *)
      ELSE
        RETURN FALSE;
      END;
    END;
  END CanFold;

  PROCEDURE IsAdr(inst : GSAData.Instruction) : BOOLEAN;
  BEGIN
    RETURN FALSE; (* Handled by ValueNumber? *)
    RETURN (inst.class = GSAOpcode.Mmemory) & (inst.subcl = GSAOpcode.Madr);
  END IsAdr;

  (* CalcConstant: calculate an instruction with known constant operands
   *)
  PROCEDURE CalcConstant(inst : GSAData.Instruction;
                         c0   : GSAData.Const;
                         c1   : GSAData.Const) : GSAData.Const;
    VAR
      class, subcl : SHORTINT;
      op0 : GSAData.Operand;
      def : GSAData.Usable;

    PROCEDURE conditional(class, subcl : INTEGER;
                          inst : GSAData.Instruction;
                          c0   : GSAData.Const;
                          c1   : GSAData.Const) : GSAData.Const;
      VAR
        tf : SHORTINT;
        b : BOOLEAN;
    BEGIN
      tf := c0.type.form;
      CASE class OF
      | GSAOpcode.Ceql:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.pointer,
          Symtab.nil,
          Symtab.procedure: b := c0(GSAData.ConstInt).val = c1(GSAData.ConstInt).val;

        | Symtab.set: b := c0(GSAData.ConstSet).val = c1(GSAData.ConstSet).val;

        | Symtab.bool: b := c0(GSAData.ConstBool).val = c1(GSAData.ConstBool).val;
        END;

      | GSAOpcode.Cneq:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.nil,
          Symtab.pointer,
          Symtab.procedure: b := c0(GSAData.ConstInt).val # c1(GSAData.ConstInt).val;

        | Symtab.set: b := c0(GSAData.ConstSet).val # c1(GSAData.ConstSet).val;

        | Symtab.bool: b := c0(GSAData.ConstBool).val # c1(GSAData.ConstBool).val;
        END;

      | GSAOpcode.Clss:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.pointer,
          Symtab.procedure: b := c0(GSAData.ConstInt).val < c1(GSAData.ConstInt).val;
        END;

      | GSAOpcode.Cleq:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.pointer,
          Symtab.procedure: b := c0(GSAData.ConstInt).val <= c1(GSAData.ConstInt).val;
        END;

      | GSAOpcode.Cgtr:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.pointer,
          Symtab.procedure: b := c0(GSAData.ConstInt).val > c1(GSAData.ConstInt).val;
        END;

      | GSAOpcode.Cgeq:
        CASE tf OF
        | Symtab.char,
          Symtab.byte,
          Symtab.sint,
          Symtab.int,
          Symtab.lint,
          Symtab.pointer,
          Symtab.procedure: b := c0(GSAData.ConstInt).val >= c1(GSAData.ConstInt).val;
        END;
      END;
      RETURN GSAData.ConstGetBool(inst.region, b, inst.pos);
    END conditional;

    PROCEDURE Aconvert(class, subcl : INTEGER;
                       inst : GSAData.Instruction;
                       c0   : GSAData.Const;
                       c1   : GSAData.Const) : GSAData.Const;
      VAR
        type : Symtab.Type;
        result : GSAData.Const;
    BEGIN
      (* FEG: conversion of constants will always succeed *)
      CASE subcl (* destination type *) OF
      | GSAOpcode.asS1:
        type := Symtab.sinttyp;

      | GSAOpcode.asU1:
        type := Symtab.chartyp;

      | GSAOpcode.asS2:
        type := Symtab.inttyp;

      | GSAOpcode.asS4:
        type := Symtab.linttyp;

      | GSAOpcode.asU4:
        type := Symtab.linttyp; (* should be an unsigned type, but there is none *)
      END;
      result := GSAData.ConstGetInt(inst.region, c0(GSAData.ConstInt).val,
                                    type, inst.pos);
      RETURN result;
    END Aconvert;

    PROCEDURE Aabs(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt) : GSAData.Const;
      VAR m : Symtab.TypeMetric;
    BEGIN
      m := Symtab.metrics[inst.type.form];
      IF (c0.val > m(Symtab.OrdMetric).min) &
         (c0.val <= m(Symtab.OrdMetric).max) THEN
        RETURN GSAData.ConstGetInt(inst.region, ABS(c0.val), inst.type, inst.pos);
      ELSE
        Config.Error(E.NumberTooLarge);
        RETURN NIL;
      END;
    END Aabs;

    PROCEDURE Aneg(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt) : GSAData.Const;
      VAR
        m : Symtab.TypeMetric;
    BEGIN
      m := Symtab.metrics[inst.type.form];
      IF c0.val # m(Symtab.OrdMetric).min THEN
        RETURN GSAData.ConstGetInt(inst.region, -c0.val, inst.type, inst.pos);
      ELSE
        Config.Error(E.NumberTooLarge);
        RETURN NIL;
      END;
    END Aneg;

    PROCEDURE Aadd(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt;
                   c1   : GSAData.ConstInt) : GSAData.Const;
      VAR
        t0, t1 : BOOLEAN;
        c : GSAData.Const;
        m : Symtab.TypeMetric;
    BEGIN
      m := Symtab.metrics[inst.type.form];
      t0 := (c1.val >= 0) & (c0.val <= m(Symtab.OrdMetric).max - c1.val);
      t1 := (c1.val < 0) & (c0.val >= m(Symtab.OrdMetric).min - c1.val);
      IF t0 OR t1 THEN
        c := GSAData.ConstGetInt(inst.region, c0.val + c1.val, inst.type, inst.pos);
      ELSE
        Config.Error(E.SumTooLarge);
        c := NIL;
      END;
      RETURN c;
    END Aadd;

    PROCEDURE Asub(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt;
                   c1   : GSAData.ConstInt) : GSAData.Const;
      VAR
        t0, t1 : BOOLEAN;
        c : GSAData.Const;
        m : Symtab.TypeMetric;
    BEGIN
      m := Symtab.metrics[inst.type.form];
      t0 := (c1.val >= 0) & (c0.val >= m(Symtab.OrdMetric).min + c1.val);
      t1 := (c1.val < 0) & (c0.val <= m(Symtab.OrdMetric).max + c1.val);
      IF t0 OR t1 THEN
        c := GSAData.ConstGetInt(inst.region, c0.val - c1.val, inst.type, inst.pos);
      ELSE
        Config.Error(E.DifferenceTooLarge);
        c := NIL;
      END;
      RETURN c;
    END Asub;

    PROCEDURE Adiv(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt;
                   c1   : GSAData.ConstInt) : GSAData.Const;
      VAR c : GSAData.Const;
    BEGIN
      IF c1.val # 0 THEN
        c := GSAData.ConstGetInt(inst.region, c0.val DIV c1.val, inst.type, inst.pos);
      ELSE
        Config.Error(E.DivisionByZero);
        c := NIL;
      END;
      RETURN c;
    END Adiv;

    PROCEDURE Amul(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt;
                   c1   : GSAData.ConstInt) : GSAData.Const;
      VAR
        t0, t1 : BOOLEAN;
        c : GSAData.Const;
        m : Symtab.TypeMetric;
        lim : LONGINT;
    BEGIN
      m := Symtab.metrics[inst.type.form];
      IF (c0.val >= 0) = (c1.val >= 0) THEN
        lim := m(Symtab.OrdMetric).max;
      ELSE
        lim := m(Symtab.OrdMetric).min;
      END;

      (* inv: lim <=> overflow limit *)
      IF (c0.val = 0) OR (c1.val = 0) THEN
        c := GSAData.ConstGetInt(inst.region, 0, inst.type, inst.pos);
      ELSE
        lim := lim DIV c1.val;
        t0 := (c0.val >= 0) & (c0.val <= lim);
        t1 := (c0.val < 0) & (c0.val >= lim);
        IF t0 OR t1 THEN
          c := GSAData.ConstGetInt(inst.region, c0.val * c1.val, inst.type, inst.pos);
        ELSE
          Config.Error(E.ProductTooLarge);
          c := NIL;
        END
      END;
      RETURN c;
    END Amul;

    PROCEDURE Amod(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt;
                   c1   : GSAData.ConstInt) : GSAData.Const;
      VAR c : GSAData.Const;
    BEGIN
      IF c1.val # 0 THEN
        c := GSAData.ConstGetInt(inst.region, c0.val MOD c1.val, inst.type, inst.pos);
      ELSE
        Config.Error(E.DivisionByZero);
        c := NIL;
      END;
      RETURN c;
    END Amod;

    PROCEDURE Aodd(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetBool(inst.region, ODD(c0.val), inst.pos);
    END Aodd;

    PROCEDURE Anot(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstBool) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetBool(inst.region, ~c0.val, inst.pos);
    END Anot;

    PROCEDURE Lrotate(class, subcl : INTEGER;
                      inst : GSAData.Instruction;
                      c0   : GSAData.ConstInt;
                      c1   : GSAData.ConstInt) : GSAData.Const;
      VAR v : LONGINT;
    BEGIN
      IF (c1.val >= 0) & (c1.val < 32) THEN
        CASE class OF
        | GSAOpcode.Lrol: v := c1.val;
        | GSAOpcode.Lror: v := -c1.val;
        END;
        RETURN GSAData.ConstGetInt(inst.region, SYSTEM.ROT(c0.val, v),
                                   inst.type, inst.pos);
      ELSE
        Config.Error(E.NumberTooLarge);
        RETURN NIL;
      END;
    END Lrotate;

    PROCEDURE Llshift(class, subcl : INTEGER;
                      inst : GSAData.Instruction;
                      c0   : GSAData.ConstInt;
                      c1   : GSAData.ConstInt) : GSAData.Const;
      VAR v : LONGINT;
    BEGIN
      IF (c1.val >= 0) & (c1.val < 32) THEN
        CASE class OF
        | GSAOpcode.Llsl: v := c1.val;
        | GSAOpcode.Llsr: v := -c1.val;
        END;
        RETURN GSAData.ConstGetInt(inst.region, SYSTEM.LSH(c0.val, v),
                                   inst.type, inst.pos);
      ELSE
        Config.Error(E.NumberTooLarge);
        RETURN NIL;
      END;
    END Llshift;

    PROCEDURE Lashift(class, subcl : INTEGER;
                      inst : GSAData.Instruction;
                      c0   : GSAData.ConstInt;
                      c1   : GSAData.ConstInt) : GSAData.Const;
      VAR v : LONGINT;
    BEGIN
      IF (c1.val >= 0) & (c1.val < 32) THEN
        CASE class OF
        | GSAOpcode.Lasl: v := c1.val;
        | GSAOpcode.Lasr: v := -c1.val;
        END;
        RETURN GSAData.ConstGetInt(inst.region, ASH(c0.val, v),
                                   inst.type, inst.pos);
      ELSE
        Config.Error(E.NumberTooLarge);
        RETURN NIL;
      END;
    END Lashift;

    PROCEDURE Sdiff(class, subcl : INTEGER;
                    inst : GSAData.Instruction;
                    c0   : GSAData.ConstSet;
                    c1   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, c0.val - c1.val, inst.pos);
    END Sdiff;

    PROCEDURE Sunion(class, subcl : INTEGER;
                     inst : GSAData.Instruction;
                     c0   : GSAData.ConstSet;
                     c1   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, c0.val + c1.val, inst.pos);
    END Sunion;

    PROCEDURE Ssub(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstSet;
                   c1   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, c0.val - c1.val, inst.pos);
    END Ssub;

    PROCEDURE Sintersection(class, subcl : INTEGER;
                            inst : GSAData.Instruction;
                            c0   : GSAData.ConstSet;
                            c1   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, c0.val * c1.val, inst.pos);
    END Sintersection;

    PROCEDURE Sneg(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, -c0.val, inst.pos);
    END Sneg;

    PROCEDURE Sincl(class, subcl : INTEGER;
                    inst : GSAData.Instruction;
                    c0   : GSAData.ConstSet;
                    c1   : GSAData.ConstInt) : GSAData.Const;
      VAR
        s : SET;
    BEGIN
      s := {c1.val};
      RETURN GSAData.ConstGetSet(inst.region, c0.val + s, inst.pos);
    END Sincl;

    PROCEDURE Sexcl(class, subcl : INTEGER;
                    inst : GSAData.Instruction;
                    c0   : GSAData.ConstSet;
                    c1   : GSAData.ConstInt) : GSAData.Const;
      VAR
        s : SET;
    BEGIN
      s := {c1.val};
      RETURN GSAData.ConstGetSet(inst.region, c0.val - s, inst.pos);
    END Sexcl;

    PROCEDURE Srange(class, subcl : INTEGER;
                     inst : GSAData.Instruction;
                     c0   : GSAData.ConstInt;
                     c1   : GSAData.ConstInt) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, {c0.val..c1.val}, inst.pos);
    END Srange;

    PROCEDURE Selement(class, subcl : INTEGER;
                       inst : GSAData.Instruction;
                       c0   : GSAData.ConstInt;
                       c1   : GSAData.ConstSet) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetBool(inst.region, c0.val IN c1.val, inst.pos);
    END Selement;

    PROCEDURE Sconvert(class, subcl : INTEGER;
                       inst : GSAData.Instruction;
                       c0   : GSAData.ConstInt) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetSet(inst.region, {c0.val}, inst.pos);
    END Sconvert;

    PROCEDURE Gcap(class, subcl : INTEGER;
                   inst : GSAData.Instruction;
                   c0   : GSAData.ConstInt) : GSAData.Const;
    BEGIN
      RETURN GSAData.ConstGetInt(inst.region, ORD(CAP(CHR(c0.val))), inst.type, inst.pos);
    END Gcap;

  BEGIN
    class := inst.class;
    subcl := inst.subcl;
    IF (class >= GSAOpcode.Abegin) & (class < GSAOpcode.Aend) THEN
      CASE class OF
      | GSAOpcode.Aabs:
        RETURN Aabs(class, subcl, inst, c0(GSAData.ConstInt));

      | GSAOpcode.Aneg:
        RETURN Aneg(class, subcl, inst, c0(GSAData.ConstInt));

      | GSAOpcode.Aadd:
        RETURN Aadd(class, subcl, inst,
                    c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Asub:
        RETURN Asub(class, subcl, inst,
                    c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Adiv:
        RETURN Adiv(class, subcl, inst,
                    c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Amul:
        RETURN Amul(class, subcl, inst,
                    c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Amod:
        RETURN Amod(class, subcl, inst,
                    c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Aodd:
        RETURN Aodd(class, subcl, inst, c0(GSAData.ConstInt));

      | GSAOpcode.Anot:
        RETURN Anot(class, subcl, inst, c0(GSAData.ConstBool));

      | GSAOpcode.Aconvert:
        RETURN Aconvert(class, subcl, inst, c0, c1);
      END;
    ELSIF (class >= GSAOpcode.Lbegin) & (class < GSAOpcode.Lend) THEN
      CASE class OF
      | GSAOpcode.Lrol, GSAOpcode.Lror:
        RETURN Lrotate(class, subcl, inst,
                       c0(GSAData.ConstInt), c1(GSAData.ConstInt));
      | GSAOpcode.Llsl, GSAOpcode.Llsr:
        RETURN Llshift(class, subcl, inst,
                       c0(GSAData.ConstInt), c1(GSAData.ConstInt));
      | GSAOpcode.Lasr, GSAOpcode.Lasl:
        RETURN Lashift(class, subcl, inst,
                       c0(GSAData.ConstInt), c1(GSAData.ConstInt));
      END;
    ELSIF (class >= GSAOpcode.Cbegin) & (class < GSAOpcode.Cend) THEN
      RETURN conditional(class, subcl, inst, c0, c1);
    ELSIF (class >= GSAOpcode.Sbegin) & (class < GSAOpcode.Send) THEN
      CASE class OF
      | GSAOpcode.Sdiff:
        RETURN Sdiff(class, subcl, inst,
                     c0(GSAData.ConstSet), c1(GSAData.ConstSet));

      | GSAOpcode.Sunion:
        RETURN Sdiff(class, subcl, inst,
                     c0(GSAData.ConstSet), c1(GSAData.ConstSet));

      | GSAOpcode.Ssub:
        RETURN Ssub(class, subcl, inst,
                    c0(GSAData.ConstSet), c1(GSAData.ConstSet));

      | GSAOpcode.Sintersection:
        RETURN Sintersection(class, subcl, inst,
                             c0(GSAData.ConstSet), c1(GSAData.ConstSet));

      | GSAOpcode.Sneg:
        RETURN Sneg(class, subcl, inst, c0(GSAData.ConstSet));

      | GSAOpcode.Sincl:
        RETURN Sincl(class, subcl, inst,
                     c0(GSAData.ConstSet), c1(GSAData.ConstInt));

      | GSAOpcode.Sexcl:
        RETURN Sexcl(class, subcl, inst,
                     c0(GSAData.ConstSet), c1(GSAData.ConstInt));

      | GSAOpcode.Srange:
        RETURN Srange(class, subcl, inst,
                      c0(GSAData.ConstInt), c1(GSAData.ConstInt));

      | GSAOpcode.Selement:
        RETURN Selement(class, subcl, inst,
                        c0(GSAData.ConstInt), c1(GSAData.ConstSet));

      | GSAOpcode.Sconvert:
        RETURN Sconvert(class, subcl, inst, c0(GSAData.ConstInt));
      END;
    ELSE
      CASE subcl OF
      | GSAOpcode.Gcap: RETURN Gcap(class, subcl, inst, c0(GSAData.ConstInt));
      END;
    END;
  END CalcConstant;

  PROCEDURE InitLattice(usable : GSAData.Usable);
    VAR
      u : GSAData.Usable;
      res : GSAData.Result;
      op : GSAData.Operand;
  BEGIN
    u := usable;
    IF ~HasLattice(u) THEN
      WITH u:GSAData.GlobalRegion DO
        usable.info := gTrue;

      | u:GSAData.Region DO
        usable.info := unclassified;
        op := u.operands.fop;
        WHILE op # u.operands DO
          InitLattice(op.def);
          op := op.fop;
        END;

      | u:GSAData.Gate DO
        usable.info := unclassified;

      | u:GSAData.Instruction DO
        IF CanFold(u) OR IsAdr(u) THEN
          usable.info := unclassified;
          (* inv: these instructions only produce one result *)
          ASSERT((u.results.fres = u) & (u.results.fres.fres = u.results));
        ELSE
          (* this instruction is not foldable; ensure that
           * all results it produces are marked as 'nonconst'  *)
          res := u.results.fres;
          WHILE res # u.results DO
            res.info := nonconst;
            res := res.fres;
          END;
        END;
      | u:GSAData.Const DO
        usable.info := ConstLattice(u);

      | u:GSAData.Symbol DO
        usable.info := nonconst;
      ELSE
        usable.info := nonconst;
      END;
    END;
  END InitLattice;

  PROCEDURE RegionInitLattices(r : GSAData.GlobalRegion);
    VAR
      res : GSAData.Result;
      enter : GSAData.Instruction;
      const : GSAData.Const;

    PROCEDURE ril(r : GSAData.Region);
      VAR i : GSAData.Instruction;
    BEGIN
      InitLattice(r);
      i := r.instructions.finst;
      WHILE i # r.instructions DO
        WITH i:GSAData.Region DO
          ril(i);
        ELSE
          InitLattice(i);
        END;
        i := i.finst;
      END;
    END ril;

  BEGIN
    (* all parameters passed to the procedure are assumed to be non-const *)
    enter := GSAData.InstructionEnter(r);
    res := enter.results.fres;
    WHILE res # enter.results DO
      res.info := nonconst;
      res := res.fres;
    END;

    (* Initialize all constants used.  These values will appear directly
     * in operands, but without this intialization they will not have
     * a lattice associated with them.  The lattice can be created when the
     * value is used, but that requires a special case check for every
     * operand processed.
     *)
    const := r.constants.fcon;
    WHILE const # r.constants DO
      const.info := ConstLattice(const);
      const := const.fcon;
    END;
    ril(r);
    (* inv: all instructions in 'r' have a lattice value now *)
  END RegionInitLattices;

  (* InitializeWorklist: add instructions to the worklist
   *
   * Add all instructions not classified as 'nonconst'
   *)
  PROCEDURE InitializeWorklist(r : GSAData.GlobalRegion);

    PROCEDURE append(i : GSAData.Instruction);
    BEGIN
      IF dfInitialize IN diagnostics THEN
        Config.LogWStr('init append ');
        GSANames.WDecode(i);
        Config.LogWLn;
      END;
      i.inlink := worklist;
      i.iplink := worklist.iplink;
      worklist.iplink.inlink := i;
      worklist.iplink := i;
    END append;

    PROCEDURE init(r : GSAData.Region);
      VAR
        i : GSAData.Instruction;
    BEGIN
      append(r);
      i := r.instructions.finst;
      WHILE i # r.instructions DO
        IF i.info # nonconst THEN
          IF i IS GSAData.Region THEN
            init(i(GSAData.Region));
          ELSE
            append(i);
          END;
        END;
        i := i.finst;
      END;
    END init;

  BEGIN
    NEW(worklist);
    worklist.inlink := worklist;
    worklist.iplink := worklist;
    init(r);
    IF dfDumpWorklist IN diagnostics THEN
      dumpworklist;
    END;
  END InitializeWorklist;

  PROCEDURE LatticeOfGate(g : GSAData.Gate) : Lattice;
    VAR
      mop : GSAData.Operand;
      merge : GSAData.Merge;

    PROCEDURE Gif(m : GSAData.Merge; g : GSAData.Gate) : Lattice;
      VAR
        op0, op1 : GSAData.Operand;
        l, lop0, lop1 : Lattice;
    BEGIN
      l := m.info(Lattice);
      op0 := GSAData.OperandNth(1, g);
      lop0 := op0.def.info(Lattice);
      op1 := GSAData.OperandNth(2, g);
      lop1 := op1.def.info(Lattice);
      IF l = unclassified THEN
        RETURN unclassified;
      ELSIF l.state = csOperand THEN
        CASE l.op OF
        | 0:
          RETURN lop0;

        | 1:
          RETURN lop1;
        END;
      ELSIF (lop0.state = csConst) & (lop0 = lop1) THEN
        RETURN lop0;
      ELSE
        RETURN nonconst;
      END;
    END Gif;

    PROCEDURE Gcase(m : GSAData.Merge; g : GSAData.Gate) : Lattice;
      VAR
        l, lop : Lattice;
        op : GSAData.Operand;
    BEGIN
      l := m.info(Lattice);
      IF l = unclassified THEN
        RETURN l;
      ELSIF l.state = csOperand THEN
        op := GSAData.OperandNth(1 + l.op, g);
        ASSERT((op # NIL) & (op.def.info # NIL), 1024);
        RETURN op.def.info(Lattice);
      ELSE
        RETURN nonconst;
      END;
    END Gcase;

  BEGIN
    mop := GSAData.OperandNth(0, g);
    merge := mop.def(GSAData.Merge);
    CASE merge.subcl OF
    | GSAOpcode.Gif:
      RETURN Gif(merge, g);

    | GSAOpcode.Gcond:
      HALT(2000); (* internal error; no gates in conditional merges *)

    | GSAOpcode.Gloop:
      RETURN nonconst;

    | GSAOpcode.Gcase:
      RETURN Gcase(merge, g);
    END;
  END LatticeOfGate;

  PROCEDURE LatticeOfGuard(g : GSAData.Guard) : Lattice;

    PROCEDURE Gtrue(g : GSAData.Guard) : Lattice;
      VAR
        op : GSAData.Operand;
        gate : GSAData.Instruction;
        lattice : Lattice;
        b : GSAData.Const;
    BEGIN
      op := GSAData.OperandNth(0, g);
      lattice := op.def.info(Lattice);
      IF lattice.state = csConst THEN
        RETURN lattice;
      ELSIF lattice.state = csOperand THEN
        (* The conditional used for the guard is a gate and
         * is has evaluated to a constant operand.  The value of
         * this guard is based on the value of the operand selected.
         * Keep in mind that the the operand can itself also be a gate.
         *)
        gate := op.def(GSAData.Instruction);
        op := GSAData.OperandNth(lattice.op + 1, gate);
        lattice := op.def.info(Lattice);
        ASSERT(lattice.state = csConst, 1100);
        RETURN lattice;
      ELSE
        RETURN nonconst;
      END;
    END Gtrue;

    PROCEDURE Gfalse(g : GSAData.Guard) : Lattice;
      VAR
        op : GSAData.Operand;
        lattice : Lattice;
        b : GSAData.Const;
        gate : GSAData.Instruction;
    BEGIN
      op := GSAData.OperandNth(0, g);
      lattice := op.def.info(Lattice);
      IF lattice.state = csConst THEN
        IF lattice = gTrue THEN
          RETURN gFalse;
        ELSE
          RETURN gTrue;
        END;
      ELSIF lattice.state = csOperand THEN
        (* The conditional used for the guard is a gate and
         * is has evaluated to a constant operand.  The value of
         * this guard is based on the value of the operand selected.
         *)
        gate := op.def(GSAData.Instruction);
        op := GSAData.OperandNth(lattice.op + 1, gate);
        lattice := op.def.info(Lattice);
        ASSERT(lattice.state = csConst, 1101);
        IF lattice = gTrue THEN
          RETURN gFalse;
        ELSE
          RETURN gTrue;
        END;
      ELSE
        RETURN nonconst;
      END;
    END Gfalse;

    PROCEDURE Gcasesgl(g : GSAData.Guard) : Lattice;
      VAR
        slattice : Lattice;
        selector, op : GSAData.Operand;
        sconst : GSAData.ConstInt;
        oconst : GSAData.Const;
    BEGIN
      selector := GSAData.OperandNth(0, g);
      slattice := selector.def.info(Lattice);
      IF slattice.state = csConst THEN
        op := selector.fop;
        sconst := slattice.const(GSAData.ConstInt);
        WHILE op # g.operands DO
          oconst := op.def(GSAData.Const);
          WITH oconst:GSAData.ConstInt DO
            IF sconst.val = oconst.val THEN
              RETURN gTrue;
            END;

          | oconst:GSAData.ConstIntRange DO
            IF (oconst.lo <= sconst.val) & (sconst.val <= oconst.hi) THEN
              RETURN gTrue;
            END;
          END;
          op := op.fop;
        END;
        RETURN gFalse;
      END;
      RETURN nonconst;
    END Gcasesgl;

    PROCEDURE Gcaseelse(g : GSAData.Guard) : Lattice;
      VAR
        lattice : Lattice;
        selector : GSAData.Operand;
        reg : GSAData.Instruction;
    BEGIN
      selector := GSAData.OperandNth(0, g);
      lattice := selector.def.info(Lattice);
      IF lattice.state = csConst THEN
        IF g.region.info(Lattice) = unclassified THEN
          reg := g.binst;
          (* $case is unclassified;
           * Check all $casesgl regions to see if one is active
           *
           * Gcaseelse will always appear last in a case region:
           *   This guard is not yet classified, and since the selector
           *   of the CASE evaluates to a constant, examine all the
           *   Gcasesgl items in the case region to see if one is
           *   currently active (Since the selector evaluates to a
           *   constant, either a single Gcasesgl or the Gcaseelse
           *   will be active).  If any  Gcasesgl is active, the Gcaseelse
           *   is not; if no other Gcasesgl is active, the Gcaseelse must be
           *   active.
           *)
          WHILE reg # g.region.instructions DO
            IF reg.info(Lattice) = gTrue THEN
              RETURN gFalse;
            END;
            reg := reg.binst;
          END;
          RETURN gTrue;
        ELSE
          RETURN g.info(Lattice);
        END;
      END;
      RETURN nonconst;
    END Gcaseelse;

  BEGIN
    CASE g.subcl OF
    | GSAOpcode.Gtrue:
      RETURN Gtrue(g);
    | GSAOpcode.Gfalse:
      RETURN Gfalse(g);
    | GSAOpcode.Gcasesgl:
      RETURN Gcasesgl(g);
    | GSAOpcode.Gcaseelse:
      RETURN Gcaseelse(g);
    END;
  END LatticeOfGuard;

  PROCEDURE LatticeOfCase(g : GSAData.Case) : Lattice;
    VAR
      selector : GSAData.Operand;
      lattice : Lattice;
      i : INTEGER;
      classified : BOOLEAN; (* unclassified flag *)
      case : GSAData.Instruction;
  BEGIN
    IF (g.info # unclassified) THEN
      (* This CASE element statement has been classified. *)
      RETURN g.info(Lattice);
    ELSE
      selector := GSAData.OperandNth(0, g);
      lattice := selector.def.info(Lattice);
      IF lattice = nonconst THEN
        IF dfCaseProgress IN diagnostics THEN
          Config.LogWLn;
          GSANames.WDecode(g);
          Config.LogWStr(' nonconst');
        END;
        RETURN nonconst;
      ELSIF lattice.state = csConst THEN
        (* The CASE selector is constant.
         *
         * inv: instructions are initially linked into the worklist
         *      in the order in which they appear in the global region.
         *
         * The first time through this code, the selector value can be
         * determined to be const, but the case regions will be
         * indeterminate.  Following this, all regions in the case region
         * will be visited by the worklist processing portion of the
         * algorithm - which sets the lattice value for each item.
         *
         * The second time through this code, the lattice value will be set.
         *)
        i := 0;
        classified := TRUE;
        case := g.instructions.finst;
        WHILE classified & (case # g.instructions) DO
          IF case IS GSAData.Guard THEN
            lattice := case.info(Lattice);
            classified := lattice # unclassified;
            IF lattice = gTrue THEN
              IF dfCaseProgress IN diagnostics THEN
                Config.LogWLn;
                GSANames.WDecode(g);
                Config.LogW(' ');
                Config.LogWStr(' region-');
                Config.LogWNum(i, 0);
              END;
              RETURN OperandLattice(i);
            ELSIF lattice = gFalse THEN
              (* This section of the case cannot be reached. *)
              RETURN gFalse;
            END;
            INC(i);
          END;
          case := case.finst;
        END;

        IF dfCaseProgress IN diagnostics THEN
          Config.LogWLn;
          GSANames.WDecode(g);
          Config.LogWStr(' classified: ');
          Config.LogWBool(classified);
          Config.LogWStr('  ');
          Config.LogWNum(i, 5);
          Config.LogWLn;
        END;
        ASSERT(~classified, 1102);
        RETURN unclassified;
      ELSE
        IF dfCaseProgress IN diagnostics THEN
          Config.LogWLn;
          GSANames.WDecode(g);
          Config.LogWStr(' unchanged');
        END;
        RETURN g.info(Lattice); (* g.info IN {unclassified, nonconst, unreachable} *)
      END;
    END;
  END LatticeOfCase;

  PROCEDURE LatticeOfMerge(g : GSAData.Merge) : Lattice;

    PROCEDURE Gif(g : GSAData.Merge) : Lattice;
      VAR
        op : GSAData.Operand;
        l0, l1 : Lattice;
    BEGIN
      op := GSAData.OperandNth(0, g);
      l0 := op.def.info(Lattice);
      op := GSAData.OperandNth(1, g);
      l1 := op.def.info(Lattice);

      IF l0 = unclassified THEN
        IF (l1 = unclassified) OR (l1 = gFalse) THEN
          RETURN unclassified;
        ELSE
          (* inv: (l1 = gTrue) OR (l1 = nonconst) *)
          (* inv: l1 = gTrue -> l0 = gFalse *)
          (* inv: l1 = nonconst -> gate = nonconst *)
          RETURN OperandLattice(1);
        END;
      ELSIF l0 = gFalse THEN
        IF l1 = unclassified THEN
          RETURN unclassified;
        ELSE
          RETURN OperandLattice(1);
        END;
      ELSIF l0 = unreachable THEN
        RETURN OperandLattice(1);
      ELSE
        (* inv: (l0 = gTrue) OR (l0 = nonconst) *)
        (* inv: l0 = gTrue -> l1 = gFalse *)
        (* inv: l0 = nonconst -> gate = nonconst *)
        IF l0 = gTrue THEN
          RETURN OperandLattice(0);
        ELSE
          ASSERT(l0 = nonconst);
          RETURN nonconst;
        END;
      END;
    END Gif;

    PROCEDURE Gcond(g : GSAData.Merge) : Lattice;
      VAR
        op : GSAData.Operand;
        l0, l1 : Lattice;
    BEGIN
      op := GSAData.OperandNth(0, g);
      l0 := op.def.info(Lattice);
      op := GSAData.OperandNth(1, g);
      l1 := op.def.info(Lattice);
      IF (l0 = unclassified) OR (l1 = unclassified) THEN
        RETURN unclassified;
      ELSIF (l0 = gTrue) OR (l1 = gTrue) THEN
        RETURN gTrue;
      ELSIF (l0 = gFalse) & (l1 = gFalse) THEN
        RETURN unreachable;
      ELSE
        RETURN nonconst;
      END;
    END Gcond;

    PROCEDURE Gcase(g : GSAData.Merge) : Lattice;
      VAR
        op : GSAData.Operand;
        lattice : Lattice;
        i : INTEGER;
    BEGIN
      i := 0;
      op := GSAData.OperandNth(0, g);
      (* inv: op <-> first region being merged *)

      WHILE op # g.operands DO
        lattice := op.def.info(Lattice);
        IF lattice = unclassified THEN
          RETURN unclassified;
        ELSIF lattice = nonconst THEN
          RETURN nonconst;
        ELSIF lattice = gTrue THEN
          IF dfCaseProgress IN diagnostics THEN
            Config.LogWLn;
            GSANames.WDecode(g);
            Config.LogWStr(' merge operand-');
            Config.LogWNum(i, 0);
          END;
          RETURN OperandLattice(i);
        END;
        op := op.fop;
        INC(i);
      END;
      RETURN g.info(Lattice);
    END Gcase;

    PROCEDURE Gloop(g : GSAData.Merge) : Lattice;
      VAR
        op : GSAData.Operand;
    BEGIN
      op := GSAData.OperandNth(1, g);
      IF op.def.info(Lattice) = unclassified THEN
        RETURN unclassified;
      ELSE
        RETURN nonconst;
      END;
    END Gloop;

  BEGIN
    CASE g.subcl OF
    | GSAOpcode.Gif:
      RETURN Gif(g);
    | GSAOpcode.Gcond:
      RETURN Gcond(g);
    | GSAOpcode.Gloop:
      RETURN Gloop(g);
    | GSAOpcode.Gcase:
      RETURN Gcase(g);
    END;
  END LatticeOfMerge;

  PROCEDURE LatticeOfInstruction(inst : GSAData.Instruction) : Lattice;
    VAR
    o0, o1 : GSAData.Operand; (* operand 0, 1 *)
    l0, l1 : Lattice;         (* lattice for o0, o1 *)
    c0, c1 : GSAData.Const;
    const : GSAData.Const;    (* constant result *)
  BEGIN
    IF CanFold(inst) OR IsAdr(inst) THEN
      l0 := NIL;
      c0 := NIL;
      o0 := GSAData.OperandNth(0, inst);
      IF o0.def.info # NIL THEN
        l0 := o0.def.info(Lattice);
        c0 := l0.const;
      END;

      l1 := NIL;
      c1 := NIL;
      o1 := GSAData.OperandNth(1, inst);
      IF (o1 # NIL) & (o1.def.info # NIL) THEN
        l1 := o1.def.info(Lattice);
        c1 := l1.const;
      END;
      IF (l0 # NIL) & (l1 # NIL) THEN
        IF (l0.state = csConst) & (l1.state = csConst) THEN
          ASSERT(c0 # NIL, 1024);
          ASSERT(c1 # NIL, 1025);
          const := CalcConstant(inst, c0, c1);
          IF const # NIL THEN
            RETURN ConstLattice(const);
          END;
        ELSIF (l0 = unreachable) OR (l1 = unreachable) THEN
          RETURN unreachable;
        ELSIF (l0 = nonconst) OR (l1 = nonconst) THEN
          RETURN nonconst;
        ELSE
          RETURN unclassified;
        END;
      ELSE
        RETURN nonconst;
      END;
    ELSE
      (* Several instructions cannot be propagated, so they are
       * always non-const. *)
      ASSERT((inst.class = GSAOpcode.Mregion) &
             (inst.subcl IN {GSAOpcode.Mgreg,
                             GSAOpcode.Menter,
                             GSAOpcode.Mexit}), 1026);
      RETURN nonconst;
    END;
  END LatticeOfInstruction;

  PROCEDURE NewLattice(inst : GSAData.Instruction) : Lattice;
  BEGIN
    IF inst.info = unreachable THEN
      RETURN unreachable;
    ELSIF inst.info = nonconst THEN
      RETURN nonconst;
    ELSIF inst IS GSAData.Gate THEN
      RETURN LatticeOfGate(inst(GSAData.Gate));
    ELSIF inst IS GSAData.Merge THEN
      RETURN LatticeOfMerge(inst(GSAData.Merge));
    ELSIF inst IS GSAData.Guard THEN
      RETURN LatticeOfGuard(inst(GSAData.Guard));
    ELSIF inst IS GSAData.Case THEN
      RETURN LatticeOfCase(inst(GSAData.Case));
    ELSE
      RETURN LatticeOfInstruction(inst);
    END;
  END NewLattice;

  PROCEDURE ReplaceByConstants(r : GSAData.Region);
    VAR
      inst, n : GSAData.Instruction;
      lattice : Lattice;

    (* ReplaceMergeInstruction: evaluate constant merge
     *
     * Merge 'm' has evaluated to a constant value: operand opnum
     * is the constant value which should be used.
     *
     * For a merge to evaluate to a constant, the conditional which
     * is associated with it must have also evaluated to a constant.
     * The instructions in the unreachable paths will be deleted.
     *)
    PROCEDURE ReplaceMergeInst(m : GSAData.Merge; opnum : INTEGER);
      VAR
        inst : GSAData.Instruction;
        op : GSAData.Operand;

    BEGIN
      inst := m.instructions.finst;
      WHILE inst # m.instructions DO
        op := GSAData.OperandNth(1 + opnum, inst);
        GSAData.UseReplace(inst, op.def);
        inst := inst.finst;
      END;
      GSAData.InstructionDelete(m);
    END ReplaceMergeInst;

    (* ReplaceCondMerge: evaluate a constant conditional merge
     *
     * Conditional merge 'm' has evaluated to 'gTrue'.  This causes all the
     * instructions in 'm' to be always executed.
     * Replace uses of constant instructions with the constant value and then
     * move all remaining instructions to the region containing the merge.
     *)
    PROCEDURE ReplaceCondMergeInst(m : GSAData.Merge);
      VAR
        inst : GSAData.Instruction;
    BEGIN
      ReplaceByConstants(m);
      IF m.instructions.finst # m.instructions THEN
        GSAData.MergeMoveBody(m);
      END;
      GSAData.InstructionDelete(m);
    END ReplaceCondMergeInst;

    (* ReplaceLoopMergeInst: evaluate a loop merge
     *
     * Loop merge 'm' has evaluated to 'gTrue'.
     * In this compiler, the loop construct will execute at least once.
     *
     * The $loop-merge instruction has two operands, the loop entry
     * condition and the backedge condition.  The following table
     * shows the meaning of the values:
     *
     *  entry  | backedge  | meaning
     *  -------|-----------|---------------------------
     *  gFalse | gFalse    | internal error
     *  -------|-----------|---------------------------
     *  gFalse | gTrue     | internal error
     *  -------|-----------|---------------------------
     *  gTrue  | gFalse    | loop executes only once
     *         |           |
     *         |           | Uses of gates inside the $loop-merge
     *         |           | are replaced with the first second operand
     *         |           | of the gate.
     *         |           |
     *         |           | Uses of gates outside the $loop-merge
     *         |           | are replaced with the third operand
     *         |           | of the gate.
     *         |           |
     *         |           | Instructions remaining in the loop can be moved
     *         |           | immediately prior to the loop.  The loop can be
     *         |           | deleted.
     *  -------|-----------|---------------------------
     *  gTrue  | gTrue     | infinite loop
     *  -------|-----------|---------------------------
     *
     * Since the loop must execute at least once, the first parameter
     * will always be TRUE, even though the second parameter may not
     * be a constant value.
     *)
    PROCEDURE ReplaceLoopMergeInst(m : GSAData.Merge);
      VAR
        op : GSAData.Operand;
        def : GSAData.Usable;
        n, inst : GSAData.Instruction;
    BEGIN
      ReplaceByConstants(m);
      (* inv: loops always entered; first parm must be TRUE *)
      op := GSAData.OperandNth(0, m); (* top edge *)
      ASSERT((op.def IS GSAData.ConstBool) &
             op.def(GSAData.ConstBool).val, 1024);

      op := GSAData.OperandNth(1, m); (* backedge parameter *)
      def := op.def;
      IF def IS GSAData.ConstBool THEN
        IF def(GSAData.ConstBool).val THEN (* infinite loop *)
          (* nop *)
        ELSE (* single iteration loop *)
          loopsimplified := TRUE;
          inst := m.instructions.finst;
          WHILE inst # m.instructions DO
            n := inst.finst;
            WITH inst:GSAData.Gate DO
              op := GSAData.OperandNth(1, inst); (* loop entry value *)
              def := op.def;
              GSAData.UseReplaceInRegion(m, inst, def);
              op := GSAData.OperandNth(2, inst); (* loop entry value *)
              def := op.def;
              GSAData.UseReplace(inst, def);
              GSAData.InstructionDelete(inst);
            ELSE (* nop *)
            END;
            inst := n;
          END;
          (* All Gates uses have been replaced.  Move the remaining loop
           * body to outside the loop and delete the loop *)
          GSAData.MergeMoveBody(m);
          GSAData.InstructionDelete(m);
        END;
      ELSE (* nop; non-constant loop *)
      END;
    END ReplaceLoopMergeInst;

    PROCEDURE ReplaceCaseInst(c : GSAData.Case; opnum : INTEGER);
      VAR
        inst, n : GSAData.Instruction;
        lattice : Lattice;
    BEGIN
      inst := c.instructions.finst;
      WHILE inst # c.instructions DO
        n := inst.finst;
        WITH inst:GSAData.Guard DO
          lattice := inst.info(Lattice);
          IF lattice = gTrue THEN
            GSAData.GuardMoveBody(inst);
            GSAData.InstructionDelete(inst);
          ELSIF lattice = gFalse THEN
            GSAData.InstructionDelete(inst);
          END;
        | inst:GSAData.Merge DO
          ASSERT(inst.subcl = GSAOpcode.Gcase);
          ReplaceMergeInst(inst, opnum);
        END;
        inst := n;
      END;
      GSAData.CaseMoveBody(c);
      GSAData.InstructionDelete(c);
    END ReplaceCaseInst;

  BEGIN
    inst := r.instructions.finst;
    WHILE inst # r.instructions DO
      lattice := inst.info(Lattice);

      ASSERT(lattice # unclassified);
      IF dfReplaceByConst IN diagnostics THEN
        GSANames.WDecode(inst);
        Config.LogWStr(' lattice: ');
        outlattice(lattice);
        Config.LogWLn;
      END;
      IF lattice = unreachable THEN
        n := inst.finst;
        GSAData.InstructionDelete(inst);
      ELSE
        WITH inst:GSAData.Merge DO
          n := inst.finst;
          CASE inst.subcl OF
          | GSAOpcode.Gif, GSAOpcode.Gcase:
            IF lattice.state = csOperand THEN
              ReplaceMergeInst(inst, lattice.op);
            END;

          | GSAOpcode.Gcond:
            IF lattice = gTrue THEN
              ReplaceCondMergeInst(inst);
            END;

          | GSAOpcode.Gloop:
            ReplaceLoopMergeInst(inst);
          END;

        | inst:GSAData.Guard DO
          IF lattice = gTrue THEN
            IF inst.instructions.finst # inst.instructions THEN
              n := inst.instructions.finst;
              GSAData.GuardMoveBody(inst);
            ELSE
              n := inst.finst;
            END;
            GSAData.InstructionDelete(inst);
          ELSIF (lattice = gFalse) OR (lattice = unreachable) THEN
            n := inst.finst;
            GSAData.InstructionDelete(inst);
          ELSE (* lattice is nonconst *)
            ReplaceByConstants(inst); (* Process guarded region. *)
            n := inst.finst;
          END;

        | inst:GSAData.Case DO
          n := inst.finst;
          IF lattice.state = csOperand THEN
            ReplaceCaseInst(inst, lattice.op);
          END;

        | inst:GSAData.Region DO
          ReplaceByConstants(inst);
          n := inst.finst;

        ELSE
          n := inst.finst;
          IF lattice.state = csConst THEN
            GSAData.UseReplace(inst, lattice.const);
            GSAData.InstructionDelete(inst);
          END;
        END;
      END;
      inst := n;
    END;
  END ReplaceByConstants;

  (* MarkUnreachable: Marks all instructions in a region as unreachable
   *
   * The original region is not marked as unreachable - it should
   * be marked as 'gFalse' by caller.
   *)
  PROCEDURE MarkUnreachable(r : GSAData.Region);
    VAR
      i : GSAData.Instruction;
  BEGIN
    i := r.instructions.finst;
    WHILE i # r.instructions DO
      i.info := unreachable;
      WITH i:GSAData.Region DO
        MarkUnreachable(i);
      ELSE (* nop *)
      END;
      i := i.finst;
    END;
  END MarkUnreachable;

  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    VAR
      inst, next : GSAData.Instruction;
      lattice : Lattice;
      res : GSAData.Result;
  BEGIN
    IF diagnostics # {} THEN
      Config.LogWStr("Constant Propogation");
      Config.LogWLn;
    END;
    NEW(unclassified);
    unclassified.const := NIL;
    unclassified.state := csUnclass;
    unclassified.op := 0;

    NEW(nonconst);
    nonconst.const := NIL;
    nonconst.state := csNonconst;
    nonconst.op := 0;

    NEW(unreachable);
    unreachable.const := NIL;
    unreachable.state := csUnreachable;
    unreachable.op := 0;

    NEW(operands, 2); (* two (left & right) operands are most common;
                       * CASE will allocate more space as needed
                       *)

    gTrue := ConstLattice(GSAData.ConstGetBool(r, TRUE, r.pos));
    gFalse := ConstLattice(GSAData.ConstGetBool(r, FALSE, r.pos));

    REPEAT
      loopsimplified := FALSE;
      GSAData.RegionClearInfo(r);
      GSAData.RegionClearLinks(r); (* clear instruction cia links *)
      GSAData.RegionNumber(r);
      RegionInitLattices(r);
      IF dfDumpLattice IN diagnostics THEN
        dumplattice(r);
      END;
      InitializeWorklist(r);

      WHILE worklist.inlink # worklist DO
        inst := worklist.inlink;
        worklist.inlink := inst.inlink;
        inst.inlink.iplink := worklist;
        inst.iplink := NIL;
        inst.inlink := NIL;

        lattice := NewLattice(inst);
        IF dfProgress IN diagnostics THEN
           IF lattice.state > inst.info(Lattice).state THEN
             Config.LogWStr('old/new: ');
             Config.LogWNum(inst.info(Lattice).state, 0);
             Config.LogWStr(' ');
             Config.LogWNum(lattice.state, 0);
             Config.LogWLn;
           END;
        END;

        ASSERT(lattice.state <= inst.info(Lattice).state, 1103);
        IF lattice.state < inst.info(Lattice).state THEN
          (* state changed.  More fully classified instruction *)

          (* only 1 result is allowed - because there is no way to put
           * a pure result onto the worklist.
           *)
          inst.info := lattice;
          inst.inlink := worklist;
          inst.iplink := worklist.iplink;
          worklist.iplink.inlink := inst;
          worklist.iplink := inst;

          (* Since this instruction has been more fully classified,
           * it is important to revisit all instructions which use
           * the result of this instruction; to do so, they must be
           * added into the worklist.
           *)

          IF (inst IS GSAData.Region) & (inst.info = gFalse) THEN
            MarkUnreachable(inst(GSAData.Region));
          END;
        ELSIF lattice = unclassified THEN
          (* no classification, put back on worklist *)
          inst.inlink := worklist;
          inst.iplink := worklist.iplink;
          worklist.iplink.inlink := inst;
          worklist.iplink := inst;
        END;

        IF dfDumpWorklist IN diagnostics THEN
          dumpworklist;
        END;
      END;
      IF dfDumpLattice IN diagnostics THEN
        dumplattice(r);
      END;

      ReplaceByConstants(r);
    UNTIL loopsimplified = FALSE;
  END Perform;

  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN
    unclassified := NIL;
    nonconst := NIL;
    gFalse := NIL;
    gTrue := NIL;
    unreachable := NIL;
    worklist := NIL;
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
END O3GSAConstPropagate.
