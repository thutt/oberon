MODULE O3GSADump;
  IMPORT
    SYSTEM,
    Types, (* Disagnostic information only *)
    Config := O3Config,
              Console,
    Symtab := O3Symtab,
    GSAData := O3GSAData,
    GSANames := O3GSANames,
    GSAOpcode := O3GSAOpcode;

  CONST
    GraphViz = FALSE;

  TYPE
    Name = ARRAY 15 OF CHAR;

  VAR
    (* node numbering scheme:

      To keep the subnodes in each procedure as static as possible (so
      they will not be affected by changes in other procedures) the following
      node number scheme is used:
    *)
    nofGreg : LONGINT; (* number of global regions encountered *)
    nofNodes : LONGINT; (* node reference counter *)

  VAR
    stdout : Config.File;
    dotout : Config.File;
    indent : INTEGER;

  PROCEDURE ^ Region*(r : GSAData.GlobalRegion);
  PROCEDURE ^ WInstructionList(x : GSAData.Instruction);

  PROCEDURE DotGraphNodeNumber(n : GSAData.Node);
  BEGIN
    Config.WriteCh(dotout, '"');
    Config.WriteStringNum(dotout, n.reg * 1000 + n.ref, 1);
    Config.WriteCh(dotout, '"');
  END DotGraphNodeNumber;

  PROCEDURE DotGraphLabel(VAR class : GSANames.Class;
                          VAR subcl : GSANames.Subclass);

  BEGIN
    Config.WriteString(dotout, ' [label="');
    Config.WriteString(dotout, class);
    Config.WriteCh(dotout, '.');
    Config.WriteString(dotout, subcl);
    Config.WriteString(dotout, '", shape="ellipse"]');
  END DotGraphLabel;

  PROCEDURE DotGraphOpen(r : GSAData.Region);
  BEGIN
    Config.WriteString(dotout, 'digraph "GSA" { ');
    Config.WriteCh(dotout, 0AX);
  END DotGraphOpen;

  PROCEDURE DotGraphClose(r : GSAData.Region);
  BEGIN
    Config.WriteCh(dotout, 0AX);
    Config.WriteString(dotout, '}');
    Config.WriteCh(dotout, 0AX);
  END DotGraphClose;

  PROCEDURE DotGraphNode(inst      : GSAData.Instruction;
                         VAR class : GSANames.Class;
                         VAR subcl : GSANames.Subclass);
    VAR
      op : GSAData.Operand;
  BEGIN
    DotGraphNodeNumber(inst);
    DotGraphLabel(class, subcl);
    Config.WriteCh(dotout, 0AX);

    (* Write out the edges to the operands *)
    op := inst.operands.fop;
    WHILE op # inst.operands DO
      DotGraphNodeNumber(op);
      Config.WriteString(dotout, " -> ");
      DotGraphNodeNumber(inst);
      Config.WriteCh(dotout, 0AX);
      op := op.fop;
    END;
  END DotGraphNode;

  PROCEDURE DotGraphEdge(parent, child: GSAData.Node);
  BEGIN
    Config.WriteString(dotout, 'edge: { sourcename: ');
    DotGraphNodeNumber(parent);
    Config.WriteString(dotout, ' targetname: ');
    DotGraphNodeNumber(child);
    Config.WriteString(dotout, ' }');
    Config.WriteCh(dotout, 0AX);
  END DotGraphEdge;

  PROCEDURE WS(n : ARRAY OF CHAR);
  BEGIN Config.WriteString(stdout, n);
  END WS;

  PROCEDURE WN(n : LONGINT);
  BEGIN Config.WriteStringNum(stdout, n, 1);
  END WN;

  PROCEDURE WH(n : LONGINT);
  BEGIN Config.WriteStringHex(stdout, n);
  END WH;

  PROCEDURE W(ch : CHAR);
  BEGIN Config.WriteCh(stdout, ch);
  END W;

  PROCEDURE NL;
  BEGIN W(0AX);
  END NL;

  PROCEDURE WSet(s : SET);
  BEGIN Config.WriteStringSet(stdout, s);
  END WSet;

  PROCEDURE WLR(x : LONGREAL);
  BEGIN Config.WriteStringLReal(stdout, x, 15);
  END WLR;

  PROCEDURE WR(x : REAL);
  BEGIN Config.WriteStringReal(stdout, x, 9);
  END WR;

  PROCEDURE WBool(x : BOOLEAN);
  BEGIN IF x THEN WS('TRUE'); ELSE WS('FALSE'); END;
  END WBool;

  PROCEDURE WAdr(x : GSAData.Info);
  BEGIN WS('adr=['); WH(SYSTEM.VAL(LONGINT, x)); WS(']');
  END WAdr;

  PROCEDURE WPos(pos : LONGINT);
  BEGIN
    IF FALSE THEN
      WS(' ['); IF pos # GSAData.UndefInfoData THEN WN(pos); ELSE WS('---'); END; WS(']  ');
    ELSE WS('  ');
    END;
  END WPos;

  PROCEDURE WSymName(sym : Symtab.Symbol);
  BEGIN IF sym # NIL THEN WS(sym.name^); ELSE WS('UNDEFINED'); END;
  END WSymName;

  PROCEDURE WSymbol(x : GSAData.Symbol);
  BEGIN WSymName(x.sym);
  END WSymbol;

  PROCEDURE WInstructionType(x : GSAData.Instruction);
  BEGIN (* IF x.type # NIL THEN WN(x.type.form); W(' '); ELSE W('?'); END; *) (* diagnostic only *)
  END WInstructionType;

  PROCEDURE WType(x : GSAData.Type);
   BEGIN IF x.type.sym # NIL THEN WSymName(x.type.sym); ELSE WS('anonymous type'); END;
  END WType;

  PROCEDURE Indent;
    VAR i : INTEGER;
  BEGIN i := 0; WHILE i < indent DO INC(i); W(' '); END;
  END Indent;

  PROCEDURE Label(lab : ARRAY OF CHAR);
  BEGIN Indent; WS(lab); WS(': ');
  END Label;

  PROCEDURE NotOutput(n : GSAData.Info) : BOOLEAN;
  BEGIN
    IF n.ref = GSAData.UndefInfoData THEN RETURN TRUE;
    ELSIF n.ref < 0 THEN n.ref := ABS(n.ref); RETURN TRUE;
    ELSE RETURN FALSE;
    END;
  END NotOutput;

  PROCEDURE NumberNode(x : GSAData.Info);
  BEGIN ASSERT(x.ref = GSAData.UndefInfoData); x.reg := nofGreg; x.ref := nofNodes; INC(nofNodes);
  END NumberNode;

  PROCEDURE ForwardNode(x : GSAData.Info);
  BEGIN x.reg := nofGreg; x.ref := -nofNodes; INC(nofNodes);
  END ForwardNode;

  PROCEDURE NodeNumber(x : GSAData.Info);
  BEGIN WN(x.reg); W('.'); WN(ABS(x.ref)); WS(' ('); WN(x.dfo); W(')');
  END NodeNumber;

  PROCEDURE NodeHeader(x : GSAData.Info);
  BEGIN Indent;
    IF x.ref = GSAData.UndefInfoData THEN NumberNode(x); END;
    NodeNumber(x); WPos(x.pos);
  END NodeHeader;

  PROCEDURE WNodeRef(x : GSAData.Info);
  BEGIN
    IF x.ref = GSAData.UndefInfoData THEN ForwardNode(x); END;
    W('('); WN(x.dfo); W(')');
  END WNodeRef;

  PROCEDURE WRegionRange(r : GSAData.Instruction);
  BEGIN WS('range=['); WN(r.rangeL); WS(', '); WN(r.rangeH); WS(')');
  END WRegionRange;

  PROCEDURE ArithSuffix(x : GSAData.Instruction);
  BEGIN
    IF x.subcl IN {0..5} THEN (* integer opcode *)
      W('.');
      IF ~ODD(x.subcl) THEN W('s'); (* signed *)
      ELSE W('u'); (* unsigned *)
      END;
      CASE x.subcl OF
      | 0..1: W('1');
      | 2..3: W('2');
      | 4..5: W('4');
      END;
    ELSIF x.subcl IN {22..23} THEN (* real opcode *)
      CASE x.subcl OF
      | 22: WS('.r8');
      | 23: WS('.r4');
      END;
    ELSE (* special case; nop for now 1999.06.08 *)
    END;
  END ArithSuffix;

  PROCEDURE Usable(x : GSAData.Usable);
  BEGIN
    IF NotOutput(x) THEN
      NodeHeader(x);
      WITH x:GSAData.Symbol DO WSymbol(x); WS(' ');
      | x:GSAData.Type DO
        IF x.type.sym # NIL THEN WType(x);
        ELSE WS('anonymous type');
        END;
        WS(' ');
      | x:GSAData.Addressable DO
      ELSE (* plain usable *) WS('usable');
      END;
      NL;
    END;
  END Usable;


  PROCEDURE WVReg(x : GSAData.Usable);
  BEGIN
    (* Only print Vreg when it has been assigned. *)
    CASE x.vreg.rkind OF
    | GSAData.VRegInteger:
      IF x.vreg.ireg < Config.RegisterCount THEN
        WS(":%R");              (* Real register. *)
      ELSE
        WS(":%vr");             (* Virtual register. *)
      END;
      WN(x.vreg.ireg);

    | GSAData.VRegReal:
      IF x.vreg.rreg < Config.RegisterCount THEN
        WS(":%F");              (* Real register. *)
      ELSE
        WS(":%vf");             (* Virtual register. *)
      END;
      WN(x.vreg.rreg);
    ELSE (* No virtual register assigned *)
    END;
  END WVReg;


  PROCEDURE WTempVar(x : GSAData.Temporary);
  BEGIN
    CASE x.kind OF
    | GSAData.tfExit: WS('%exit-'); WN(x.num);
    | GSAData.tfReturnFlag: WS('%return-'); WN(x.num);
    | GSAData.tfReturnValue: WS('%result-'); WN(x.num);
    | GSAData.tfArrayLength: WS(x.definedIn.name^); WS('-len-'); WN(x.dim);
    | GSAData.tfRecordTag: WS(x.definedIn.name^); WS('-tag');
    | GSAData.tfDynFrame: WS('dynamic-frame');
    | GSAData.tfMemory: WS('%memory');
    | GSAData.tfNonLocalMem: WS('%nlm');
    ELSE WS('%t'); WN(x.num);
    END;
    WVReg(x);
  END WTempVar;

  PROCEDURE WConst(x : GSAData.Const);
  BEGIN
    WS('const{');
    WITH x:GSAData.ConstInt DO WN(x(GSAData.ConstInt).val);
    | x:GSAData.ConstBool DO WBool(x.val);
    | x:GSAData.ConstSet DO WSet(x.val);
    | x:GSAData.ConstReal DO WR(x.val);
    | x:GSAData.ConstLReal DO WLR(x.val);
    | x:GSAData.ConstIntRange DO
      WS("[");
      WN(x(GSAData.ConstIntRange).lo); WS(".."); WN(x(GSAData.ConstIntRange).hi);
      WS("]");
    | x:GSAData.ConstString DO W('"'); WS(x.val^); W('"');
    END;
    W('}');
    WVReg(x);
  END WConst;

  PROCEDURE WDefinition(x : GSAData.Usable);
  BEGIN
    WITH x:GSAData.Const DO
      WConst(x);

    | x:GSAData.Type DO
      IF x.type.sym # NIL THEN WType(x);
      ELSE WS('anonymous type');
      END;

    | x:GSAData.Temporary DO
      WTempVar(x);

    | x:GSAData.Symbol DO
      WSymbol(x);

    | x:GSAData.Addressable DO (* should be handled by Type & Symbol *)
      ASSERT(FALSE, 1030);

    | x:GSAData.Instruction DO
      WS('result[');
      WNodeRef(x);
      WS(']');

    | x:GSAData.Result DO
      WS('result{');
      WN(GSAData.ResultIndex(x)); WS(' of ');
      WNodeRef(x.owner); WS('}');
    END;
    W(' ');
  END WDefinition;

  PROCEDURE WLocation(x : GSAData.Location);
    VAR var : GSAData.Addressable;
  BEGIN
    WS('[location=');
    WITH x:GSAData.SymLocation DO var := x.var;
      WITH var:GSAData.Temporary DO WTempVar(var);
      | var:GSAData.Symbol DO WSymbol(var(GSAData.Symbol));
      | var:GSAData.Type DO WType(var);
      END;
      CASE x.kind OF
      | GSAData.slSymbol:
      | GSAData.slAddress: WS('/adr');
      END;
    ELSE (* nop *)
    END;
    WS(']');
  END WLocation;

  PROCEDURE WUses(x : GSAData.Usable);
    VAR f, y : GSAData.Operand;
  BEGIN
    WS('uses={');
    y := x.uses.fuses;
    WHILE y # x.uses DO
      WNodeRef(y.owner);
      y := y.fuses;
      IF y # x.uses THEN
        WS(' ');
      END;
    END;
    WS('}');
  END WUses;

  PROCEDURE WOperands(x : GSAData.Instruction);
    VAR y : GSAData.Operand;
  BEGIN
    y := x.operands.fop;
    WHILE y # x.operands DO
      WDefinition(y.def);
      IF y.location # NIL THEN
        WLocation(y.location);
      END;
      y := y.fop;
      IF y # x.operands THEN
        WS(", ");
      END;
    END;
  END WOperands;

  PROCEDURE WAddressable(x : GSAData.Addressable);
  BEGIN
    WITH x:GSAData.Temporary DO WTempVar(x);
    | x:GSAData.Symbol DO WSymbol(x);
    | x:GSAData.Type DO WType(x);
    | x:GSAData.Const DO WConst(x);
    END;
  END WAddressable;


  PROCEDURE WResults(x : GSAData.Instruction);
    VAR
      r : GSAData.Result;
      nofRes : INTEGER;
  BEGIN
    IF x.lhs # NIL THEN
      (*
       * This instruction is the RHS of an assignment.  This special field
       * (x.lhs) is only meant to be used by the visual dumping mechanism
       * and should not be used by the optimizers.
       *)
      WAddressable(x.lhs);
      WS(" := ");
    END;

    (* First element on the list is the instruction itself. *)
    nofRes := 0;
    IF x.results.fres # x.results THEN
      r := x.results.fres;
      IF r # x.results THEN
        WS("[");
        WHILE r # x.results DO
          IF nofRes > 1 THEN
            WS(", ");
          END;
          IF r.location = NIL THEN
            WS("res{");
            WN(nofRes);
            WS("}");
            WVReg(r);
          ELSE
            WLocation(r.location);
          END;
          INC(nofRes);
          r := r.fres;
        END;
        WS("] ");
      END;
    END;
  END WResults;

  PROCEDURE WInstructionFlags(y : GSAData.Instruction);
    VAR
      i     : INTEGER;
      first : BOOLEAN;
      attr  : GSANames.Attribute;
  BEGIN
    WS("flags{");
    i := 0;
    first := TRUE;
    WHILE i <= GSAData.raMaxGlobalAttribute DO
      IF i IN y.attrib THEN
        IF ~first THEN
          WS(", ");
        END;
        GSANames.DecodeAttribute(i, attr);
        WS(attr);
        first := FALSE;
      END;
      INC(i);
    END;
    WS("}");
  END WInstructionFlags;

  PROCEDURE WInstruction(y : GSAData.Instruction);
    VAR
      class : GSANames.Class;
      subcl : GSANames.Subclass;
  BEGIN
    IF NotOutput(y) THEN
      GSANames.Decode(y, class, subcl);
      NodeHeader(y);
      WInstructionType(y);
      WResults(y);
      IF GraphViz THEN
        DotGraphNode(y, class, subcl);
      END;
      CASE y.class OF
      | GSAOpcode.Maccess, GSAOpcode.Mupdate: WS(class); W('-'); WS(subcl); W(' ');
      | GSAOpcode.Mmemory, GSAOpcode.Mregion: WS(subcl); W(' ');
      | GSAOpcode.Abegin..GSAOpcode.Aend - 1: WS(class); W('.'); WS(subcl); W(' ');
      | GSAOpcode.Lbegin..GSAOpcode.Lend - 1: WS(class); W('.'); WS(subcl); W(' ');
      | GSAOpcode.Hbegin..GSAOpcode.Hend - 1: WS(class); W('.'); WS(subcl); W(' ');
      | GSAOpcode.Cbegin..GSAOpcode.Cend - 1:  WS(class); W('.'); WS(subcl); W(' ');
      | GSAOpcode.Sbegin..GSAOpcode.Send - 1: WS(class); W('.'); WS(subcl); W(' ');
      | GSAOpcode.Tbegin..GSAOpcode.Tend - 1: WS(class); W('-'); WS(subcl); W(' ');
      | GSAOpcode.Gbegin..GSAOpcode.Gend - 1: WS(subcl); W(' ');
      | GSAOpcode.Pbegin..GSAOpcode.Pend - 1: WS(subcl); W(' ');
      ELSE
          Config.LogWStr('invalid instruction class: {');
          Config.LogWNum(y.class, 3);
          Config.LogWStr(',  ');
          Config.LogWNum(y.subcl, 3);
          Config.LogWStr('}');
          HALT(9999);
      END;
      WInstructionFlags(y);
      W(' ');
      WOperands(y);
      W(' ');
      WRegionRange(y);
      W(' ');
      WUses(y);
      NL;

      WITH y:GSAData.Region DO
        WInstructionList(y.instructions);
      ELSE (* nop *)
      END;
    ELSE WNodeRef(y);
    END;
  END WInstruction;

  (* x: dummy list head *)
  PROCEDURE WInstructionList(x : GSAData.Instruction);
    VAR y : GSAData.Instruction;
  BEGIN INC(indent); y := x.finst;
    WHILE y # x DO WInstruction(y); y := y.finst; END;
    DEC(indent);
  END WInstructionList;

  PROCEDURE MarkNotOutput(r : GSAData.Region);
    VAR rgn : GSAData.Region; i : GSAData.Instruction;
  BEGIN r.ref := GSAData.UndefInfoData;
    i := r.instructions.finst;
    WHILE i # r.instructions DO
      i.ref := GSAData.UndefInfoData; i := i.finst;
    END;

    rgn := r.regions.freg;
    WHILE rgn # r.regions DO
      MarkNotOutput(rgn); rgn := rgn.freg;
    END;
  END MarkNotOutput;

  (* dump `r' to a previously opened file *)
  PROCEDURE Region*(r : GSAData.GlobalRegion);
    VAR y : GSAData.Region;

  BEGIN MarkNotOutput(r); y := r;
    IF NotOutput(y) THEN
      IF y IS GSAData.GlobalRegion THEN
        nofNodes := 0;
        INC(nofGreg);
      END;
      NodeHeader(y);

      IF y IS GSAData.GlobalRegion THEN
        Label('greg');
        WSymName(y(GSAData.GlobalRegion).proc);
      ELSE
        Label('reg');
      END;
      W(' '); WRegionRange(y); NL; INC(indent);
      IF GraphViz THEN
        DotGraphOpen(r);
      END;
      WInstructionList(y.instructions);
      IF GraphViz THEN
        DotGraphClose(r);
      END;
      DEC(indent);
      NL; NL;
    END;
  END Region;

  PROCEDURE OpenFile*(module, procedure : ARRAY OF CHAR;
                      extension : ARRAY OF CHAR;
                      header : ARRAY OF CHAR);
    VAR name : POINTER TO ARRAY OF CHAR; mlen, plen, elen, vlen : LONGINT;

    PROCEDURE len(VAR s : ARRAY OF CHAR) : LONGINT;
      VAR l, i : LONGINT; ch : CHAR;
    BEGIN
      l := LEN(s);
      i := 0;
      REPEAT
        ch := s[i];
        INC(i);
      UNTIL (ch = 0X) OR (i >= l);
      RETURN i - 1;
    END len;

    PROCEDURE copy(src : ARRAY OF CHAR; VAR dest : ARRAY OF CHAR; dstoffs : LONGINT);
      VAR ch : CHAR; i : LONGINT;
    BEGIN
      i := 0;
      REPEAT
        ch := src[i];
        dest[dstoffs + i] := ch;
        INC(i);
      UNTIL ch = 0X;
    END copy;

  BEGIN
    nofGreg := -1; (* preincremented *)
    nofNodes := 0;
    mlen := len(module);
    plen := len(procedure);
    elen := len(extension);
    vlen := 4; (* .dot *)
    NEW(name, mlen + plen + 1 + elen + vlen + 1);
    copy(module, name^, 0);
    name[mlen] := '.';
    copy(procedure, name^, mlen + 1);
    copy(extension, name^, mlen + 1 + plen);
    Config.CreateBinary(name^, stdout);
    ASSERT(stdout # NIL);
    Config.WriteString(stdout, header);
    Config.WriteCh(stdout, 0AX);
    Config.WriteCh(stdout, 0AX);
    indent := 0;

    IF GraphViz THEN
      copy('.dot', name^, mlen + 1 + plen + elen);
      Config.CreateBinary(name^, dotout);
      ASSERT(dotout # NIL);
    END;
  END OpenFile;

  PROCEDURE CloseFile*;
  BEGIN
    Config.Register(stdout);
    IF GraphViz THEN
      Config.Register(dotout);
    END;
    stdout := NIL;
    dotout := NIL;
  END CloseFile;
END O3GSADump.
