(* Copyright (c) 1999-2026 Logic Magicians Software *)
MODULE O3MGSA; (* Perform rewriting (AST -> GSA), improvements and codegen *)
  IMPORT
    Types,
    Config:=O3Config,
    E:=O3Errors,
    Symtab:=O3Symtab,
    AST := O3TreeNode,
    GSAData := O3GSAData,
    GSANames := O3GSANames,
    GSAOpcode := O3GSAOpcode,
    GSACI := O3GSAImprove;

(* Notes:
   FEG: 'front end guarantees'
*)

  CONST
    asADDRESS = GSAOpcode.asU4; (* address size; prevents changing lots
                                 * of asU4 when doing 64-bit *)
  CONST
    dfProgress = 0;
    diagnostics = { };

  CONST (* Attributes flags *)
    afExited = 0;
    afReturned = 1;

  CONST (* CombineAttributes: attributes kinds *)
    akNormal = 0;
    akLoop = 1;

  TYPE
    Attributes = RECORD
      x : GSAData.Item;
      exit : GSAData.Temporary;
      returned : GSAData.Temporary;
      resultval : GSAData.Temporary; (* actual function result *)
      flags : SET;
    END;

  VAR
    (* current procedure being processed;
     * used for establishing ownership of
     * compiler-generated temporaries
     *)
    CurrentProcedure : Symtab.Symbol;

  PROCEDURE ^ GSAAssign(r : GSAData.Region;
                        lhs : GSAData.Usable;
                        rhs : GSAData.Result;
                    VAR x : GSAData.Item);
  PROCEDURE ^ Design(r : GSAData.Region;
                     n : AST.Design;
                 VAR x : GSAData.Item);
  PROCEDURE ^ Expr(r : GSAData.Region; n : AST.Expr; VAR x : GSAData.Item);

  PROCEDURE ^ Trap(r : GSAData.Region;
                   subcl : SHORTINT;
                   pos : LONGINT;
                   cond : GSAData.Item);

  PROCEDURE ^ GetSymbol(r : GSAData.Region;
                        sym : Symtab.Symbol;
                        pos : LONGINT) : GSAData.Addressable;

  PROCEDURE printtype(node : GSAData.Node);
    VAR
      n : Types.Name;
  BEGIN
    Types.NameOf(Types.TypeOf(node), n);
    Config.LogWStr("type name = '");
    Config.LogWStr(n^);
    Config.LogWStr("'");
    Config.LogWLn;
  END printtype;

  PROCEDURE Fatal(n : INTEGER);
  BEGIN
    Config.LogWLn;
    Config.LogWStr('fatal internal error ');
    Config.LogWNum(n, 1);
    Config.LogWLn;
    HALT(1024);
  END Fatal;

  PROCEDURE InitAttributes(VAR attr : Attributes);
  BEGIN
    GSAData.InitItem(attr.x);
    attr.exit := NIL;
    attr.flags := {};
    attr.returned := NIL;
    attr.resultval := NIL;
  END InitAttributes;

  (* CombineAttributes: combines attributes from
   *                    differently-scoped regions
   *
   * Given two sets of attributes, this procedure produces
   * a set-wise union of the attributes
   *)
  PROCEDURE CombineAttributes(kind : SHORTINT;
                          VAR lhs : Attributes;
                              rhs : Attributes);
  BEGIN
    lhs.flags := lhs.flags + rhs.flags;
    CASE kind OF
    | akLoop: (* EXIT does not synthesize out of LOOP *)
      lhs.flags := lhs.flags * (-{afExited});
    | akNormal: (* nop *)
    END;
  END CombineAttributes;

  PROCEDURE MergeOpenControlRegion(m : GSAData.Merge;
                                   r : GSAData.Region;
                                   attr : Attributes;
                                   VAR regionAttr : Attributes);
  BEGIN
    GSAData.MergeOpenControlRegion(m, r);
    regionAttr := attr;
  END MergeOpenControlRegion;

  (* ArithmeticSubclass: returns the opcode (arithmetic) subclass
   *                     of a Symtab.Type
   *
   * pre: type # NIL & defined(type^) & type.form IN {arithmetic types}
   * post: result IN {GSAOpcode.[arithmetic subclasses]
   *)
  PROCEDURE ArithmeticSubclass(type : Symtab.Type) : SHORTINT;
    VAR
      subcl : SHORTINT;
  BEGIN
    CASE type.form OF
    | Symtab.bool, Symtab.byte, Symtab.char:
      subcl := GSAOpcode.asU1; (* 1 byte unsigned *)

    | Symtab.sint:
      subcl := GSAOpcode.asS1;

    | Symtab.int:
      subcl := GSAOpcode.asS2;

    | Symtab.lint:
      subcl := GSAOpcode.asS4;

    | Symtab.real:
      subcl := GSAOpcode.asR4;

    | Symtab.lreal:
      subcl := GSAOpcode.asR8;

    | Symtab.set:
      subcl := GSAOpcode.asU4;

    | Symtab.pointer, Symtab.procedure:
      subcl := asADDRESS;

    | Symtab.array, Symtab.openarr, Symtab.dynarr:
      ASSERT(type(Symtab.Array).of.form = Symtab.char); (* FEG *)
      subcl := GSAOpcode.asST;

    | Symtab.string:
      subcl := GSAOpcode.asST;

    ELSE
      Config.LogWStr('ArithmeticSubClass: invalid subclass (');
      Config.LogWNum(type.form, 0);
      Config.LogW(')');
      Config.LogWLn;
      HALT(1024);
    END;
    RETURN subcl;
  END ArithmeticSubclass;

  PROCEDURE CompleteItem(node : GSAData.Usable; VAR x : GSAData.Item);
  BEGIN
    x.type := node.type;
    x.node := node;
  END CompleteItem;

  (* StoreGetVar: get %nlm variable *)
  PROCEDURE StoreGetVar(r : GSAData.Region) : GSAData.Temporary;
    VAR
      enter : GSAData.Instruction;
      found : BOOLEAN;
      op : GSAData.Operand;
      def : GSAData.Usable;
  BEGIN
    enter := GSAData.InstructionEnter(r);
    op := enter.operands.fop;
    found := FALSE;
    WHILE (op # enter.operands) & ~found DO
      def := op.def;
      WITH def:GSAData.Temporary DO
        found := def.kind = GSAData.tfNonLocalMem;
      ELSE (* nop *)
      END;
      IF ~found THEN
        op := op.fop;
      END;
    END;

    IF found THEN
      RETURN op.def(GSAData.Temporary);
    ELSE
      RETURN NIL;
    END;
  END StoreGetVar;

  (* EnterResultAppend: append a Result to the 'enter' instruction
   *
   * All results added to the enter instruction will
   * have their 'sym location' set to themselves so that
   * finding array length parameters can function properly
   * (see Len())
   *
   * Global, non-local and var parameters will also have their addresses
   * added to the list.
   *
   * post: op.currvalue := $result
   *)
  PROCEDURE EnterResultAppend(e : GSAData.Instruction; op : GSAData.Addressable);
    VAR
      x : GSAData.Result;
      loc : GSAData.Location;
  BEGIN
    ASSERT((e.class = GSAOpcode.Mregion) & (e.subcl = GSAOpcode.Menter));
    loc := GSAData.NewSymLocation(GSAData.slSymbol, op, op.pos);
    x := GSAData.ResultAppend(e, loc, op.type);
    op.currvalue := x;
  END EnterResultAppend;

  PROCEDURE EnterResultAppendAddr(e : GSAData.Instruction; op : GSAData.Addressable);
    VAR
      x : GSAData.Result;
      loc : GSAData.Location;
  BEGIN
    ASSERT((e.class = GSAOpcode.Mregion) & (e.subcl = GSAOpcode.Menter));
    loc := GSAData.NewSymLocation(GSAData.slAddress, op, op.pos);
    x := GSAData.ResultAppend(e, loc, op.type);
  END EnterResultAppendAddr;

  (* EnterResultAdd: add a new item to the end of the $enter Result list *)
  PROCEDURE EnterResultAdd(r : GSAData.Region; a : GSAData.Symbol);
    VAR
      level : SHORTINT;
      greg  : GSAData.GlobalRegion;
      enter : GSAData.Instruction;
  BEGIN
    IF a.currvalue = NIL THEN
      CASE a.sym.kind OF
      | Symtab.var, Symtab.par, Symtab.varpar,
        Symtab.darrdesc, Symtab.arrdesc, Symtab.recdesc:
        (* A Symbol in the program is being used as an RValue, but it has
         * not yet been assigned a value.  It is an error for a local
         * variable to have not been assigned a value.
         *
         * Non-local symbols
         *
         * When a global variable is found to be used before it is
         * assigned a value, the value actually is implicit as coming from
         * the $enter instruction.  If that is the case, it should be
         * appended to the result list of $enter.
         *)
        greg := GSAData.RegionFindGlobal(r);
        level := greg.proc.mnolev;
        enter := GSAData.InstructionEnter(greg);

        IF (a.sym.mnolev <= 0) THEN  (* global symbol *)
          EnterResultAppend(enter, a);
          EnterResultAppendAddr(enter, a);
        ELSIF (a.sym.mnolev < level + 1) THEN
          (* non-local; nested procedure levels are the same as variables
           * of the enclosing scope.  Variables of procedures have a
           * scoping level 1 level greater than the procedure.
           *)
          EnterResultAppend(enter, a);
          EnterResultAppendAddr(enter, a);
        ELSE
          (* inv: local variables are initialized through Mdecl nodes, so
           *      if one is not initialized (it's currvalue field is NIL),
           *      then there is an internal problem in the compiler
           *)
          Config.Fatal(-1);
        END;
      ELSE
        a.currvalue := a;
      END;
    END;
  END EnterResultAdd;

  PROCEDURE ExitOperandAppend(i : GSAData.Instruction);
    VAR
      exit : GSAData.Instruction;
  BEGIN
    exit := GSAData.InstructionExit(i.region);
    GSAData.OperandAppend(exit, i);
  END ExitOperandAppend;

  (* StoreGet: gets %nlm associated with 'r' *)
  PROCEDURE StoreGet(r : GSAData.Region) : GSAData.Result;
    VAR
      enter, inst : GSAData.Instruction;
      store : GSAData.Temporary;
      greg : GSAData.GlobalRegion;
      rhs : GSAData.Item;
      result : GSAData.Result;
  BEGIN
    (* When a %create is not found on the operand list of $enter,
     * it means that no $nlmctor has been issued for the region
     * for 'r'.  $nlmctor must be issued and assigned to a
     * created %nlm.
     *
     * When a %create operand is found, the current value
     * should be returned.
     *)
    store := StoreGetVar(r);

    IF store = NIL THEN
      enter := GSAData.InstructionEnter(r);
      greg := GSAData.RegionFindGlobal(r);
      store := GSAData.NewTemporaryNonLocalMem(r, greg.proc, r.pos);
      inst := GSAData.NewInstruction(GSAOpcode.Pnlm, GSAOpcode.Pctor,
                                     Symtab.linttyp, r.pos);
      GSAData.InstructionAppend(r, inst);
      CompleteItem(inst, rhs);
      GSAData.AssignToVariable(r, store, rhs);
      GSAData.OperandAppend(enter, store);
      result := inst;
    ELSE
      result := store.currvalue(GSAData.Result);
    END;
    RETURN result;
  END StoreGet;

  (* StoreDelete: append $nlmdtor to 'r' and as an operand of $exit *)
  PROCEDURE StoreDelete(r : GSAData.Region);
    VAR
      inst : GSAData.Instruction;
      exit : GSAData.Instruction;
      store : GSAData.Result;
  BEGIN
    store := StoreGet(r);
    inst := GSAData.NewInstruction(GSAOpcode.Pnlm, GSAOpcode.Pdtor,
                                   Symtab.linttyp, r.pos);
    GSAData.InstructionAppend(r, inst);
    GSAData.OperandAppend(inst, store);
    INCL(inst.attrib, GSAData.raLive);
    ExitOperandAppend(inst); (* Link %nlm dtor to $exit. *)
  END StoreDelete;

  (* AddressOf: takes the address of 'x'
   * pre: (r # NIL) & (r <-> region into which the
   *                          address instruction will be inserted
   * pre: defined(x)
   * pre: pos >= 0
   * post: result <-> adr instruction
   * post: result will have been appened to 'r'
   *)
  PROCEDURE AddressOf(r : GSAData.Region;
                      x : GSAData.Item;
                      pos : LONGINT) : GSAData.Result;
    VAR
      adr : GSAData.Instruction;
  BEGIN
    adr := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Madr,
                                  x.type, pos);
    GSAData.OperandAppend(adr, x.node);
    GSAData.InstructionAppend(r, adr);
    RETURN adr;
  END AddressOf;

  (* NilCheck: test n # NIL: return conditional merge
   * The conditional merge corresponds to the 'nil-check' region
   * and is intended to be used to place a `trap' instruction.
   *)
  PROCEDURE NilCheck(r : GSAData.Region; n : GSAData.Item);
    VAR
      neq      : GSAData.Instruction;
      neqTrue  : GSAData.Region;
      neqFalse : GSAData.Region;
      m        : GSAData.CondMerge;
      x        : GSAData.Item;
  BEGIN
    neq := GSAData.NewInstruction(GSAOpcode.Cneq, GSAOpcode.asU1,
                                  Symtab.booltyp, n.node.pos);
    (* If 'n' is an addressable symbol, get the current value.
     * Otherwise, 'n' is the Result of an instruction that computed
     * the current value.
     *)
    IF n.node IS GSAData.Addressable THEN
      n.node := n.node(GSAData.Addressable).currvalue;
    ELSE
      ASSERT(n.node IS GSAData.Result);
    END;
    GSAData.OperandAppend(neq, n.node);
    GSAData.OperandAppend(neq, GSAData.ConstGetNil(r, n.node.pos));
    GSAData.InstructionAppend(r, neq);
    CompleteItem(neq, x);

    Trap(r, GSAOpcode.Tnil, n.node.pos, x);
  END NilCheck;

  PROCEDURE Deref(r : GSAData.Region;
                  base : GSAData.Item;
                  pos : LONGINT) : GSAData.Instruction;
    VAR
      deref : GSAData.Instruction;
      store, adr : GSAData.Result;
      cond : GSAData.Item;

  BEGIN
    (* If base is a Symbol, then the current value of the symbol should
     * be used (it is the deepest deref in the designator tree).
     * If, however, base is not a Symbol, then it is a field or an element
     * which have been accessed through the current value of some symbol
     * and therefore the instruction is the current value.
     *)

    NilCheck(r, base);
    adr := AddressOf(r, base, pos);
    store := StoreGet(r);
    deref := GSAData.NewInstruction(GSAOpcode.Maccess, GSAOpcode.Mderef,
                                    base.type(Symtab.Pointer).to, pos);
    IF base.node IS GSAData.Symbol THEN
      GSAData.OperandAppend(deref, base.node(GSAData.Symbol).currvalue);
    ELSE
      GSAData.OperandAppend(deref, base.node);
    END;

    GSAData.OperandAppend(deref, adr);
    GSAData.OperandAppend(deref, store);
    GSAData.InstructionAppend(r, deref);
    RETURN deref;
  END Deref;

  PROCEDURE MakeDeref(r : GSAData.Region;
                      base : GSAData.Item;
                      pos : LONGINT;
                      VAR x : GSAData.Item);
  BEGIN
    CompleteItem(Deref(r, base, pos), x);
  END MakeDeref;

  PROCEDURE MakeTDNode(r : GSAData.Region;
                       type : Symtab.Type;
                       pos : LONGINT;
                       VAR td : GSAData.Item);
    VAR
      besym : GSAData.Addressable;
  BEGIN
    ASSERT(Symtab.HasTD(type), 1024);
    besym := GetSymbol(r, Symtab.GetTD(NIL, type), pos);
    EnterResultAdd(r, besym(GSAData.Symbol));
    CompleteItem(besym.currvalue, td);
  END MakeTDNode;

  (* GetTypeTag: given a variable `var', return its type tag in `tag'
   *)
  PROCEDURE GetTypeTag(r : GSAData.Region;
                       var : GSAData.Item;
                       pos : LONGINT;
                       VAR tag : GSAData.Item);
    VAR
      enter, t : GSAData.Instruction;
      deref : GSAData.Item;
      res : GSAData.Result;
      op : GSAData.Operand;
  BEGIN
    IF var.type.form = Symtab.pointer THEN (* need to deref to get tag *)
      MakeDeref(r, var, pos, deref);
      t := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mheaptag,
                                  Symtab.sysptrtyp, pos);
      GSAData.OperandAppend(t, var.node);
      GSAData.OperandAppend(t, deref.node);
      GSAData.InstructionAppend(r, t);
      CompleteItem(t, tag);
    ELSE (* var parm *)
      enter := GSAData.InstructionEnter(r);
      ASSERT(var.node IS GSAData.Instruction);
      op := GSAData.OperandFirst(var.node(GSAData.Instruction)); (* {Maccess,Mvarparm} *)
      ASSERT(op # NIL);
      ASSERT(op.def IS GSAData.Symbol);
      res := GSAData.ResultFind(enter, op.def(GSAData.Symbol), GSAData.slSymbol);

      (* type descriptor address follows type descriptor which follows
       * symbol address, which follows the symbol on $enter results
       *)
      CompleteItem(res.fres.fres.fres, tag);
    END;
  END GetTypeTag;

  (* RangeOrdinal: test `n' IN [low..high): return conditional merge
   * The conditional merge corresponds to the `out-of-range' region
   * and is intended to be used to place a `trap' instruction.
   *)
  PROCEDURE RangeOrdinal(r : GSAData.Region;
                         n : GSAData.Item;
                         low, high : GSAData.Usable) : GSAData.CondMerge;
    VAR
      geq, lss : GSAData.Instruction;
      m : GSAData.CondMerge;
      x : GSAData.Item;
      geqTrue, geqFalse, lssTrue, lssFalse : GSAData.Region;
  BEGIN
    m := GSAData.NewCondMerge(low.pos);
    geq := GSAData.NewInstruction(GSAOpcode.Cgeq, ArithmeticSubclass(low.type),
                                  Symtab.linttyp, low.pos);
    GSAData.OperandAppend(geq, n.node);
    GSAData.OperandAppend(geq, low);
    GSAData.InstructionAppend(r, geq);
    CompleteItem(geq, x);
    GSAData.SplitPaths(r, x, low.pos, geqTrue, geqFalse);

    lss := GSAData.NewInstruction(GSAOpcode.Clss, ArithmeticSubclass(Symtab.linttyp),
                                  Symtab.linttyp, low.pos);
    GSAData.OperandAppend(lss, n.node);
    GSAData.OperandAppend(lss, high);
    GSAData.InstructionAppend(geqTrue, lss);

    CompleteItem(lss, x);
    GSAData.SplitPaths(geqTrue, x, low.pos, lssTrue, lssFalse);
    GSAData.OperandAppend(m, geqFalse);
    GSAData.OperandAppend(m, lssFalse);

    GSAData.CondMergeSetPaths(m, geqTrue, m);
    GSAData.InstructionAppend(r, m);
    RETURN m;
  END RangeOrdinal;

  (* Trap: insert trap `subcl' into the specificed trap into `r' based on
   *       conditional `cond'.
   *)
  PROCEDURE Trap(r : GSAData.Region;
                 subcl : SHORTINT;
                 pos : LONGINT;
                 cond : GSAData.Item);
    VAR
      merge : GSAData.Merge;
      true, false : GSAData.Region;
      trap : GSAData.Instruction;
      attr : Attributes;
  BEGIN
    InitAttributes(attr);
    GSAData.SplitControlPath(r, cond, pos, true, false, merge);
    MergeOpenControlRegion(merge, true, attr, attr);
    MergeOpenControlRegion(merge, false, attr, attr);
    trap := GSAData.NewInstruction(GSAOpcode.Ttrap, subcl, Symtab.notyp, pos);
    INCL(trap.attrib, GSAData.raLive);
    INCL(true.attrib, GSAData.raLive);
    INCL(false.attrib, GSAData.raLive);
    INCL(merge.attrib, GSAData.raLive);
    GSAData.InstructionAppend(false, trap);
    GSAData.MergeCommit(merge, r);
  END Trap;

  (* GetSymbol: return a backend symbol from the given
   *            frontend symbol, `sym'
   *
   * If `sym' is not associated with a backend
   * symbol, create one.  The symbol (GSAData.Symbol) will
   * be returned.  It is not suitable to use this value as
   * an rvalue (only as an lvalue).  Use RValue() to create an
   * rvalue.
   *)
  PROCEDURE GetSymbol(r : GSAData.Region;
                      sym : Symtab.Symbol;
                      pos : LONGINT) : GSAData.Addressable;
    VAR
      s : GSAData.Addressable;
  BEGIN
    IF sym.bedata = NIL THEN
      s := GSAData.NewSymbol(r, sym, Symtab.SymbolOwner(sym), pos);
      sym.bedata := GSAData.NewBEData();
      GSAData.SymbolSetNode(sym, s);
    ELSE
      s := sym.bedata(GSAData.BEData).node;
    END;
    RETURN s;
  END GetSymbol;

  PROCEDURE ConstGetValue(r : GSAData.Region;
                          val : Symtab.Const;
                          pos : LONGINT;
                          VAR x : GSAData.Item);
    VAR
      node : GSAData.Const;
  BEGIN
    CASE val.type.form OF
    | Symtab.bool: node := GSAData.ConstGetBool(r, val.bool, pos);
    | Symtab.char, Symtab.sint, Symtab.int,
      Symtab.lint: node := GSAData.ConstGetInt(r, val.i0,val.type, pos);
    | Symtab.real: node := GSAData.ConstGetReal(r, SHORT(val.real), pos);
    | Symtab.lreal: node := GSAData.ConstGetLReal(r, val.real, pos);
    | Symtab.set: node := GSAData.ConstGetSet(r, val.set, pos);
    | Symtab.string: node := GSAData.ConstGetString(r, val.ext, pos);
    | Symtab.nil: node := GSAData.ConstGetNil(r, pos);
    END;
    CompleteItem(node, x);
  END ConstGetValue;

  (* GetArrayLength: return LEN(arr, dim) *)
  PROCEDURE GetArrayLength(r : GSAData.Region;
                           arr : GSAData.Usable;
                           dim : GSAData.ConstInt;
                           pos : LONGINT) : GSAData.Usable;
  VAR
    len : GSAData.Instruction;
    op : GSAData.Operand;
    offset : GSAData.Const;
    result : GSAData.Usable;
    f : LONGINT;
    elType : Symtab.Type;

    PROCEDURE DimensionLength(a : Symtab.Type; dim, pos : LONGINT) : GSAData.Const;
    BEGIN
      WHILE dim > 0 DO
        a := a(Symtab.Array).of;
        DEC(dim);
      END;
      RETURN GSAData.ConstGetInt(r, a(Symtab.Array).n, Symtab.linttyp, pos);
    END DimensionLength;

    PROCEDURE ParmDimensionLength(r : GSAData.Region;
                                  var : GSAData.Symbol;
                                  dim : LONGINT) : GSAData.Result;
      VAR
        res : GSAData.Result;
    BEGIN
      res := GSAData.ResultFind(GSAData.InstructionEnter(r), var, GSAData.slSymbol);

      IF var.sym.kind = Symtab.varpar THEN
        res := res.fres;
        (* inv: res <-> varparm address *)
      END;

      res := res.fres;
      (* inv: res <-> dimension-0 value *)

      WHILE dim > 0 DO
        res := res.fres;
        DEC(dim);
      END;
      RETURN res;
    END ParmDimensionLength;

  BEGIN
    WITH arr:GSAData.Instruction DO
      IF arr.class = GSAOpcode.Maccess THEN
        CASE arr.subcl OF
        | GSAOpcode.Mvarparm: (* open array *)
          op := GSAData.OperandFirst(arr); (* {Maccess,Mvarparm} *)
          ASSERT(op # NIL);
          ASSERT(op.def IS GSAData.Symbol);
          result := ParmDimensionLength(r, op.def(GSAData.Symbol), dim.val);

        | GSAOpcode.Mderef: (* dynamic array *)
          elType := arr.type; (* FIXME(twh): fe cannot perform arr.type(Symtab.Array)
                               * as formal parm*)
          ASSERT(elType IS Symtab.Array);
          elType := Symtab.ElemType(elType(Symtab.Array));
          f := Symtab.linttyp.size; (* size of a field in the type descriptor *)

          CASE elType.form OF
          | Symtab.bool, Symtab.byte, Symtab.char,
            Symtab.sint, Symtab.int, Symtab.lint,
            Symtab.real, Symtab.lreal, Symtab.set, Symtab.procedure: (* dynarr0 *)
            offset := GSAData.ConstGetInt(r, f * (2 + dim.val), Symtab.linttyp, r.pos);

          | Symtab.pointer: (* dynarr1 *)
            offset := GSAData.ConstGetInt(r, f * (5 + dim.val), Symtab.linttyp, r.pos);

          | Symtab.record: (* dynarr2 *)
            offset := GSAData.ConstGetInt(r, f * (6 + dim.val), Symtab.linttyp, r.pos);

          | Symtab.array:
            WHILE elType.form = Symtab.array DO
              elType := elType(Symtab.Array).of;
            END;
            CASE elType.form OF
            | Symtab.bool, Symtab.byte, Symtab.char,
              Symtab.sint, Symtab.int, Symtab.lint,
              Symtab.real, Symtab.lreal, Symtab.set, Symtab.procedure: (* dynarr3 *)
              offset := GSAData.ConstGetInt(r, f * (2 + dim.val), Symtab.linttyp, r.pos);

            | Symtab.pointer: (* dynarr4 *)
              offset := GSAData.ConstGetInt(r, f * (6 + dim.val), Symtab.linttyp, r.pos);

            | Symtab.record: (* dynarr5 *)
              offset := GSAData.ConstGetInt(r, f * (6 + dim.val), Symtab.linttyp, r.pos);
            END;
          END;
          (* inv: offset <-> offset into array block for the array dimension length *)

          len := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mdynarrlen,
                                        Symtab.linttyp, pos);
          GSAData.OperandAppend(len, arr);
          GSAData.OperandAppend(len, dim);
          GSAData.OperandAppend(len, offset);
          GSAData.InstructionAppend(r, len);
          result := len;
        ELSE (* statically sized array *)
          (* it is not allowed to take array length through $mem *)
          ASSERT(arr.subcl IN {GSAOpcode.Mfield, GSAOpcode.Melement, GSAOpcode.Mnonlocal});
          result := DimensionLength(arr.type, dim.val, r.pos);
        END;
      ELSE
        Config.Fatal(-3);
      END;

    | arr:GSAData.Symbol DO (* statically sized or by-value open array parameter *)
      IF arr.sym.kind = Symtab.var THEN
        result := DimensionLength(arr.type, dim.val, r.pos);
      ELSE
        ASSERT(arr.sym.kind = Symtab.par, 1099);
        result := ParmDimensionLength(r, arr, dim.val);
      END;
    END;
    ASSERT((result IS GSAData.Result) OR (result IS GSAData.Const), 1100);
    RETURN result;
  END GetArrayLength;

  PROCEDURE Convert(r : GSAData.Region;
                    class : SHORTINT;
                    to : Symtab.Type;
                    n : GSAData.Usable;
                    pos : LONGINT) : GSAData.Usable;
    VAR
      inst : GSAData.Instruction;
      as0, as1 : SHORTINT;
  (* XXX There is a defect here in the original (oc) oberon compiler: if the
   * as0 and as1 variables are removed and the function calls placed in
   * the if statement, the result is always true *)
  BEGIN
    as0 := ArithmeticSubclass(to);
    as1 := ArithmeticSubclass(n.type);
    IF as0 # as1 THEN
      inst := GSAData.NewInstruction(class, ArithmeticSubclass(to), to, pos);
      GSAData.OperandAppend(inst, n);
      GSAData.InstructionAppend(r, inst);
      RETURN inst;
    ELSE
      RETURN n;
    END;
  END Convert;

  PROCEDURE Design(r : GSAData.Region;
                   n : AST.Design;
                   VAR x : GSAData.Item);

    PROCEDURE Symbol(r : GSAData.Region; n : AST.Design; VAR x : GSAData.Item);
      VAR
        sym : GSAData.Addressable;
        greg : GSAData.GlobalRegion;
        access : GSAData.Instruction;
        store : GSAData.Result;
        addr : GSAData.Result;
    BEGIN
      store := StoreGet(r);
      sym := GetSymbol(r, n.sym, n.pos);
      CompleteItem(sym, x);
      EnterResultAdd(r, sym(GSAData.Symbol));

      (* Local variables are initialized through Mdecl nodes.  Non-local and
       * varparms are initialized through the result list of $enter.  So, every
       * symbol should have a current value.
       *)
      ASSERT(sym.currvalue # NIL);

      IF n.sym.kind = Symtab.var THEN
        greg := GSAData.RegionFindGlobal(r);
        (* nonlocal variable access requires $nonlocal instruction
         * by-reference variables require $varpar instruction
         * local variables do not need an extra access instruction
         *)
        IF (n.sym.mnolev <= 0) OR (n.sym.mnolev < greg.proc.mnolev + 1) THEN
          (* nonlocal variable *)
          CompleteItem(sym, x);
          addr := AddressOf(r, x, sym.pos);
          access := GSAData.NewInstruction(GSAOpcode.Maccess, GSAOpcode.Mnonlocal,
                                           n.type, n.pos);
          GSAData.OperandAppend(access, sym);
          GSAData.OperandAppend(access, addr);
          GSAData.OperandAppend(access, store);
          GSAData.InstructionAppend(r, access);
          CompleteItem(access, x);
        END;
      ELSIF n.sym.kind = Symtab.varpar THEN
        (* by-reference parameter *)
          CompleteItem(sym, x);
          addr := AddressOf(r, x, sym.pos);
          access := GSAData.NewInstruction(GSAOpcode.Maccess, GSAOpcode.Mvarparm,
                                           n.type, n.pos);
          GSAData.OperandAppend(access, sym);
          GSAData.OperandAppend(access, addr);
          GSAData.OperandAppend(access, store);
          GSAData.InstructionAppend(r, access);
          CompleteItem(access, x);
      END;
    END Symbol;

    PROCEDURE Method(r : GSAData.Region; n : AST.Field; VAR x : GSAData.Item);
      VAR
        method : GSAData.Addressable;
    BEGIN
      method := GetSymbol(r, n.sym, n.pos);
      CompleteItem(method, x);
    END Method;

    PROCEDURE Field(r : GSAData.Region; n : AST.Field; VAR x : GSAData.Item);
      VAR
        y : GSAData.Item;
        add, access : GSAData.Instruction;
        adr : GSAData.Result;
        offs : GSAData.Const;

    BEGIN
      Design(r, n.base, y);
      (* inv: y is the record base
       * produces:
       * 1 add adr-y, offset-field
       * 2 field y, 1, offset-field
       *)
      offs := GSAData.ConstGetInt(r, n.sym.adr, Symtab.linttyp, n.pos);
      adr := AddressOf(r, y, n.pos);

      add := GSAData.NewInstruction(GSAOpcode.Aadd, asADDRESS,
                                    Symtab.sysptrtyp, n.pos);
      GSAData.OperandAppend(add, adr);
      GSAData.OperandAppend(add, offs);
      GSAData.InstructionAppend(r, add);

      access := GSAData.NewInstruction(GSAOpcode.Maccess, GSAOpcode.Mfield,
                                       n.type, n.pos);
      GSAData.OperandAppend(access, y.node);
      GSAData.OperandAppend(access, add);
      GSAData.OperandAppend(access, offs);
      GSAData.InstructionAppend(r, access);
      CompleteItem(access, x);
    END Field;

    PROCEDURE Index(r : GSAData.Region; n : AST.Index; VAR x : GSAData.Item);
      VAR
        var, base, index, cond : GSAData.Item;
        elSize : GSAData.Const;
        design : AST.Design;
        trap, add, offs, access : GSAData.Instruction;
        len : GSAData.Usable;
        m : GSAData.CondMerge;
        adr : GSAData.Result;
        dim : LONGINT;
        dimension : GSAData.Const;

      PROCEDURE DesignOfIndex(d : AST.Design; VAR dim : LONGINT; VAR dsgn : AST.Design);
        VAR
          i : LONGINT;
      BEGIN
        i := 0;
        WHILE d IS AST.Index DO
          INC(i);
          d := d(AST.Index).base;
        END;
        dsgn := d;
        dim := i;
      END DesignOfIndex;

    BEGIN
      Design(r, n.base, base);
      Expr(r, n.index, index);
      DesignOfIndex(n.base, dim, design);
      Design(r, design, var);

      dimension := GSAData.ConstGetInt(r, dim, Symtab.linttyp, n.pos);
      len := GetArrayLength(r, var.node, dimension(GSAData.ConstInt), n.pos);
      index.node := Convert(r, GSAOpcode.Aconvert, Symtab.linttyp, index.node, n.pos);
      m := RangeOrdinal(r, index,
                        GSAData.ConstGetInt(r, 0, Symtab.linttyp, n.index.pos),
                        len);

      CompleteItem(m, cond);
      Trap(r, GSAOpcode.Tindex, n.index.pos, cond);

      adr := AddressOf(r, base, n.base.pos);
      elSize := GSAData.ConstGetInt(r, n.base.type(Symtab.Array).of.size,
                                    Symtab.linttyp, n.base.pos);
      offs := GSAData.NewInstruction(GSAOpcode.Amul,
                                     ArithmeticSubclass(Symtab.linttyp),
                                     Symtab.linttyp, n.index.pos);
      GSAData.OperandAppend(offs, index.node);
      GSAData.OperandAppend(offs, Convert(r, GSAOpcode.Aconvert, Symtab.linttyp, elSize, n.pos));
      GSAData.InstructionAppend(r, offs);

      add := GSAData.NewInstruction(GSAOpcode.Aadd, asADDRESS,
                                    Symtab.sysptrtyp, n.index.pos);
      GSAData.OperandAppend(add, adr);
      GSAData.OperandAppend(add, Convert(r, GSAOpcode.Aconvert, Symtab.sysptrtyp, offs, n.pos));
      GSAData.InstructionAppend(r, add);

      access := GSAData.NewInstruction(GSAOpcode.Maccess, GSAOpcode.Melement,
                                       n.type, n.pos);
      GSAData.OperandAppend(access, base.node);
      GSAData.OperandAppend(access, add);
      GSAData.OperandAppend(access, index.node);
      GSAData.InstructionAppend(r, access);
      CompleteItem(access, x);
    END Index;

    PROCEDURE Deref(r : GSAData.Region; n : AST.Deref; VAR x : GSAData.Item);
      VAR
        base : GSAData.Item;
    BEGIN
      Design(r, n.base, base);
      MakeDeref(r, base, n.pos, x);
    END Deref;

    (* ImplicitGuard: implicit type guard
     * This is induced for assignments to VAR-parm records to ensure the assigned
     * record does not violate the type of the assignee.
     *)
    PROCEDURE ImplicitGuard(r : GSAData.Region; n : AST.Guard;
                            VAR x : GSAData.Item);
      VAR
        c, g : GSAData.Instruction;
        tag, td, cond, var : GSAData.Item;
      type : GSAData.Type;
      merge : GSAData.Merge;
      true, false : GSAData.Region;
      attr : Attributes;
    BEGIN
      InitAttributes(attr);
      Design(r, n.design, var);
      type := GSAData.NewType(n.type, n.type.sym, n.pos);

      GetTypeTag(r, var, n.pos, tag);
      MakeTDNode(r, n.type, n.pos, td);
      c := GSAData.NewInstruction(GSAOpcode.Ceql, asADDRESS, n.type, n.pos);
      GSAData.OperandAppend(c, tag.node);
      GSAData.OperandAppend(c, td.node);
      GSAData.InstructionAppend(r, c);

      CompleteItem(c, cond);
      GSAData.SplitControlPath(r, cond, c.pos, true, false, merge);

      MergeOpenControlRegion(merge, true, attr, attr);
      Design(true, n.design, var); (* recalculate the designator
                                    * to ensure that the test has a 'use'
                                    *)

      MergeOpenControlRegion(merge, false, attr, attr);
      g := GSAData.NewInstruction(GSAOpcode.Ttrap, GSAOpcode.Tiguard,
                                  Symtab.notyp, n.pos);
      INCL(g.attrib, GSAData.raLive);
      INCL(true.attrib, GSAData.raLive);
      INCL(false.attrib, GSAData.raLive);
      INCL(merge.attrib, GSAData.raLive);
      GSAData.InstructionAppend(false, g);
      GSAData.MergeCommit(merge, r);
      CompleteItem(var.node, x);
    END ImplicitGuard;

    PROCEDURE ExplicitGuard(r : GSAData.Region; n : AST.Guard; VAR x : GSAData.Item);
      VAR
        c, g : GSAData.Instruction;
        tag, td, cond, var : GSAData.Item;
        type : GSAData.Type;
        true, false : GSAData.Region;
        attr : Attributes;
        merge : GSAData.Merge;
    BEGIN
      InitAttributes(attr);
      Design(r, n.design, var);
      type := GSAData.NewType(n.type, n.type.sym, n.pos);

      GetTypeTag(r, var, n.pos, tag);
      MakeTDNode(r, n.type, n.pos, td);
      c := GSAData.NewInstruction(GSAOpcode.Ceql, asADDRESS, n.type, n.pos);
      GSAData.OperandAppend(c, tag.node);
      GSAData.OperandAppend(c, td.node);
      GSAData.InstructionAppend(r, c);

      CompleteItem(c, cond);
      GSAData.SplitControlPath(r, cond, c.pos, true, false, merge);

      (* add operand to Merge region *)
      MergeOpenControlRegion(merge, true, attr, attr);

      (* recalculate the designator to ensure that the test has a 'use' *)
      Design(true, n.design, var);

      (* add operand to Merge region *)
      MergeOpenControlRegion(merge, false, attr, attr);
      g := GSAData.NewInstruction(GSAOpcode.Ttrap, GSAOpcode.Teguard,
                                  Symtab.notyp, n.pos);
      INCL(g.attrib, GSAData.raLive);
      INCL(true.attrib, GSAData.raLive);
      INCL(false.attrib, GSAData.raLive);
      INCL(merge.attrib, GSAData.raLive);
      GSAData.InstructionAppend(false, g);
      GSAData.MergeCommit(merge, r);
      CompleteItem(var.node, x);
    END ExplicitGuard;

  BEGIN
    IF n # NIL THEN
      CASE n.subcl OF
      | AST.Dvar, AST.Dpar, AST.Dvarpar, AST.Dtype, AST.Dproc,
        AST.Drecdesc, AST.Darrdesc, AST.Ddarrdesc: Symbol(r, n, x);
      | AST.Dmethod: Method(r, n(AST.Field), x);
      | AST.Dfield: Field(r, n(AST.Field), x);
      | AST.Dmodule, AST.Dscope: Fatal(10240);
      | AST.Dderef: Deref(r, n(AST.Deref), x);
      | AST.Dindex: Index(r, n(AST.Index), x);
      | AST.Diguard: ImplicitGuard(r, n(AST.Guard), x);
      | AST.Deguard: ExplicitGuard(r, n(AST.Guard), x);
      | AST.Dconst: ConstGetValue(r, n.sym(Symtab.SymbolConst).val, n.pos, x);
      | AST.Dstdproc: Fatal(19999);
      ELSE
        Config.LogWLn;
        Config.LogWStr('Design: invalid subclass <');
        Config.LogWNum(n.subcl, 1);
        Config.LogW('>');
        Fatal(10260);
      END;
    END;
  END Design;

  PROCEDURE RValue(r : GSAData.Region;
                   n : AST.Design;
               VAR x : GSAData.Item);
    VAR
      a : GSAData.Addressable;
  BEGIN
    Design(r, n, x);
    IF x.node IS GSAData.Addressable THEN
      a := x.node(GSAData.Addressable);
      WITH a:GSAData.Symbol DO
        ASSERT(a.currvalue # NIL);
        x.node := a.currvalue;

      | a:GSAData.Const DO  (* nop; current value is itself *)
      END;
    ELSE
      ASSERT(x.node IS GSAData.Result);
      (* a complex desginator, such as a record field
       * or an array access has been used.  Since this is already an
       * Instruction, it suffices nicely as a Result (rvalue).
       * It must be a Result due to the way the type hierarchy & algorithms
       * are designed.
       *)
    END;
  END RValue;

  (* assign to an array, structured, nonlocal or varparm variable
   *
   * The %nlm variable should only be assigned to when the
   * data access is truly non-local.  For example, assigning to a local
   * RECORD variable field should not assign to %nlm.
   *)
  PROCEDURE AssignThruInstruction(r   : GSAData.Region;
                                  lhs : GSAData.Instruction;
                                  rhs : GSAData.Item);
    VAR
      op : GSAData.Operand;
      def : GSAData.Usable;
      greg : GSAData.GlobalRegion;
      store : GSAData.Temporary;
      symloc : GSAData.SymLocation;
      level : SHORTINT;
      nonlocal : BOOLEAN;
      sym : GSAData.Symbol;
  BEGIN
    ASSERT(lhs.class = GSAOpcode.Maccess, 1025);
    ASSERT(lhs.subcl IN {GSAOpcode.Mderef,
                         GSAOpcode.Mfield,
                         GSAOpcode.Melement,
                         GSAOpcode.Mnonlocal,
                         GSAOpcode.Mvarparm}, 1026);
    GSAData.OperandAppend(lhs, rhs.node);
    CompleteItem(lhs, rhs);
    ASSERT(rhs.node IS GSAData.Instruction, 1024);
    GSAData.InstructionAccToUpd(rhs.node(GSAData.Instruction));

    (* When the first operand is not a Result (or extension), it's a direct
     * variable access.  It must be determined if the variable is local or
     * non-localto decide if %nlm should be assigned.
     *)
    op := lhs.operands.fop;
    IF op.def IS GSAData.Result THEN
      nonlocal := TRUE;
    ELSE
      greg := GSAData.RegionFindGlobal(r);
      level := greg.proc.mnolev;
      sym := op.def(GSAData.Symbol);
      nonlocal := (sym.sym.mnolev <= 0) OR
                  (sym.sym.mnolev < level + 1) OR
                  (lhs.subcl IN {GSAOpcode.Mderef,
                                 GSAOpcode.Mnonlocal,
                                 GSAOpcode.Mvarparm});
    END;
    IF nonlocal THEN
      store := StoreGetVar(r);
      GSAData.AssignToVariable(r, store, rhs);
    END;
  END AssignThruInstruction;

  PROCEDURE GSAAssign(r : GSAData.Region;
                      lhs : GSAData.Usable;
                      rhs : GSAData.Result;
                  VAR x : GSAData.Item);
  BEGIN
    CompleteItem(rhs, x);
    WITH lhs:GSAData.Symbol DO
      GSAData.AssignToVariable(r, lhs, x);

    | lhs:GSAData.Instruction DO
      AssignThruInstruction(r, lhs, x);
  END;
  END GSAAssign;

  PROCEDURE Misc(r : GSAData.Region; n : AST.Node; VAR x : GSAData.Item);

    PROCEDURE InitTD(r : GSAData.Region; n : AST.InitTD);
      VAR
        inst : GSAData.Instruction;
        x : GSAData.Item;
        subcl : SHORTINT;
        td : GSAData.Symbol;
        tdtype : GSAData.Type;
    BEGIN
      (* Type Descriptor initialization will only occur in the module
       * initialization code.  Since type descriptors _must_ be initialized,
       * mark all instructions as always live.
       *)
      GSAData.InitItem(x);
      td := GSAData.NewSymbol(r, n.td, n.td, n.pos);
      tdtype := GSAData.NewType(n.td.described, n.td.described.sym, n.pos);

      CASE n.td.kind OF
      | Symtab.recdesc: subcl := GSAOpcode.Ginitrec;
      | Symtab.arrdesc: subcl := GSAOpcode.Ginitarr;
      | Symtab.darrdesc:  subcl := GSAOpcode.Ginitdarr;
      END;
      inst := GSAData.NewInstruction(GSAOpcode.Gtypedesc, subcl, n.type, n.pos);
      INCL(inst.attrib, GSAData.raLive); (* TD initializers cannot be removed *)
      GSAData.OperandAppend(inst, tdtype);
      GSAData.InstructionAppend(r, inst);
      CompleteItem(inst, x);
      GSAData.AssignToVariable(r, td, x);
    END InitTD;

    PROCEDURE Decl(n : AST.Declaration);
      VAR
        c : GSAData.Const;
        s : GSAData.Addressable;
        addr, rhs : GSAData.Item;
        inst : GSAData.Instruction;
    BEGIN (* inv: Mdecl only at procedure level -> r IS GlobalRegion *)
      (* A symbol appearing in a Mdecl node is a variable, type or constant *)
      IF n.sym.kind = Symtab.var THEN
        s := GetSymbol(r, n.sym, r.pos);
        ASSERT(s # NIL);
        CASE s.type.form OF
        | Symtab.bool:
          c := GSAData.ConstGetBool(r, FALSE, r.pos);

        | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint:
          c := GSAData.ConstGetInt(r, 0, n.sym.type, r.pos);

        | Symtab.real:
          c := GSAData.ConstGetReal(r, 0, r.pos);

        | Symtab.lreal:
          c := GSAData.ConstGetLReal(r, 0, r.pos);

        | Symtab.set:
          c := GSAData.ConstGetSet(r, {}, r.pos);

        | Symtab.pointer, Symtab.procedure:
          c := GSAData.ConstGetNil(r, 0);

        | Symtab.array, Symtab.record:
          c := NIL; (* uses $initialize *)

        | Symtab.openarr, Symtab.dynarr, Symtab.string: (* nop; not possible for local variable *)
        ELSE
          Config.Fatal(-1); (* unhandled variable type *)
        END;

        (* inv: c = NIL -> use $initialize *)
        IF c # NIL THEN
          CompleteItem(c, rhs);
        ELSE
          CompleteItem(s, addr);
          inst := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Minitialize, s.type, r.pos);
          GSAData.OperandAppend(inst, s);
          GSAData.OperandAppend(inst, AddressOf(r, addr, r.pos));
          GSAData.OperandAppend(inst, GSAData.ConstGetInt(r, s.type.size, Symtab.linttyp, r.pos));
          GSAData.InstructionAppend(r, inst);

          IF Symtab.modinit IN r(GSAData.GlobalRegion).proc.flags THEN
            INCL(inst.attrib, GSAData.raLive);
          END;
          CompleteItem(inst, rhs);
        END;

        GSAData.AssignToVariable(r, s, rhs);
      END;
    END Decl;

    PROCEDURE Import(n : AST.Import);
      VAR
        inst : GSAData.Instruction;
        x : GSAData.Item;
        mod : GSAData.Symbol;
    BEGIN
      GSAData.InitItem(x);
      mod := GSAData.NewSymbol(r, n.module, n.module, n.pos);
      inst := GSAData.NewInstruction(GSAOpcode.Pmisc, GSAOpcode.Pimport, n.type,
                                     n.pos);
      INCL(inst.attrib, GSAData.raLive); (* imports cannot be removed *)
      GSAData.OperandAppend(inst, mod);
      GSAData.InstructionAppend(r, inst);
    END Import;

  BEGIN
    IF n # NIL THEN
      ASSERT(n.class = AST.Nmisc);
      CASE n.subcl OF
      | AST.Mdecl: Decl(n(AST.Declaration));
      | AST.Minittd: InitTD(r, n(AST.InitTD));
      | AST.Mimport: Import(n(AST.Import));
      END;
    END;
  END Misc;

  PROCEDURE MiscList(r : GSAData.Region; n : AST.Node; VAR x : GSAData.Item);
  BEGIN
    WHILE n # NIL DO
      Misc(r, n, x);
      n := n.next;
    END;
  END MiscList;

  PROCEDURE TypeTest(r : GSAData.Region;
                     pos : LONGINT;
                     var, type : GSAData.Item;
                     VAR x : GSAData.Item);
    VAR
      test : GSAData.Instruction;
      tag, vmt : GSAData.Item;
  BEGIN
    GetTypeTag(r, var, pos, tag);
    MakeTDNode(r, type.type, pos, vmt); (* VMT-pointer variable *)

    test := GSAData.NewInstruction(GSAOpcode.Ceql, asADDRESS,
                                   Symtab.sysptrtyp, pos);
    GSAData.OperandAppend(test, tag.node);
    GSAData.OperandAppend(test, vmt.node);
    GSAData.InstructionAppend(r, test);
    CompleteItem(test, x);
  END TypeTest;

  PROCEDURE UnaryMinus(r : GSAData.Region;
                       class : SHORTINT;
                       op : GSAData.Usable;
                       type : Symtab.Type;
                       pos : LONGINT;
                       VAR x : GSAData.Item);
    VAR
      inst : GSAData.Instruction;
  BEGIN
    inst := GSAData.NewInstruction(class, ArithmeticSubclass(type),
                                   type, pos);
    GSAData.OperandAppend(inst, op);
    GSAData.InstructionAppend(r, inst);
    CompleteItem(inst, x);
  END UnaryMinus;


  PROCEDURE Expr(r : GSAData.Region; n : AST.Expr; VAR x : GSAData.Item);

    PROCEDURE MExpr(n : AST.MExpr; VAR x : GSAData.Item);
      VAR
        y : GSAData.Item;
        inst : GSAData.Instruction;
        class : SHORTINT;
        address : GSAData.Result;
        u : GSAData.Usable;
    BEGIN
      Expr(r, n.op, y);
      CASE n.subcl OF
      | AST.Enot: (* negate boolean expression *)
        inst := GSAData.NewInstruction(GSAOpcode.Anot,
                                       ArithmeticSubclass(Symtab.booltyp),
                                       n.type, n.pos);
        GSAData.OperandAppend(inst, y.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);

      | AST.Euminus: (* unary minus *)
        IF n.type.form IN Symtab.NumSet THEN
          class := GSAOpcode.Aneg;
        ELSE
          class := GSAOpcode.Sneg;
        END;
        UnaryMinus(r, class, y.node(GSAData.Usable), n.type, n.pos, x);

      | AST.Euplus: (* unary plus (aka NOP) *) x := y;

      | AST.Econvert: (* checked conversion *)
        IF n.type.form = Symtab.set THEN
          class := GSAOpcode.Sconvert;
        ELSE
          class := GSAOpcode.Aconvert;
        END;
        u := Convert(r, class, n.type, y.node, n.pos);
        CompleteItem(u(GSAData.Instruction), x);

      | AST.Ecast: (* unchecked conversion *)
        x := y;
        x.type := n.type;

      | AST.Eadr:
        CompleteItem(y.node, x);
        address := AddressOf(r, x, n.pos);
        CompleteItem(address, x);
      END;
    END MExpr;

    PROCEDURE DExpr(n : AST.DExpr; VAR x : GSAData.Item);
      VAR
        lop, rop : GSAData.Item;
        class, subcl : SHORTINT;

      PROCEDURE CreateInstruction(class, subcl : SHORTINT;
                                  lop, rop : GSAData.Item;
                              VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
      BEGIN
        inst := GSAData.NewInstruction(class, subcl, n.type, n.pos);
        GSAData.OperandAppend(inst, lop.node);
        GSAData.OperandAppend(inst, rop.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END CreateInstruction;

      PROCEDURE Compare(r     : GSAData.Region;
                        n     : AST.DExpr;
                        class : SHORTINT;
                        VAR x : GSAData.Item);
        VAR
          lop, rop : GSAData.Item;
      BEGIN
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        CreateInstruction(class, ArithmeticSubclass(n.lop.type), lop, rop, x);
      END Compare;

      PROCEDURE And(r : GSAData.Region; n : AST.DExpr; VAR x : GSAData.Item);
        VAR
          m : GSAData.CondMerge;
          lhs, rhs : GSAData.Item;
          tlhs, flhs, trhs, frhs: GSAData.Region;
      BEGIN (* Conditional & *)
        (* The cmerge node is the merge of the false-paths
         * from both the left- and right-hand conditions.
         * The false-path out of the & node is the cmerge.
         * The true-path out of the & node is the true path
         * of the right-hand condition
         *)
        m := GSAData.NewCondMerge(n.pos);
        Expr(r, n.lop, lhs);
        GSAData.SplitPaths(r, lhs, n.lop.pos, tlhs, flhs);

        Expr(tlhs, n.rop, rhs);
        GSAData.SplitPaths(tlhs, rhs, n.rop.pos, trhs, frhs);

        GSAData.OperandAppend(m, flhs);
        GSAData.OperandAppend(m, frhs);

        GSAData.CondMergeSetPaths(m, trhs, m);
        GSAData.InstructionAppend(r, m);
        CompleteItem(m, x);
      END And;

      PROCEDURE Or(r : GSAData.Region;
                   n : AST.DExpr;
               VAR x : GSAData.Item);
        VAR
          m : GSAData.CondMerge;
          lhs, rhs : GSAData.Item;
          tlhs, flhs, trhs, frhs: GSAData.Region;
      BEGIN (* Conditional OR *)
        (* The cmerge node is the merge of the true-paths from
         * both the left- and right-hand conditions.
         * The true-path out of the OR node is the cmerge.
         * The false-path out of the OR node is the false path of
         * the right-hand condition (the region where subsequent
         * instructions should be placed)
         *)
        m := GSAData.NewCondMerge(n.pos);
        Expr(r, n.lop, lhs);
        GSAData.SplitPaths(r, lhs, n.lop.pos, tlhs, flhs);

        Expr(flhs, n.rop, rhs);
        GSAData.SplitPaths(flhs, rhs, n.rop.pos, trhs, frhs);

        GSAData.OperandAppend(m, tlhs);
        GSAData.OperandAppend(m, trhs);

        GSAData.CondMergeSetPaths(m, m, frhs);
        GSAData.InstructionAppend(r, m);
        CompleteItem(m, x);
      END Or;

    BEGIN
      CASE n.subcl OF
      | AST.Etimes:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        IF n.type.form IN Symtab.NumSet THEN
          class := GSAOpcode.Amul;
        ELSE
          class := GSAOpcode.Sintersection;
        END;
        CreateInstruction(class, ArithmeticSubclass(n.type), lop, rop, x);

      | AST.Ediv:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        CreateInstruction(GSAOpcode.Adiv, ArithmeticSubclass(n.type),
                          lop, rop, x);

      | AST.Eslash:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        IF n.type.form IN Symtab.NumSet THEN
          class := GSAOpcode.Adiv;
        ELSE
          class := GSAOpcode.Sdiff;
        END;
        CreateInstruction(class, ArithmeticSubclass(n.type), lop, rop, x);

      | AST.Emod:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        class := GSAOpcode.Amod;
        subcl := ArithmeticSubclass(n.type);
        CreateInstruction(class, ArithmeticSubclass(n.type), lop, rop, x);

      | AST.Eplus:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        IF n.type.form IN Symtab.NumSet THEN
          class := GSAOpcode.Aadd;
        ELSE
          class := GSAOpcode.Sunion;
        END;
        CreateInstruction(class, ArithmeticSubclass(n.type), lop, rop, x);

      | AST.Eminus:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        IF n.type.form IN Symtab.NumSet THEN
          class := GSAOpcode.Asub;
        ELSE
          class := GSAOpcode.Ssub;
        END;
        CreateInstruction(class, ArithmeticSubclass(n.type), lop, rop, x);

      | AST.Eand:
        And(r, n, x);

      | AST.Eor:
        Or(r, n, x);

      | AST.Eeql:
        Compare(r, n, GSAOpcode.Ceql, x);

      | AST.Eneq:
        Compare(r, n, GSAOpcode.Cneq, x);

      | AST.Elss:
        Compare(r, n, GSAOpcode.Clss, x);

      | AST.Eleq:
        Compare(r, n, GSAOpcode.Cleq, x);

      | AST.Egtr:
        Compare(r, n, GSAOpcode.Cgtr, x);

      | AST.Egeq:
        Compare(r, n, GSAOpcode.Cgeq, x);

      | AST.Ein:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        CreateInstruction(GSAOpcode.Selement, ArithmeticSubclass(n.type),
                          lop, rop, x);

      | AST.Eupto:
        Expr(r, n.lop, lop);
        Expr(r, n.rop, rop);
        CreateInstruction(GSAOpcode.Srange, ArithmeticSubclass(n.type),
                          lop, rop, x);

      | AST.Eis: Fatal(10260); (* handled by IsTest() *)

      | AST.Ecall: Fatal(10270); (* handled by FuncCall & ProcCall *)
      END;
    END DExpr;

    PROCEDURE IsTest(n : AST.IsTest; VAR x : GSAData.Item);
      VAR
        var, type : GSAData.Item;
    BEGIN (* synthesize: typetest <var>, <type> *)
      RValue(r, n.var, var);
      RValue(r, n.istype, type);
      TypeTest(r, n.pos, var, type, x);
    END IsTest;

    PROCEDURE StandardProcedure(r : GSAData.Region;
                                proc : SHORTINT;
                                rtype : Symtab.Type; (* procedure result type *)
                                args : AST.Arg;
                                VAR x : GSAData.Item);

      PROCEDURE Len(r : GSAData.Region;
                    arr : AST.Design;
                    dimension : AST.Expr;
                    pos : LONGINT;
                    VAR x : GSAData.Item);
        VAR
          design, dim : GSAData.Item;
          len : GSAData.Usable;
      BEGIN
        Design(r, arr, design);
        Expr(r, dimension, dim);
        len := GetArrayLength(r, design.node, dim.node(GSAData.ConstInt), pos);
        CompleteItem(len, x);
      END Len;

      PROCEDURE Abs(r : GSAData.Region;
                    e : AST.Expr;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, e, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Aabs, ArithmeticSubclass(expr.type),
                                       expr.type, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Abs;

      PROCEDURE Cap(r : GSAData.Region;
                    e : AST.Expr;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, e, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Gmisc, GSAOpcode.Gcap,
                                       Symtab.chartyp, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Cap;

      PROCEDURE Odd(r : GSAData.Region;
                    e : AST.Expr;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, e, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Aodd,
                                       ArithmeticSubclass(expr.type),
                                       Symtab.booltyp, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Odd;

      PROCEDURE Shift(r : GSAData.Region;
                      sl, sr : SHORTINT;
                      lhs, rhs : AST.Expr;
                      pos : LONGINT;
                  VAR x : GSAData.Item);
        VAR
          cmp : GSAData.Instruction;
          neg, lop, rop : GSAData.Item;
          shiftLeft, shiftRight : GSAData.Region;
          shiftMerge : GSAData.Merge;
          shiftAttr : Attributes;
          temp : GSAData.Temporary;
          greg : GSAData.GlobalRegion;

        PROCEDURE Emit(r : GSAData.Region; class : SHORTINT; rop : GSAData.Item);
          VAR
            inst : GSAData.Instruction;
            x : GSAData.Item;
        BEGIN
          inst := GSAData.NewInstruction(class, ArithmeticSubclass(lop.type),
                                         Symtab.linttyp, pos);
          GSAData.OperandAppend(inst, lop.node);
          GSAData.OperandAppend(inst, rop.node);
          GSAData.InstructionAppend(r, inst);
          CompleteItem(inst, x);
          GSAData.AssignToVariable(r, temp, x);
        END Emit;

      BEGIN
        InitAttributes(shiftAttr);
        greg := GSAData.RegionFindGlobal(r);
        Expr(r, lhs, lop);
        Expr(r, rhs, rop);
        (* shift lop by rop.
           rop < 0 -> shift right
           rop >= 0 -> shift left
        *)
        temp := GSAData.NewTemporary(r, Symtab.linttyp, greg.proc, pos);

        cmp := GSAData.NewInstruction(GSAOpcode.Clss, ArithmeticSubclass(rhs.type),
                                      Symtab.booltyp, pos);
        GSAData.OperandAppend(cmp, rop.node);
        GSAData.OperandAppend(cmp, GSAData.ConstGetInt(r, 0, rhs.type, pos));
        GSAData.InstructionAppend(r, cmp);

        CompleteItem(cmp, x);
        GSAData.SplitControlPath(r, x, pos, shiftRight, shiftLeft, shiftMerge);

        MergeOpenControlRegion(shiftMerge, shiftRight, shiftAttr, shiftAttr);
        UnaryMinus(shiftRight, GSAOpcode.Aneg,
                   rop.node(GSAData.Usable), rop.type, pos, neg);
        Emit(shiftRight, sr, neg);

        GSAData.MergeReset(shiftMerge);

        MergeOpenControlRegion(shiftMerge, shiftLeft, shiftAttr, shiftAttr);
        Emit(shiftLeft, sl, rop);

        GSAData.MergeCommit(shiftMerge, r);
        CompleteItem(temp.currvalue, x);
      END Shift;

      PROCEDURE New(r : GSAData.Region;
                    tdsym : AST.Design;
                    dim : AST.Node;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          td, d : GSAData.Item;
          inst : GSAData.Instruction;
          described : Symtab.Type;
      BEGIN
        Design(r, tdsym, td);
        described := tdsym.sym(Symtab.SymbolTypeDesc).described;
        CASE tdsym.sym.kind OF
        | Symtab.recdesc:
          inst := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mnewrecord,
                                         described, pos);
          GSAData.OperandAppend(inst, td.node);
          GSAData.InstructionAppend(r, inst);
          INCL(inst.attrib, GSAData.raUniqueResult);
          CompleteItem(inst, x);

        | Symtab.arrdesc:
          inst := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mnewarray,
                                         described, pos);
          GSAData.OperandAppend(inst, td.node);
          GSAData.InstructionAppend(r, inst);
          INCL(inst.attrib, GSAData.raUniqueResult);
          CompleteItem(inst, x);

        | Symtab.darrdesc:
          inst := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mnewdynarray,
                                         described, pos);
          GSAData.OperandAppend(inst, td.node);
          WHILE dim # NIL DO
            Expr(r, dim(AST.Arg).arg(AST.Expr), d);
            GSAData.OperandAppend(inst, d.node);
            dim := dim.next;
          END;
          GSAData.InstructionAppend(r, inst);
          INCL(inst.attrib, GSAData.raUniqueResult);
          CompleteItem(inst, x);
        END;
      END New;

      PROCEDURE Min(r : GSAData.Region;
                    type : Symtab.Type;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          c : GSAData.Const;
          f : SHORTINT;
      BEGIN
        f := type.form;
        CASE f OF
        | Symtab.bool:
          c := GSAData.ConstGetBool(r,
                                    Symtab.metrics[f](Symtab.BoolMetric).min,
                                    pos);

        | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint, Symtab.set:
          c := GSAData.ConstGetInt(r, Symtab.metrics[f](Symtab.OrdMetric).min,
                                   type, pos);

        | Symtab.real:
          c := GSAData.ConstGetReal(r, Symtab.metrics[f](Symtab.RealMetric).min, pos);

        | Symtab.lreal:
          c := GSAData.ConstGetLReal(r, Symtab.metrics[f](Symtab.LRealMetric).min, pos);
        END;
        CompleteItem(c, x);
      END Min;

      PROCEDURE Max(r : GSAData.Region;
                    type : Symtab.Type;
                    pos : LONGINT;
                VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          c : GSAData.Const;
          f : SHORTINT;
      BEGIN
        f := type.form;
        CASE f OF
        | Symtab.bool:
          c := GSAData.ConstGetBool(r, Symtab.metrics[f](Symtab.BoolMetric).max, pos);

        | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint, Symtab.set:
          c := GSAData.ConstGetInt(r, Symtab.metrics[f](Symtab.OrdMetric).max,
                                   type, pos);

        | Symtab.real:
          c := GSAData.ConstGetReal(r, Symtab.metrics[f](Symtab.RealMetric).max, pos);

        | Symtab.lreal:
          c := GSAData.ConstGetLReal(r, Symtab.metrics[f](Symtab.LRealMetric).max, pos);
        END;
        CompleteItem(c, x);
      END Max;

      PROCEDURE Size(r : GSAData.Region;
                     dest, type : Symtab.Type;
                     pos : LONGINT;
                 VAR x : GSAData.Item);
        VAR
          c : GSAData.Const;
      BEGIN
        c := GSAData.ConstGetInt(r, type.size, dest, pos);
        CompleteItem(c, x);
      END Size;

      PROCEDURE Incl(r : GSAData.Region;
                     set : AST.Design;
                     e : AST.Expr;
                     pos : LONGINT;
                 VAR x : GSAData.Item);
        VAR
          rvalue, design, expr : GSAData.Item;
          union, bit : GSAData.Instruction;
      BEGIN
        RValue(r, set, rvalue);
        Design(r, set, design);
        Expr(r, e, expr);
        union := GSAData.NewInstruction(GSAOpcode.Sincl, GSAOpcode.asU4,
                                        Symtab.settyp, pos);
        GSAData.OperandAppend(union, rvalue.node);
        GSAData.OperandAppend(union, expr.node);
        GSAData.InstructionAppend(r, union);
        GSAAssign(r, design.node(GSAData.Usable), union, x);
        CompleteItem(union, x);
      END Incl;

      PROCEDURE Excl(r : GSAData.Region;
                     set : AST.Design;
                     e : AST.Expr;
                     pos : LONGINT;
                     VAR x : GSAData.Item);
        VAR
          design, expr : GSAData.Item;
          inst : GSAData.Instruction;
      BEGIN
        Design(r, set, design);
        Expr(r, e, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Sexcl, GSAOpcode.asU4,
                                       Symtab.settyp, pos);
        GSAData.OperandAppend(inst, design.node);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Excl;

      PROCEDURE Adr(r : GSAData.Region;
                    d : AST.Design;
                    pos : LONGINT;
                    VAR x : GSAData.Item);
        VAR
          res    : GSAData.Result;
          adr    : GSAData.Instruction;
          design : GSAData.Item;
      BEGIN
        Design(r, d, design);
        design.type := Symtab.linttyp;
        res := AddressOf(r, design, pos);
        adr := res(GSAData.Instruction);
        CompleteItem(adr, x); (* synthesizes a LONGINT type *)
      END Adr;

      PROCEDURE Cc(r : GSAData.Region;
                   code : AST.Expr;
                   pos : LONGINT;
                   VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          cc  : GSAData.Item;
      BEGIN
        Expr(r, code, cc);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gcondcode,
                                       Symtab.booltyp, pos);
        GSAData.OperandAppend(inst, cc.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Cc;

      PROCEDURE Bit(r : GSAData.Region;
                    lhs, rhs : AST.Expr;
                    pos : LONGINT;
                    VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          lop, rop : GSAData.Item;
      BEGIN
        Expr(r, lhs, lop);
        Expr(r, rhs, rop);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gbit,
                                       Symtab.booltyp, pos);
        GSAData.OperandAppend(inst, lop.node);
        GSAData.OperandAppend(inst, rop.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
        (* FIXME: provide range test on RHS *)
      END Bit;

      PROCEDURE Get(r : GSAData.Region;
                    desttype : Symtab.Type;
                    addr : AST.Expr;
                    pos : LONGINT;
                    VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, addr, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Hget,
                                       ArithmeticSubclass(desttype),
                                       desttype, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Get;

      PROCEDURE Put(r : GSAData.Region;
                    dest, val : AST.Expr;
                    pos : LONGINT;
                    VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          dst, src : GSAData.Item;
          store : GSAData.Temporary;
      BEGIN
        Expr(r, dest, dst);
        Expr(r, val, src);
        inst := GSAData.NewInstruction(GSAOpcode.Hput, ArithmeticSubclass(val.type),
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, dst.node);
        GSAData.OperandAppend(inst, src.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
        store := StoreGetVar(r);
        GSAData.AssignToVariable(r, store, x);
      END Put;

      PROCEDURE GetReg(r : GSAData.Region;
                       desttype : Symtab.Type;
                       reg : AST.Expr;
                       pos : LONGINT;
                       VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, reg, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Hgetreg,
                                       ArithmeticSubclass(desttype),
                                       desttype, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END GetReg;

      PROCEDURE PutReg(r : GSAData.Region;
                       reg, val : AST.Expr;
                       pos : LONGINT;
                       VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          dst, src : GSAData.Item;
      BEGIN
        Expr(r, reg, dst);
        Expr(r, val, src);
        inst := GSAData.NewInstruction(GSAOpcode.Hputreg,
                                       ArithmeticSubclass(val.type),
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, dst.node);
        GSAData.OperandAppend(inst, src.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END PutReg;

      PROCEDURE SysNew(r : GSAData.Region;
                       desttype : Symtab.Type;
                       e : AST.Expr;
                       pos : LONGINT;
                       VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          expr : GSAData.Item;
      BEGIN
        Expr(r, e, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gnewblock,
                                       desttype, pos);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        INCL(inst.attrib, GSAData.raUniqueResult);
        CompleteItem(inst, x);
      END SysNew;

      PROCEDURE Move(r : GSAData.Region;
                     source, dest, length : AST.Expr;
                     pos : LONGINT;
                     VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          src, dst, len : GSAData.Item;
      BEGIN
        Expr(r, source, src);
        Expr(r, dest, dst);
        Expr(r, length, len);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gmove,
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, src.node);
        GSAData.OperandAppend(inst, dst.node);
        GSAData.OperandAppend(inst, len.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Move;

      PROCEDURE MemR(r : GSAData.Region;
                     source, offset : AST.Expr;
                     dest : AST.Design;
                     pos : LONGINT;
                     VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          src, dst, ofs : GSAData.Item;
      BEGIN
        Expr(r, source, src);
        Expr(r, offset, ofs);
        Design(r, dest, dst);
        inst := GSAData.NewInstruction(GSAOpcode.Hmemr,
                                       ArithmeticSubclass(dest.type),
                                       dest.type, pos);
        GSAData.OperandAppend(inst, src.node);
        GSAData.OperandAppend(inst, ofs.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
        IF dst.node IS GSAData.Instruction THEN
          AssignThruInstruction(r, dst.node(GSAData.Instruction), x);
        ELSE
          GSAData.AssignToVariable(r, dst.node(GSAData.Addressable), x);
        END;
      END MemR;

      PROCEDURE MemW(r : GSAData.Region;
                     source, offset, val : AST.Expr;
                     pos : LONGINT;
                     VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          src, expr, ofs : GSAData.Item;
      BEGIN
        Expr(r, source, src);
        Expr(r, offset, ofs);
        Expr(r, val, expr);
        inst := GSAData.NewInstruction(GSAOpcode.Hmemw,
                                       ArithmeticSubclass(expr.type),
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, src.node);
        GSAData.OperandAppend(inst, ofs.node);
        GSAData.OperandAppend(inst, expr.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END MemW;

      PROCEDURE BitReset(r : GSAData.Region;
                         addr, bitnum : AST.Expr;
                         pos : LONGINT;
                         VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          adr, bit : GSAData.Item;
      BEGIN
        Expr(r, addr, adr);
        Expr(r, bitnum, bit);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gresetbit,
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, adr.node);
        GSAData.OperandAppend(inst, bit.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END BitReset;

      PROCEDURE BitSet(r : GSAData.Region;
                       addr, bitnum : AST.Expr;
                       pos : LONGINT;
                       VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          adr, bit : GSAData.Item;
      BEGIN
        Expr(r, addr, adr);
        Expr(r, bitnum, bit);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gsetbit,
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, adr.node);
        GSAData.OperandAppend(inst, bit.node);
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END BitSet;

      PROCEDURE Finalize(r : GSAData.Region;
                         type : Symtab.Type;
                         func : AST.Design;
                         pos : LONGINT;
                         VAR x : GSAData.Item);
        VAR
          inst : GSAData.Instruction;
          td, adr : GSAData.Item;
      BEGIN
        Design(r, func, adr);
        MakeTDNode(r, type, pos, td);
        inst := GSAData.NewInstruction(GSAOpcode.Gsystem, GSAOpcode.Gfinalize,
                                       Symtab.notyp, pos);
        GSAData.OperandAppend(inst, td.node);
        GSAData.OperandAppend(inst, AddressOf(r, adr, pos));
        GSAData.InstructionAppend(r, inst);
        CompleteItem(inst, x);
      END Finalize;

    BEGIN
      CASE proc OF
      | Symtab.absfn: Abs(r, args.arg(AST.Expr), n.pos, x);
      | Symtab.capfn: Cap(r, args.arg(AST.Expr), n.pos, x);
      | Symtab.oddfn: Odd(r, args.arg(AST.Expr), n.pos, x);
      | Symtab.adrfn: Adr(r, args.arg(AST.Design), n.pos, x);
      | Symtab.ccfn: Cc(r, args.arg(AST.Expr), n.pos, x);

      | Symtab.ashfn: Shift(r, GSAOpcode.Lasl, GSAOpcode.Lasr,
                            args.arg(AST.Expr), args.next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.lshfn: Shift(r, GSAOpcode.Llsl, GSAOpcode.Llsr,
                            args.arg(AST.Expr), args.next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.rotfn: Shift(r, GSAOpcode.Lrol, GSAOpcode.Lror,
                            args.arg(AST.Expr), args.next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.lenfn: Len(r, args.arg(AST.Design), args.next(AST.Arg).arg(AST.Expr),
                          n.pos, x);

      | Symtab.bitfn: Bit(r, args.arg(AST.Expr), args.next(AST.Arg).arg(AST.Expr),
                          n.pos, x);

      | Symtab.newfn: New(r, args.arg(AST.Design), args.next, n.pos, x);

      | Symtab.getfn: Get(r, rtype, args.arg(AST.Expr), n.pos, x);

      | Symtab.putfn: Put(r, args.arg(AST.Expr), args.next(AST.Arg).arg(AST.Expr),
                          n.pos, x);

      | Symtab.getrfn: GetReg(r, rtype, args.arg(AST.Expr), n.pos, x);

      | Symtab.putrfn: PutReg(r, args.arg(AST.Expr),
                              args.next(AST.Arg).arg(AST.Expr),
                              n.pos, x);

      | Symtab.sysnewfn:
        SysNew(r, rtype, args.arg(AST.Expr), n.pos, x);

      | Symtab.movefn: Move(r, args.arg(AST.Expr),
                            args.next(AST.Arg).arg(AST.Expr),
                            args.next(AST.Arg).next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.minfn: Min(r, args.arg.type, n.pos, x);

      | Symtab.maxfn: Max(r, args.arg.type, n.pos, x);

      | Symtab.sizefn: Size(r, n.type, args.arg.type, n.pos, x);

      | Symtab.inclfn: Incl(r, args.arg(AST.Design),
                            args.next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.exclfn: Excl(r, args.arg(AST.Design),
                            args.next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.copyfn:
        Fatal(19999); (* COPY is turned into an Assign node *)

      | Symtab.memrfn: MemR(r, args.arg(AST.Expr),
                            args.next(AST.Arg).arg(AST.Expr),
                            args.next(AST.Arg).next(AST.Arg).arg(AST.Design),
                            n.pos, x);

      | Symtab.memwfn: MemW(r, args.arg(AST.Expr),
                            args.next(AST.Arg).arg(AST.Expr),
                            args.next(AST.Arg).next(AST.Arg).arg(AST.Expr),
                            n.pos, x);

      | Symtab.finalizefn:
        Finalize(r, args.arg.type, args.next(AST.Arg).arg(AST.Design), n.pos, x);

      | Symtab.bitrfn: BitReset(r, args.arg(AST.Expr),
                                args.next(AST.Arg).arg(AST.Expr),
                                n.pos, x);

      | Symtab.bitsfn: BitSet(r, args.arg(AST.Expr),
                              args.next(AST.Arg).arg(AST.Expr),
                              n.pos, x);

      ELSE
        Fatal(10240); (* either handled by front end or a new standard procedure *)
      END;
    END StandardProcedure;

    PROCEDURE FuncCall(n : AST.FuncCall; VAR x : GSAData.Item);
      VAR
        call : GSAData.Instruction;

      PROCEDURE PassedByRef(fp : Symtab.Symbol) : BOOLEAN;
      BEGIN
        RETURN ((fp.kind = Symtab.varpar) OR
                (fp.type.form IN Symtab.AggregateSet));
      END PassedByRef;

      PROCEDURE PassArguments(r : GSAData.Region;
                              call : GSAData.Instruction;
                              fp : Symtab.Symbol;
                              ap : AST.Arg);
        VAR
          x : GSAData.Item;
      BEGIN
        WHILE ap # NIL DO
          ASSERT(fp # NIL); (* must be one fp for each ap *)
          Expr(r, ap.arg, x);
          IF PassedByRef(fp) THEN
            GSAData.OperandAppend(call, AddressOf(r, x, ap.pos));
          END;
          GSAData.OperandAppend(call, x.node);
          IF ap.next # NIL THEN
            ap := ap.next(AST.Arg);
          ELSE
            ap := NIL;
          END;
          fp := Symtab.NextSymbol(fp);
        END;
      END PassArguments;

      PROCEDURE MethodCall(r : GSAData.Region;
                           n : AST.FuncCall) : GSAData.Instruction;
        VAR
          call : GSAData.Instruction;
          vmt, meth : GSAData.Item;
          selfType : Symtab.Type;
          self : Symtab.Symbol;
          method : GSAData.Instruction;
          td : GSAData.Instruction;
          index : GSAData.Const;
          methno : GSAData.Const;
          offset : LONGINT;

        PROCEDURE MakeVMTNode(r      : GSAData.Region;
                              self   : AST.Design;
                              selffp : Symtab.Symbol; (* self formal-parameter *)
                              super  : BOOLEAN;
                              pos    : LONGINT;
                          VAR x      : GSAData.Item);
          VAR
            selfap : GSAData.Item;
            selftype : Symtab.Type;
        BEGIN
          IF super THEN
            (* super calls in Oberon-2 are statially bound to the parent VMT *)
            selftype := selffp.type;
            IF selftype.form = Symtab.pointer THEN
              selftype := selftype(Symtab.Pointer).to;
            END;
            CompleteItem(GetSymbol(r, selftype(Symtab.Record).ancestor.sym, pos), x);
          ELSE
            (* self is a dereferenced pointer or a VAR parm *)
            IF selffp.kind = Symtab.varpar THEN
              (* The formal parameter is by-reference, so the actual parameter
               * must be a record.  This can be accomplished either by a dereference
               * of a heap-based record, the use of a by-reference parameter or by
               * application of a normal record.
               *)
              CASE self.subcl OF
              | AST.Dderef: (* type tag comes from heap *)
                Design(r, self(AST.Deref).base, selfap);
                GetTypeTag(r, selfap, r.pos, x);

              | AST.Dvarpar: (* type tag comes from 'enter' instruction *)
                Design(r, self, selfap);
                GetTypeTag(r, selfap, r.pos, x);
              ELSE (* normal designator; statically typed *)
                MakeTDNode(r, self.type, pos, x);
              END;
            ELSE (* self must be a pointer type *)
              ASSERT(selffp.type.form = Symtab.pointer, 1025);
              Design(r, self, selfap);
              GetTypeTag(r, selfap, r.pos, x);
            END;
          END;
          (* inv: x now points to the start of the type descriptor *)
        END MakeVMTNode;

      BEGIN
        Design(r, n.func, meth);
        selfType := n.args.arg.type;
        self := Symtab.FirstParm(n.func.type(Symtab.Procedure));
        MakeVMTNode(r, n.args.arg(AST.Design), self, AST.super IN n.func.flags, n.pos, vmt);

        methno := GSAData.ConstGetInt(r, n.func.sym(Symtab.SymbolProc).methno,
                                     Symtab.linttyp, n.pos);

        offset := -Symtab.linttyp.size * (n.func.sym(Symtab.SymbolProc).methno + 1);
        index := GSAData.ConstGetInt(r, offset, Symtab.linttyp, n.pos);

        td := GSAData.NewInstruction(GSAOpcode.Mmemory, GSAOpcode.Mtbpadr,
                                     Symtab.linttyp, n.pos);
        GSAData.OperandAppend(td, vmt.node);
        GSAData.OperandAppend(td, GetSymbol(r, self.type.sym, n.pos));
        GSAData.OperandAppend(td, meth.node);
        GSAData.OperandAppend(td, methno);
        GSAData.OperandAppend(td, index);
        GSAData.InstructionAppend(r, td);

        call := GSAData.NewInstruction(GSAOpcode.Gmisc, GSAOpcode.Gcall,
                                       n.type, n.pos);
        GSAData.OperandAppend(call, td);
        RETURN call;
      END MethodCall;

    BEGIN
      (* PROCEDURE pointers do not have a symbol field. *)
      IF (n.func.sym # NIL) & (n.func.sym IS Symtab.SymbolStdProc) THEN
        StandardProcedure(r, n.func.sym(Symtab.SymbolStdProc).procno, n.type,
                          n.args, x);
      ELSE
        IF n.func.subcl = AST.Dmethod THEN
          call := MethodCall(r, n);
        ELSE
          RValue(r, n.func, x);
          call := GSAData.NewInstruction(GSAOpcode.Gmisc, GSAOpcode.Gcall,
                                         n.type, n.pos);
          GSAData.OperandAppend(call, x.node); (* x <-> procedure to call *)
        END;
        (* pass arguments *)
        PassArguments(r, call, n.func.type(Symtab.Procedure).parms, n.args);
        GSAData.InstructionAppend(r, call);
        CompleteItem(call, x);
        ExitOperandAppend(x.node(GSAData.Instruction));
        (* function calls should not be deleted; put their result into the $exit *)
      END;
    END FuncCall;

  BEGIN
    IF n # NIL THEN
      IF n.class = AST.Nexpr THEN
        CASE n.subcl OF
        | AST.Enot, AST.Euminus, AST.Euplus, AST.Econvert, AST.Ecast, AST.Eadr:
          MExpr(n(AST.MExpr), x);

        | AST.Etimes, AST.Ediv, AST.Eslash, AST.Emod, AST.Eplus, AST.Eminus,
          AST.Eand, AST.Eor, AST.Eeql, AST.Eneq, AST.Elss, AST.Eleq, AST.Egtr,
          AST.Egeq, AST.Ein, AST.Eupto:
          DExpr(n(AST.DExpr), x);


        | AST.Eis: IsTest(n(AST.IsTest), x);

        | AST.Ecall: FuncCall(n(AST.FuncCall), x);

        | AST.Econst: ConstGetValue(r, n.val, n.pos, x);
        END;
      ELSE
        RValue(r, n(AST.Design), x);
      END;
    END;
  END Expr;

  PROCEDURE StmtList(r : GSAData.Region; n : AST.Node; VAR attr : Attributes);
    VAR
      exitTrue, exitFalse : GSAData.Region;
      exitMerge : GSAData.Merge;
      exitCond : GSAData.Item;
      exited : BOOLEAN;
      returnTrue, returnFalse : GSAData.Region;
      returnMerge : GSAData.Merge;
      returnCond : GSAData.Item;
      returned : BOOLEAN;


    PROCEDURE Enter(r : GSAData.Region; n : AST.Enter; VAR attr : Attributes);
      VAR
        region : GSAData.GlobalRegion;
        y : GSAData.Item;
        resType, t : Symtab.Type;
        enter : GSAData.Region;
        args : Symtab.Symbol;
        op : GSAData.Addressable;
        f : SHORTINT;
        dim : INTEGER;
        temp : GSAData.Temporary;
        tempattr : GSAData.TempAttributes;
        store : GSAData.Result;

      (* CopyParm: copy array or record by-value parameters *)
      PROCEDURE CopyParm(r : GSAData.Region;
                         subcl : SHORTINT;
                         dst : GSAData.Temporary;
                         src : Symtab.Symbol;
                         pos : LONGINT);
        VAR
          inst : GSAData.Instruction;
          sym : GSAData.Addressable;
          x : GSAData.Item;
      BEGIN
        (*
         * It is not sufficient to assign to the generated temporary because
         * the compiler will generate a 'copy' instruction and copy propagation
         * will undo the effect of assigning to the temporary.  In this case
         * a true copy must be coerced using special IR instructions.
         *)
        inst := GSAData.NewInstruction(GSAOpcode.Mmemory, subcl, dst.type, pos);

        (* destination of copy *)
        GSAData.OperandAppend(inst, dst);
        CompleteItem(dst, x);
        GSAData.OperandAppend(inst, AddressOf(r, x, pos));
        GSAData.OperandAppend(inst, GSAData.ConstGetInt(r, dst.type.size, Symtab.linttyp, pos));

        (* source of copy *)
        sym := GetSymbol(r, src, pos);
        GSAData.OperandAppend(inst, sym);
        CompleteItem(sym, x);
        GSAData.OperandAppend(inst, AddressOf(r, x, pos));

        GSAData.InstructionAppend(r, inst);
        (*
         * Set the original symbol to refer to the newly assigned temp.
         * Any use of the original symbol will yield the temporary
         *)
        GSAData.SymbolSetNode(src, temp);
      END CopyParm;

      (* ResetAddressables: reset all used addressable current value to NIL
       *
       * After a  region has been completely converted to GSA, the current
       * value fields must be reset to NIL so that the next region processed
       * has no conflicts with current values set from other procedures.
       *
       * This only occurs with global variables and non-locals.
       *)
      PROCEDURE ResetAddressables(addressables : GSAData.Addressable);
        VAR
          a : GSAData.Addressable;
      BEGIN
        a := addressables.faddr;
        WHILE a # addressables DO
          a.currvalue := NIL;
          IF a IS GSAData.Symbol THEN
            (* Disconnect any linkage of the front end symbol to the back end system.
             * This ensures that all non-local items will be assigned to as results of
             * $enter instruction.
             *)
            a(GSAData.Symbol).sym.bedata := NIL;
          END;
          a := a.faddr;
        END;
      END ResetAddressables;

      PROCEDURE MarkAllLive(rgn : GSAData.Region);
        VAR
          i : GSAData.Instruction;
          r : GSAData.Region;
      BEGIN
        INCL(rgn.attrib, GSAData.raLive);
        i := rgn.instructions.finst;
        WHILE i # rgn.instructions DO
          INCL(i.attrib, GSAData.raLive);
          i := i.finst;
        END;
        r := rgn.regions.freg;
        WHILE r # rgn.regions DO
          MarkAllLive(r);
          r := r.freg;
        END;
      END MarkAllLive;

    BEGIN
      GSAData.ResetTempAttributes(tempattr);
      InitAttributes(attr); (* initialize all attributes which
                             * are global for a procedure
                             *)
      ASSERT(n.info # NIL);
      IF dfProgress IN diagnostics THEN
        Config.LogWStr('Converting ');
        Config.LogWStr(n.info(Symtab.SymbolProc).name^);
        Config.LogWLn;
      END;
      region := GSAData.NewGlobalRegion(n.info(Symtab.SymbolProc), n.pos);
      GSAData.BindRegion(r, region);
      CurrentProcedure := n.info;

      (* add all formal parameters (and their additional parts) to the
       * instruction as results
       *)
      enter := GSAData.InstructionEnter(region);
      store := StoreGet(enter);
      args := n.info.type(Symtab.Procedure).parms;
      WHILE args # NIL DO
        op := GetSymbol(region, args, n.pos);
        EnterResultAppend(enter, op);
        IF args.kind IN {Symtab.par, Symtab.varpar} THEN
          IF args.kind = Symtab.varpar THEN
            EnterResultAppendAddr(enter, op);
          END;
          f := args.type.form;

          IF f = Symtab.openarr THEN (* open array lengths *)
            t := args.type;
            dim := 0;
            WHILE t.form = Symtab.openarr DO
              temp := GSAData.NewTemporaryArrayLen(enter, dim, args, n.pos);
              EnterResultAppend(enter, temp);
              t := t(Symtab.Array).of;
              INC(dim);
            END;
          ELSIF (args.kind = Symtab.varpar) & (f = Symtab.record) THEN
            (* record type tag *)
            temp := GSAData.NewTemporaryRecordTag(enter, args, n.pos);
            EnterResultAppend(enter, temp);
            EnterResultAppendAddr(enter, temp);
          END;

          IF (args.kind = Symtab.par)
           & (args.type.form IN {Symtab.record, Symtab.array}) THEN
            (*
             * Records and arrays that are passed by-value are really passed
             * by-reference for efficiency.  It is the responsibility of the
             * callee to make a local copy of the parameter
             *)
            temp := GSAData.NewTemporary(enter, args.type, n.info, n.pos);

            CASE args.type.form OF
            | Symtab.record:
              CopyParm(enter, GSAOpcode.Mrecordcopy, temp, args, n.pos);

            | Symtab.array:
              CopyParm(enter, GSAOpcode.Marraycopy, temp, args, n.pos);
            END;
          END;
        END;
        args := Symtab.NextSymbol(args);
      END;

      IF n.info.mnolev > 0 THEN (* dynamic frame pointer *)
        temp := GSAData.NewTemporaryDynFrame(enter, n.info, n.pos);
        EnterResultAppend(enter, temp);
      END;

      (* initialize '$return' *)
      IF n.info.type IS Symtab.Procedure THEN
        resType := n.info.type(Symtab.Procedure).result;
      ELSE
        resType := Symtab.notyp;
      END;

      attr.returned := GSAData.NewTemporaryReturn(enter, n.info, n.pos);
      CompleteItem(GSAData.ConstGetBool(region, FALSE, n.pos), y);
      GSAData.AssignToVariable(enter, attr.returned, y);  (* $return := FALSE  *)

      (* If the procedure has a result, a temporary variable
       * for the result is to be created an initialized
       *)
      IF resType # Symtab.notyp THEN
        attr.resultval := GSAData.NewTemporaryResult(enter, resType, n.info, n.pos);
        CASE resType.form OF
        | Symtab.bool:
          CompleteItem(GSAData.ConstGetBool(region, FALSE, n.pos), y);

        | Symtab.byte, Symtab.char, Symtab.sint, Symtab.int, Symtab.lint:
          CompleteItem(GSAData.ConstGetInt(enter, 0, resType, n.pos), y);

        | Symtab.real:
          CompleteItem(GSAData.ConstGetReal(enter, 0, n.pos), y);

        | Symtab.lreal:
          CompleteItem(GSAData.ConstGetLReal(enter, 0, n.pos), y);

        | Symtab.set:
          CompleteItem(GSAData.ConstGetSet(enter, {}, n.pos), y);

        | Symtab.pointer, Symtab.procedure:
          CompleteItem(GSAData.ConstGetNil(enter, n.pos), y);
        END;
        GSAData.AssignToVariable(enter, attr.resultval, y); (* $result := 0 *)
      END;

      MiscList(region, n.import, y);
      MiscList(region, n.inittd, y);
      MiscList(region, n.decl, y);
      StmtList(region, n.body, attr);

      StoreDelete(GSAData.InstructionExit(region));
      GSAData.RestoreTempAttributes(tempattr);
      ResetAddressables(region.addressables);
      GSAData.GlobalRegionClose(region);
      InitAttributes(attr);
      StmtList(region, n.nestedproc, attr);

      (* initialization code; all instructions must be live *)
      IF AST.main IN n.flags THEN
        MarkAllLive(region);
      END;
    END Enter;

    PROCEDURE Assign(r : GSAData.Region;
                     n : AST.Assign;
                     VAR attr : Attributes);
      VAR
        lhs, rhs : GSAData.Item;
        lhn : GSAData.Node;

      PROCEDURE blockcopy(r : GSAData.Region; VAR lhs, rhs : GSAData.Item);
        VAR
          subcl : SHORTINT;
          len : GSAData.Usable;
          dim : GSAData.Const;
          copy : GSAData.Instruction;
          lhn : GSAData.Node;
      BEGIN
        lhn := lhs.node;
        IF lhn.type.form = Symtab.array THEN
          IF lhn.type(Symtab.Array).of.form = Symtab.char THEN
            subcl := GSAOpcode.Mstringcopy;
          ELSE
            subcl := GSAOpcode.Marraycopy;
          END;
          dim := GSAData.ConstGetInt(r, 0, Symtab.linttyp, r.pos);
          len := GetArrayLength(r, lhn(GSAData.Usable), dim(GSAData.ConstInt), lhn.pos);
        ELSE
          subcl := GSAOpcode.Mrecordcopy;
          len := GSAData.ConstGetInt(r, lhn.type.size, Symtab.linttyp, r.pos);
        END;
        copy := GSAData.NewInstruction(GSAOpcode.Mmemory, subcl, lhn.type, lhn.pos);
        GSAData.InstructionAppend(r, copy);
        GSAData.OperandAppend(copy, lhn(GSAData.Usable));
        GSAData.OperandAppend(copy, AddressOf(r, lhs, lhn.pos));
        GSAData.OperandAppend(copy, len);
        GSAData.OperandAppend(copy, rhs.node);
        GSAData.OperandAppend(copy, AddressOf(r, rhs, rhs.node.pos));
        CompleteItem(copy, rhs);
      END blockcopy;

    BEGIN
      Design(r, n.lvalue, lhs);
      Expr(r, n.rvalue, rhs);
      lhn := lhs.node;
      WITH lhn : GSAData.Symbol DO
        (* cannot take address of code procedure & tbp *)
        ASSERT(lhn.sym.kind # Symtab.cproc, 1024);
        ASSERT(lhn.sym.kind # Symtab.tproc, 1025);

        IF lhn.type.form IN {Symtab.array, Symtab.record} THEN
          blockcopy(r, lhs, rhs);
        END;
        GSAData.AssignToVariable(r, lhn, rhs);

      | lhn : GSAData.Instruction DO (* array or record access *)
        IF lhn.type.form IN {Symtab.array, Symtab.record} THEN
          blockcopy(r, lhs, rhs);
        END;
        AssignThruInstruction(r, lhn, rhs);
      END;
    END Assign;

    PROCEDURE ProcCall(r : GSAData.Region;
                       n : AST.ProcCall;
                   VAR attr : Attributes);
    BEGIN
      Expr(r, n.call, attr.x);
    END ProcCall;

    PROCEDURE IfElse(r : GSAData.Region;
                     n : AST.IfElse;
                 VAR attr : Attributes);

      PROCEDURE IfBody(r : GSAData.Region;
                       ifb : AST.IfBody;
                       else : AST.StmtList;
                   VAR attr : Attributes);
        VAR
          cond : GSAData.Item;
          merge : GSAData.Merge;
          true, false : GSAData.Region;
          trueAttr, falseAttr : Attributes;
      BEGIN
        Expr(r, ifb.cond, cond);
        GSAData.SplitControlPath(r, cond, ifb.pos, true, false, merge);

        (* The region of 'merge' will change while processing the IF
         * statement so that other procedures which rely on the
         * owning-region can reliably tell the difference between the
         * true and false execution paths
         *)

        MergeOpenControlRegion(merge, true, attr, trueAttr);
        StmtList(true, ifb.stmt, trueAttr);
        GSAData.MergeReset(merge);

        MergeOpenControlRegion(merge, false, attr, falseAttr);

        IF ifb.elsif # NIL THEN
          IfBody(false, ifb.elsif, else, falseAttr);
        ELSIF else # NIL THEN
          StmtList(false, else, falseAttr);
        END;

        CombineAttributes(akNormal, attr, trueAttr);
        CombineAttributes(akNormal, attr, falseAttr);

        GSAData.MergeReset(merge);
        GSAData.InstructionSetRegion(merge, r);
        GSAData.MergeCommit(merge, r);
      END IfBody;

    BEGIN
      IfBody(r, n.ifstat, n.else, attr);
    END IfElse;

    PROCEDURE Case(r : GSAData.Region; n : AST.Case; VAR attr : Attributes);
      VAR
        x : GSAData.Item;
        m : GSAData.Merge;
        caseReg : GSAData.Region;

      PROCEDURE CaseBody(r : GSAData.Region;
                         expr : GSAData.Item;
                         sglcase : AST.SingleCase;
                         else : AST.StmtList;
                     VAR attr : Attributes);
        VAR
          g : GSAData.Guard;
          b : AST.CaseBounds;
          inattr, sglattr : Attributes;
      BEGIN
        inattr := attr;
        WHILE sglcase # NIL DO
          g := GSAData.NewGuard(expr.node, GSAOpcode.Gcasesgl, sglcase.pos);
          GSAData.InstructionAppend(r, g);
          GSAData.RegionSetMerge(g, m);
          GSAData.OperandAppend(m, g);
          GSAData.MergeReset(m);

          b := sglcase.bounds;
          WHILE b # NIL DO
            GSAData.CaseOperandAdd(g, x.type, b.bound.i0,
                                   b.bound.i1, sglcase.pos);
            b := b.next;
          END;

          sglattr := inattr;
          StmtList(g, sglcase.stmt, sglattr);
          CombineAttributes(akNormal, attr, sglattr);
          IF sglcase.next # NIL THEN
            sglcase := sglcase.next(AST.SingleCase);
          ELSE
            sglcase := NIL;
          END;
        END;

        (* inv: front end guarantees 'else # NIL' *)
        g := GSAData.NewGuard(expr.node, GSAOpcode.Gcaseelse, else.pos);
        GSAData.InstructionAppend(r, g);
        GSAData.RegionSetMerge(g, m);
        GSAData.OperandAppend(m, g);
        GSAData.MergeReset(m);
        StmtList(g, else, inattr);
        CombineAttributes(akNormal, attr, inattr);
      END CaseBody;

    BEGIN
      Expr(r, n.expr, x);
      caseReg := GSAData.NewCase(x.node(GSAData.Usable), n.pos);
      GSAData.InstructionAppend(r, caseReg);
      m := GSAData.NewMerge(GSAOpcode.Gcase, n.pos);
      CaseBody(caseReg, x, n.of.case, n.of.else, attr);
      GSAData.InstructionAppend(caseReg, m);
      GSAData.InstructionSetRegion(caseReg, r);
      GSAData.MergeCommit(m, r);
    END Case;

    PROCEDURE Loop(r : GSAData.Region; n : AST.Loop; VAR attrib : Attributes);
      VAR
        lm : GSAData.Merge; (* loop merge *)
        cond : GSAData.Instruction;
        x : GSAData.Item;
        attr : Attributes;
        enter : GSAData.Region;
    BEGIN
      attr := attrib; (* could require nested $exit *)
      enter := GSAData.InstructionEnter(r);
      attr.exit := GSAData.NewTemporaryExit(r, CurrentProcedure, n.pos);
      CompleteItem(GSAData.ConstGetBool(r, FALSE, n.pos), x);
      GSAData.AssignToVariable(enter, attr.exit, x);

      lm := GSAData.NewMerge(GSAOpcode.Gloop, n.pos);
      GSAData.InstructionAppend(r, lm);
      GSAData.OperandAppend(lm, GSAData.ConstGetBool(r, TRUE, n.pos));

      cond := GSAData.NewInstruction(GSAOpcode.Ceql,
                                     ArithmeticSubclass(Symtab.booltyp),
                                     Symtab.booltyp,
                                     n.pos);
      GSAData.OperandAppend(lm, cond);

      (* loop body *)
      GSAData.RegionSetMerge(lm, lm);
      StmtList(lm, n.body, attr);

      CompleteItem(attr.exit.currvalue, x);
      GSAData.OperandAppend(cond, x.node);
      GSAData.OperandAppend(cond, GSAData.ConstGetBool(r, FALSE, n.pos));
      GSAData.InstructionAppend(lm, cond);

      GSAData.InstructionSetRegion(lm, r);
      GSAData.MergeCommit(lm, r);
    END Loop;

    PROCEDURE RepeatLoop(r : GSAData.Region;
                         n : AST.WhileRepeat;
                     VAR attr : Attributes);
      VAR
        lm : GSAData.Merge; (* loop-merge *)
        x : GSAData.Item;
        not : GSAData.Instruction;
    BEGIN
      lm := GSAData.NewMerge(GSAOpcode.Gloop, n.pos);
      GSAData.InstructionAppend(r, lm);
      GSAData.OperandAppend(lm, GSAData.ConstGetBool(r, TRUE, n.pos));

      (* The strange creation order & insertion order of the $not
       * is to ensure that the gates are properly normalized.  Without
       * $not as an operand of the $merge-loop prior to the body being
       * emitted, the gates will have the wrong operand order (due to
       * the normalization methodology).  But, the not actually needs
       * to be evaluated at the bottom of the loop - so it it created
       * near the top, but inserted at the bottom.
       *)
      not := GSAData.NewInstruction(GSAOpcode.Anot,
                                    ArithmeticSubclass(Symtab.booltyp),
                                    Symtab.booltyp, n.pos);
      GSAData.OperandAppend(lm, not);

      GSAData.RegionSetMerge(lm, lm);
      StmtList(lm, n.body, attr);
      GSAData.MergeCommit(lm, r);

      Expr(lm, n.cond, x);
      GSAData.OperandAppend(not, x.node);
      GSAData.InstructionAppend(lm, not);
    END RepeatLoop;

    PROCEDURE WhileLoop(r : GSAData.Region;
                        n : AST.WhileRepeat;
                    VAR attr : Attributes);
      VAR
        ifM : GSAData.Merge; (* if-merge *)
        lm : GSAData.Merge; (* loop-merge *)
        x : GSAData.Item;
        ifTrue : GSAData.Region; (* REPEAT loop appears in this region *)
        ifFalse : GSAData.Region; (* if the WHILE loop should never be taken *)
        ifAttr : Attributes;
        not : GSAData.Instruction;
    BEGIN

      (* WHILE loops are transformed into a guarded REPEAT loop so
       * that loop invariant code motion will work properly
       *
       * WHILE x DO stmtlist; END;
       * becomes
       * IF x THEN REPEAT stmtlist UNTIL ~x; END;
       *)
      Expr(r, n.cond, x);
      GSAData.SplitControlPath(r, x, n.pos, ifTrue, ifFalse, ifM);
      MergeOpenControlRegion(ifM, ifTrue, attr, ifAttr);

      lm := GSAData.NewMerge(GSAOpcode.Gloop, n.pos);
      GSAData.InstructionAppend(ifTrue, lm);
      GSAData.OperandAppend(lm, GSAData.ConstGetBool(r, TRUE, n.pos));

      (* The strange creation order & insertion order of the $not
       * is to ensure that the gates are properly normalized.  Without
       * $not as an operand of the $merge-loop prior to the body being
       * emitted, the gates will have the wrong operand order (due to
       * the normalization methodology).  But, the not actually needs
       * to be evaluated at the bottom of the loop - so it it created
       * near the top, but inserted at the bottom.
       *)
      not := GSAData.NewInstruction(GSAOpcode.Anot,
                                    ArithmeticSubclass(Symtab.booltyp),
                                    Symtab.booltyp, n.pos);
      GSAData.OperandAppend(lm, not);
      GSAData.RegionSetMerge(lm, lm);
      StmtList(lm, n.body, attr);      (* loop body *)

      Expr(lm, n.cond, x);
      GSAData.OperandAppend(not, x.node);
      GSAData.InstructionAppend(lm, not);

      (* reset loop merge so if-merge will correctly gate any exported values *)
      GSAData.MergeReset(lm);

      GSAData.MergeCommit(lm, ifTrue);
      GSAData.MergeReset(ifM);
      MergeOpenControlRegion(ifM, ifFalse, attr, ifAttr);
      GSAData.MergeCommit(ifM, r);
    END WhileLoop;

    PROCEDURE Exit(r : GSAData.Region; n : AST.StmtList; VAR attr : Attributes);
      VAR
        x : GSAData.Item;
    BEGIN (* inv: front end disallows EXIT outside of loop (attr.exit # NIL) *)

      (* 2002.03.24: there are some issues with handling $exit and $return which
       * are not yet resolved.  Most strikingly, if an EXIT occurs in a
       * 'THEN', statements in the 'ELSE' are currently guarded by the
       * $exit check
       *)

      CompleteItem(GSAData.ConstGetBool(r, TRUE, n.pos), x);
      GSAData.AssignToVariable(r, attr.exit, x);
      INCL(attr.flags, afExited);
    END Exit;

    PROCEDURE Return(r : GSAData.Region; n : AST.Return; VAR attr : Attributes);
      VAR
        x, y : GSAData.Item;
    BEGIN
      ASSERT(attr.returned # NIL, 1024);
      CompleteItem(GSAData.ConstGetBool(r, TRUE, n.pos), y);
      GSAData.AssignToVariable(r, attr.returned, y);  (* $return := TRUE *)
      IF attr.resultval # NIL THEN (* $result = expression *)
        Expr(r, n.expr, x);
        GSAData.AssignToVariable(r, attr.resultval, x);
      END;
      INCL(attr.flags, afReturned);
    END Return;

    PROCEDURE For(r : GSAData.Region; n : AST.For; VAR attr : Attributes);
      VAR
        temp : GSAData.Temporary;
        control, low, high, cond : GSAData.Item;
        step : GSAData.Const;
        increment : SHORTINT;
        test : GSAData.Instruction;
        ifTrue, ifFalse, body : GSAData.Region;
        trueAttr, falseAttr : Attributes;
        ifM : GSAData.Merge; (* if merge *)

      PROCEDURE ForBody(r     : GSAData.Region;
                        inc   : SHORTINT;
                        n     : AST.For; (* body statements *)
                        ctrl  : GSAData.Item;
                        tmp   : GSAData.Temporary;
                        step  : GSAData.Const;
                        VAR attr  : Attributes);
        VAR
          x : GSAData.Item;
          test, incr  : GSAData.Instruction;
          loopM : GSAData.Merge; (* loop merge *)
          body : GSAData.Region;
          unused, backEdge : GSAData.Region;
          frontAttr , backAttr : Attributes;
          cond : GSAData.Item;
      BEGIN
        loopM := GSAData.NewMerge(GSAOpcode.Gloop, n.pos);
        GSAData.InstructionAppend(r, loopM);

        MergeOpenControlRegion(loopM, r, attr, frontAttr); (* loop front edge *)
        GSAData.RegionNewSubRegion(loopM, n.pos, body); (* alw region (loop body) *)

        (* generate loop control instruction; which must go into loop-merge *)
        IF n.step > 0 THEN
          test := GSAData.NewInstruction(GSAOpcode.Cgtr,
                                         ArithmeticSubclass(control.type),
                                         Symtab.booltyp, n.pos);
        ELSE
          test := GSAData.NewInstruction(GSAOpcode.Clss,
                                         ArithmeticSubclass(control.type),
                                         Symtab.booltyp, n.pos);
        END;
        GSAData.OperandAppend(test, ctrl.node);
        GSAData.OperandAppend(test, tmp);
        GSAData.InstructionAppend(loopM, test);
        CompleteItem(test, cond);

        GSAData.SplitPaths(loopM, cond, n.pos, unused, backEdge);
        MergeOpenControlRegion(loopM, backEdge, attr, backAttr);
        GSAData.RegionSetMerge(backEdge, loopM);

        (* loop body *)
        GSAData.RegionSetMerge(body, loopM);
        StmtList(body, n.body, frontAttr);

        (* increment / decrement the control variable *)

        incr := GSAData.NewInstruction(inc,
                                       ArithmeticSubclass(ctrl.type),
                                       ctrl.type, n.pos);
        GSAData.OperandAppend(incr, ctrl.node);
        GSAData.OperandAppend(incr, step);
        GSAData.InstructionAppend(body, incr);
        CompleteItem(incr, x);
        GSAData.AssignToVariable(body, ctrl.node(GSAData.Addressable), x);

        GSAData.InstructionSetRegion(loopM, r);
        GSAData.MergeCommit(loopM, r);

        CombineAttributes(akNormal, attr, frontAttr);
        CombineAttributes(akNormal, attr, backAttr);
      END ForBody;

    BEGIN
      Design(r, n.control, control);
      Expr(r, n.lower, low);
      Expr(r, n.upper, high);
      temp := GSAData.NewTemporary(r, control.type, CurrentProcedure, n.control.pos);
      GSAData.AssignToVariable(r, control.node(GSAData.Symbol), low);
      GSAData.AssignToVariable(r, temp, high);
      step := GSAData.ConstGetInt(r, n.step, Symtab.linttyp, n.pos);

      IF n.step > 0 THEN
        increment := GSAOpcode.Aadd;
        test := GSAData.NewInstruction(GSAOpcode.Cleq,
                                       ArithmeticSubclass(control.type),
                                       Symtab.booltyp, n.pos);
      ELSE
        increment := GSAOpcode.Asub;
        test := GSAData.NewInstruction(GSAOpcode.Cgeq,
                                       ArithmeticSubclass(control.type),
                                       Symtab.booltyp, n.pos);
      END;
      (* check if induction variable is in the for-loop range *)
      GSAData.OperandAppend(test, control.node);
      GSAData.OperandAppend(test, temp);
      GSAData.InstructionAppend(r, test);
      CompleteItem(test, cond);

      GSAData.SplitControlPath(r, cond, n.pos, ifTrue, ifFalse, ifM);
      MergeOpenControlRegion(ifM, ifTrue, attr, trueAttr);
      GSAData.RegionSetMerge(ifTrue, ifM);

      (* inv: ifTrue is the region where the loop will be emitted *)
      (* inv: ifFalse is the region when the loop shouldn't be taken at all *)

      ForBody(ifTrue, increment, n, control, temp, step, attr);

      MergeOpenControlRegion(ifM, ifFalse, attr, falseAttr);
      GSAData.MergeCommit(ifM, r);
      CombineAttributes(akNormal, attr, falseAttr);
      CombineAttributes(akNormal, attr, trueAttr);
    END For;

    (* The Oberon WITH statement is very similar to an IF statement
     * based on symbol types and this observation leads to the
     * conclusion that it will also produce nearly identical GSA code
     *)
    PROCEDURE With(r : GSAData.Region; n : AST.With; VAR attr : Attributes);

      PROCEDURE WithBody(r : GSAData.Region;
                         n : AST.WithList;
                         else : AST.StmtList);
        VAR
          test, var, type : GSAData.Item;
          merge : GSAData.Merge;
          true, false : GSAData.Region;
          trueAttr, falseAttr : Attributes;
      BEGIN
        RValue(r, n.control, var);
        RValue(r, n.testtype, type);
        TypeTest(r, n.pos, var, type, test);
        GSAData.SplitControlPath(r, test, n.pos, true, false, merge);

        MergeOpenControlRegion(merge, true, attr, trueAttr);
        StmtList(true, n.body, attr);
        GSAData.MergeReset(merge);

        MergeOpenControlRegion(merge, false, attr, falseAttr);
        IF n.next # NIL THEN
          WithBody(false, n.next(AST.WithList), else);
        ELSE (* no user-supplied ELSE ->FEG HALT *)
          StmtList(false, else, attr);
        END;

        GSAData.MergeReset(merge);
        GSAData.InstructionSetRegion(merge, r);
        GSAData.MergeCommit(merge, r);
        CombineAttributes(akNormal, attr, trueAttr);
        CombineAttributes(akNormal, attr, falseAttr);
      END WithBody;
    BEGIN
      WithBody(r, n.wstat, n.else);
    END With;

    PROCEDURE Halt(r : GSAData.Region; n : AST.Halt; VAR attr : Attributes);
      VAR
        halt : GSAData.Instruction;
        value, cond : GSAData.Item;
    BEGIN
      Expr(r, n.expr, cond);
      Expr(r, n.val, value); (* inv: value IS ConstInt *)

      CASE value.node(GSAData.ConstInt).val OF
      | Config.HaltWith:
        halt := GSAData.NewInstruction(GSAOpcode.Ttrap, GSAOpcode.Twith,
                                      Symtab.notyp, n.pos);
        INCL(halt.attrib, GSAData.raLive);
        GSAData.InstructionAppend(r, halt);

      | Config.HaltCase:
        halt := GSAData.NewInstruction(GSAOpcode.Ttrap, GSAOpcode.Tcase,
                                      Symtab.notyp, n.pos);
        INCL(halt.attrib, GSAData.raLive);
        GSAData.InstructionAppend(r, halt);

      | Config.HaltAssert: Trap(r, GSAOpcode.Tassert, n.pos, cond);

      ELSE
        halt := GSAData.NewInstruction(GSAOpcode.Ttrap, GSAOpcode.Thalt,
                                      Symtab.notyp, n.pos);
        GSAData.OperandAppend(halt, value.node);
        INCL(halt.attrib, GSAData.raLive);
        GSAData.InstructionAppend(r, halt);
      END;
    END Halt;

  BEGIN
    exited := FALSE;
    returned := FALSE;

    WHILE n # NIL DO
      IF afExited IN attr.flags THEN
        exited := TRUE;
        CompleteItem(attr.exit, exitCond);
        GSAData.SplitControlPath(r, exitCond, n.pos, exitTrue, exitFalse, exitMerge);
        GSAData.MergeOpenControlRegion(exitMerge, exitTrue);
        GSAData.MergeOpenControlRegion(exitMerge, exitFalse);
        exitTrue := r; (* save r for restoration *)
        r := exitFalse; (* ~exit; code executed only if EXIT not encountered *)
      END;

      IF afReturned IN attr.flags THEN
        returned := TRUE;
        CompleteItem(attr.returned, returnCond);
        returnCond.node := attr.returned.currvalue;
        GSAData.SplitControlPath(r, returnCond, n.pos, returnTrue,
                                 returnFalse, returnMerge);
        GSAData.MergeOpenControlRegion(returnMerge, returnTrue);
        GSAData.MergeOpenControlRegion(returnMerge, returnFalse);
        returnTrue := r; (* save r for restoration *)
        r := returnFalse; (* ~returned; code executed only if RETURN
                           * not encountered
                           *)

      END;
      CASE n.subcl OF
      | AST.Snull:
      | AST.Senter: Enter(r, n(AST.Enter), attr);
      | AST.Sassign: Assign(r, n(AST.Assign), attr);
      | AST.Scall: ProcCall(r, n(AST.ProcCall), attr);
      | AST.Sifelse: IfElse(r, n(AST.IfElse), attr);
      | AST.Scase: Case(r, n(AST.Case), attr);
      | AST.Swhile: WhileLoop(r, n(AST.WhileRepeat), attr);
      | AST.Srepeat: RepeatLoop(r, n(AST.WhileRepeat), attr);
      | AST.Sloop: Loop(r, n(AST.Loop), attr);
      | AST.Sexit: Exit(r, n(AST.StmtList), attr);
      | AST.Sreturn: Return(r, n(AST.Return), attr);
      | AST.Swith: With(r, n(AST.With), attr);
      | AST.Sfor: For(r, n(AST.For), attr);
      | AST.Sassert: Halt(r, n(AST.Halt), attr);
      END;
      IF returned THEN
        r := returnTrue;
        GSAData.MergeCommit(returnMerge, r);
      END;
      IF exited THEN
        r := exitTrue;
        GSAData.MergeCommit(exitMerge, r);
      END;
      n := n.next;
    END;
  END StmtList;

  PROCEDURE Generate*(n : AST.Node) : GSAData.GlobalRegion;
    VAR
      x : GSAData.Item;
      ModuleRegion : GSAData.GlobalRegion;
      attr : Attributes;
  BEGIN
    ASSERT((n.class = AST.Nstmt) & (n.subcl = AST.Senter), 1024);
    InitAttributes(attr);
     (* dummy head *) ModuleRegion := GSAData.NewGlobalRegion(NIL,
                                                              GSAData.UndefInfoData);
    StmtList(ModuleRegion, n, attr);
    ASSERT(ModuleRegion # NIL, 1025);
    GSACI.Perform(ModuleRegion);
    RETURN ModuleRegion;
  END Generate;

  PROCEDURE Module*(n : AST.Node) : BOOLEAN;
    VAR
      ModuleRegion : GSAData.GlobalRegion;
  BEGIN
    ModuleRegion := Generate(n);
    RETURN TRUE;
  END Module;

  PROCEDURE InstallMachine*;
    VAR
      m : Config.MachineInfo;
  BEGIN
    IF dfProgress IN diagnostics THEN
      Config.LogWStr('Installing GSA');
      Config.LogWLn;
    END;
    NEW(m);
    m.x := 0;
    Config.InstallMachine(m);
    AST.SetTreeTraversalProc(Module);
  END InstallMachine;

  PROCEDURE UninstallMachine*;
  END UninstallMachine;

END O3MGSA.
