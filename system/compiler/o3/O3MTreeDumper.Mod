MODULE O3MTreeDumper; (* node dumper *)
  IMPORT 
    Config := O3Config,
    AST := O3TreeNode, 
    Scanner := O3Scanner,
    Symtab := O3Symtab;

  CONST
    debug = FALSE;

  VAR
    type : ARRAY Symtab.record - Symtab.undef + 1 OF Scanner.Name;
    class : ARRAY 4 OF Scanner.Name;
    dsgn : ARRAY AST.Dlast - AST.Dbegin OF Scanner.Name;
    stmt : ARRAY AST.Slast - AST.Sbegin OF Scanner.Name;
    expr : ARRAY AST.Elast - AST.Ebegin OF Scanner.Name;
    misc : ARRAY AST.Mlast - AST.Mbegin OF Scanner.Name;
    nil : ARRAY 4 OF CHAR;
    true : ARRAY 5 OF CHAR;
    false : ARRAY 6 OF CHAR;
    nofNodes : INTEGER;
    rconst, lrconst : ARRAY 5 OF CHAR;

  VAR
    stdout : Config.File;

  PROCEDURE ^ PN(n : AST.Node);
  PROCEDURE ^ PNL(n : AST.Node);

  PROCEDURE OpenFile(module : ARRAY OF CHAR);
    VAR name : POINTER TO ARRAY OF CHAR; i, l : LONGINT; ch : CHAR;
  BEGIN l := LEN(module);
    i := 0; REPEAT ch := module[i]; INC(i); UNTIL (ch = 0X) OR (i >= l);
    NEW(name, i + 4); COPY(module, name^);
    name[i - 1] := '.'; name[i] := 'a'; name[i + 1] := 's'; name[i + 2] := 't'; name[i + 3] := 0X;
    Config.CreateBinary(name^, stdout); ASSERT(stdout # NIL);
  END OpenFile;

  PROCEDURE CloseFile;
  BEGIN Config.Register(stdout);
  END CloseFile;

  PROCEDURE WS(n : ARRAY OF CHAR);
  BEGIN Config.WriteString(stdout, n);
  END WS;

  PROCEDURE WN(n : LONGINT);
  BEGIN Config.WriteStringNum(stdout, n, 1);
  END WN;

  PROCEDURE W(ch : CHAR);
  BEGIN Config.WriteCh(stdout, ch);
  END W;

  PROCEDURE NL;
  BEGIN W(0AX);
  END NL;

  PROCEDURE WSet(s : SET);
  BEGIN Config.WriteStringSet(stdout, s);
  END WSet;

  PROCEDURE L(ch : CHAR);
  BEGIN W(' '); W(ch); W('=');
  END L;

  PROCEDURE PR(n : AST.Node);
  BEGIN IF n # NIL THEN WN(n.refno); ELSE W('-'); END;
  END PR;

  PROCEDURE PNR(lab : CHAR; n : AST.Node);
  BEGIN L(lab); PR(n);
  END PNR;

  PROCEDURE Ref(n : AST.Node);
  BEGIN IF (n # NIL) & (n.refno = AST.InitialNodeRef) THEN n.refno := nofNodes; INC(nofNodes); END;
  END Ref;

  PROCEDURE PT(t : Symtab.Type);
  BEGIN IF t # NIL THEN WS(type[t.form]); ELSE W('?'); END; W(' ');
  END PT;

  PROCEDURE Pad(len : SHORTINT);
  BEGIN WHILE len > 0 DO DEC(len); W(' '); END;
  END Pad;

  PROCEDURE PBN(n : AST.Node);
  BEGIN
    Ref(n.next);
    Config.WriteStringNum(stdout, n.refno, 5); W(' '); W('('); Config.WriteStringNum(stdout, n.pos, 5); W(')'); W(' ');
    WS(class[n.class]); W(' ');
    CASE n.class OF
    |  AST.Ndsgn: WS(dsgn[n.subcl]);
    |  AST.Nstmt: WS(stmt[n.subcl]);
    |  AST.Nexpr: WS(expr[n.subcl]);
    |  AST.Nmisc: WS(misc[n.subcl]);
    END;
    PT(n.type); PNR('n', n.next);
  END PBN;

  PROCEDURE PrintDesign(n : AST.Design);
  BEGIN
    IF n # NIL THEN
      CASE n.subcl OF
      | AST.Danon..AST.Diproc, AST.Dtype, AST.Ddarrdesc, AST.Darrdesc, AST.Drecdesc:
      | AST.Dmethod, AST.Dfield: PN(n(AST.Field).base);
      | AST.Dmodule, AST.Dscope:
      | AST.Dderef: PN(n(AST.Deref).base);
      | AST.Dindex: PN(n(AST.Index).base); PN(n(AST.Index).index);
      | AST.Diguard, AST.Deguard: PN(n(AST.Guard).design);
      | AST.Dproc:
      END;
      PBN(n); Pad(1);
      CASE n.subcl OF
      |  AST.Danon:
      | AST.Dvar, AST.Dpar, AST.Dvarpar, AST.Dconst, AST.Ddarrdesc, AST.Darrdesc, AST.Drecdesc: WS(n.sym.name^);
      | AST.Dmethod:
        PNR('b', n(AST.Field).base);
        Pad(1);
        IF AST.super IN n.flags THEN W('S'); Pad(1); END;
        WS(n(AST.Field).sym.name^);
      | AST.Dfield: PNR('b', n(AST.Field).base); Pad(1); WS(n(AST.Field).sym.name^);
      | AST.Dtype: WS(n.sym.name^);
      | AST.Dmodule, AST.Dscope:
      | AST.Dderef:
        PNR('b', n(AST.Deref).base);
      | AST.Dindex:
        PNR('b', n(AST.Index).base); PNR('I', n(AST.Index).index);
        L('o'); WN(n(AST.Index).offset); L('s'); WN(n(AST.Index).scale);
      | AST.Diguard, AST.Deguard:
        PNR('d', n(AST.Guard).design); Pad(1); WS(n.type.sym.name^);
      | AST.Dstdproc, AST.Dproc: WS(n.sym.name^);
      END;
    END;
  END PrintDesign;

  PROCEDURE PrintMisc(n : AST.Node);

    PROCEDURE PrintInitTD(n : AST.InitTD);
    BEGIN PBN(n); Pad(1); WS(n.td.name^);
    END PrintInitTD;

    PROCEDURE PrintImport(n : AST.Import);
    BEGIN Ref(n.next); PBN(n); Pad(1); WS(n.module.name^);
    END PrintImport;

  BEGIN
    CASE n.subcl OF
    |  AST.Mdecl:
      Ref(n(AST.Declaration).expr);
      IF n(AST.Declaration).sym.kind = Symtab.const THEN PNL(n(AST.Declaration).expr); END;
      PBN(n); L('s'); WS(n(AST.Declaration).sym.name^);
      L('f');
      IF AST.fwddecl IN n.flags THEN  W('y') ELSE W('n'); END;
      L('e'); PR(n(AST.Declaration).expr);

    | AST.Minittd: PrintInitTD(n(AST.InitTD));
    | AST.Mimport: PrintImport(n(AST.Import));
    ELSE PBN(n);
    END;
  END PrintMisc;

  PROCEDURE PrintExpr(n : AST.Expr);

    PROCEDURE PrintConst(n : AST.Expr);
    BEGIN
      PBN(n);
      Pad(1);
      CASE n.type.form OF
      |  Symtab.bool: IF n.val.bool THEN WS(true); ELSE WS(false); END;
      |  Symtab.char: WN(n.val.i0); W('C');
      |  Symtab.sint, Symtab.int, Symtab.lint: WN(n.val.i0);
      |  Symtab.real: WS(rconst);
      |  Symtab.lreal: WS(lrconst);
      |  Symtab.set: WSet(n.val.set);
      |  Symtab.string: W('"'); WS(n.val.ext^); W('"');
      |  Symtab.nil: WS(nil);
      END;
    END PrintConst;

    PROCEDURE PrintMExpr(n : AST.MExpr);
    BEGIN PN(n.op); PBN(n); PNR('o', n.op);
    END PrintMExpr;

    PROCEDURE PrintDExpr(n : AST.DExpr);
    BEGIN PN(n.lop); PN(n.rop); PBN(n); PNR('l', n.lop); PNR('r', n.rop);
    END PrintDExpr;

    PROCEDURE PrintIsTest(n : AST.IsTest);
    BEGIN PN(n.var); PN(n.istype); PBN(n); PNR('v', n.var); PNR('t', n.istype);
    END PrintIsTest;

    PROCEDURE PA(x : AST.Node);
      VAR n : AST.Arg;
    BEGIN
      IF x # NIL THEN
        n := x(AST.Arg); Ref(n); PA(n.next); PN(n.arg); PBN(n); PNR('a', n.arg); NL;
      END;
    END PA;

    PROCEDURE PrintFuncCall(n : AST.FuncCall);
    BEGIN
      PA(n.args); PN(n.func); PBN(n); PNR('a', n.args); PNR('f', n.func);
    END PrintFuncCall;

  BEGIN
    IF n # NIL THEN
      CASE n.subcl OF
      |  AST.Enot..AST.Econvert, AST.Ecast, AST.Eadr: PrintMExpr(n(AST.MExpr));
      | AST.Etimes..AST.Eupto: PrintDExpr(n(AST.DExpr));
      |  AST.Eis: PrintIsTest(n(AST.IsTest));
      |  AST.Ecall: PrintFuncCall(n(AST.FuncCall));
      |  AST.Econst: PrintConst(n);
      END;
    END;
  END PrintExpr;

  PROCEDURE PrintStmt(n : AST.StmtList);

    PROCEDURE PBS(n : AST.StmtList);
    BEGIN Ref(n.prev); PBN(n); PNR('p', n.prev);
    END PBS;

    PROCEDURE PrintEnter(n : AST.Enter);
    BEGIN
      PNL(n.import); PNL(n.inittd); PNL(n.nestedproc); PNL(n.decl); PNL(n.body);
      PBS(n); PNR('N', n.nestedproc); PNR('b', n.body); PNR('i', n.import); PNR('t', n.inittd);
      Pad(1);
      IF n.info # NIL THEN WS(n.info.name^); END;
    END PrintEnter;

    PROCEDURE PrintAssign(n : AST.Assign);
    BEGIN PN(n.lvalue); PN(n.rvalue); PBS(n); PNR('l', n.lvalue); PNR('r', n.rvalue);
    END PrintAssign;

    PROCEDURE PrintProcCall(n : AST.ProcCall);
    BEGIN PN(n.call); PBS(n);  PNR('c', n.call);
    END PrintProcCall;

    PROCEDURE PrintIfElse(n : AST.IfElse);

      PROCEDURE PIB(x : AST.Node);
        VAR n : AST.IfBody;
      BEGIN
        IF x # NIL THEN
          n := x(AST.IfBody); Ref(n);
          PIB(n.elsif); PN(n.cond); PNL(n.stmt); PBN(n);
          PNR('c', n.cond); PNR('s', n.stmt); PNR('e', n.elsif); NL;
        END;
      END PIB;
    BEGIN PIB(n.ifstat); PN(n.else); PBS(n); PNR('b', n.ifstat); PNR('e', n.else);
    END PrintIfElse;

    PROCEDURE PrintCase(n : AST.Case);

      PROCEDURE PSC(x : AST.Node);
        VAR n : AST.SingleCase; b : AST.CaseBounds;
      BEGIN
        IF x # NIL THEN
          n := x(AST.SingleCase); Ref(n); b := n.bounds;
          PSC(n.next); PNL(n.stmt);
          PBN(n); PNR('s', n.stmt); L('r'); W('[');
          WHILE b # NIL DO
            W('('); WN(b.bound.i0); W(','); WN(b.bound.i1); W(')');
            b := b.next;
            IF b # NIL THEN W(','); END;
          END;
          W(']'); NL;
        END;
      END PSC;

      PROCEDURE PCS(n : AST.CaseStat);
      BEGIN
        Ref(n); PSC(n.case); PNL(n.else); PBN(n); PNR('c', n.case); PNR('e', n.else);
        L('l'); WN(n.range.i0); L('h'); WN(n.range.i1);
      END PCS;

    BEGIN PN(n.expr); PCS(n.of); NL; PBS(n); PNR('e', n.expr); PNR('o', n.of);
    END PrintCase;

    PROCEDURE PrintLoop(n : AST.Loop);
    BEGIN PNL(n.body); PBS(n); PNR('b', n.body);
    END PrintLoop;

    PROCEDURE PrintWRLoop(n : AST.WhileRepeat);
    BEGIN PN(n.cond); PNL(n.body); PBS(n); PNR('c', n.cond); PNR('b', n.body);
    END PrintWRLoop;

    PROCEDURE PrintExit(n : AST.StmtList);
    BEGIN PBS(n);
    END PrintExit;

    PROCEDURE PrintReturn(n : AST.Return);
    BEGIN
      PN(n.expr); PBS(n); PNR('e', n.expr);
      IF n.proc # NIL THEN Pad(1); WS(n.proc.name^); END;
    END PrintReturn;

    PROCEDURE PrintWith(n : AST.With);

      PROCEDURE PWL(x : AST.Node);
        VAR n : AST.WithList;
      BEGIN
        IF x # NIL THEN
          n := x(AST.WithList); Ref(n);
          PWL(n.next); PN(n.control); PN(n.testtype); PNL(n.body); PBN(n);
          PNR('c', n.control); PNR('t', n.testtype); PNR('b', n.body); NL;
        END;
      END PWL;

    BEGIN
      PWL(n.wstat); PNL(n.else); PBS(n);
      PNR('w', n.wstat); PNR('e', n.else);
    END PrintWith;

    PROCEDURE PrintFor(n : AST.For);
    BEGIN
      PN(n.control); PN(n.lower); PN(n.upper); PNL(n.body); PBS(n);
      PNR('c', n.control); PNR('l', n.lower); PNR('u', n.upper); L('s'); WN(n.step);
      PNR('b', n.body);
    END PrintFor;

    PROCEDURE PrintHalt(n : AST.Halt);
    BEGIN PN(n.expr); PN(n.val); PBS(n); PNR('e', n.expr); PNR('v', n.val);
    END PrintHalt;

  BEGIN
    CASE n.subcl OF
    |  AST.Snull: PBS(n);
    | AST.Senter: PrintEnter(n(AST.Enter));
    | AST.Sassign: PrintAssign(n(AST.Assign));
    | AST.Scall: PrintProcCall(n(AST.ProcCall));
    | AST.Sifelse: PrintIfElse(n(AST.IfElse));
    | AST.Scase: PrintCase(n(AST.Case));
    | AST.Swhile, AST.Srepeat: PrintWRLoop(n(AST.WhileRepeat));
    | AST.Sloop: PrintLoop(n(AST.Loop));
    | AST.Sexit: PrintExit(n(AST.StmtList));
    | AST.Sreturn: PrintReturn(n(AST.Return));
    | AST.Swith: PrintWith(n(AST.With));
    | AST.Sfor: PrintFor(n(AST.For));
    | AST.Sassert: PrintHalt(n(AST.Halt));
    END;
  END PrintStmt;

  PROCEDURE PN(n : AST.Node);
  BEGIN
    IF n # NIL THEN
      Ref(n);
      CASE n.class OF
      |  AST.Ndsgn:  PrintDesign(n(AST.Design));
      |  AST.Nstmt:  PrintStmt(n(AST.StmtList));
      |  AST.Nexpr:  PrintExpr(n(AST.Expr));
      |  AST.Nmisc:  PrintMisc(n);
      END;
      NL;
    END;
  END PN;

  PROCEDURE PNL(n : AST.Node);
  BEGIN WHILE n # NIL DO PN(n); n := n.next; END;
  END PNL;

  PROCEDURE Module*(n : AST.Node) : BOOLEAN;
  BEGIN OpenFile(n(AST.Enter).info.name^); 
    IF stdout # NIL THEN nofNodes := 0; NL; PNL(n); CloseFile; RETURN TRUE;
    ELSE RETURN FALSE;
    END;
  END Module;

  PROCEDURE UninstallMachine*;
  END UninstallMachine;
  
  PROCEDURE InstallMachine*;
    VAR m : Config.MachineInfo; 
  BEGIN
    IF debug THEN Config.LogWStr('Installing TreeDumper'); Config.LogWLn; END;
    NEW(m); m.x := 0; Config.InstallMachine(m);
    AST.SetTreeTraversalProc(Module);
  END InstallMachine;
  
BEGIN
  type[Symtab.undef    ] := 'undef ';
  type[Symtab.bool     ] := 'bool  ';
  type[Symtab.byte     ] := 'byte  ';
  type[Symtab.char     ] := 'char  ';
  type[Symtab.sint     ] := 'sint  ';
  type[Symtab.int      ] := 'int   ';
  type[Symtab.lint     ] := 'lint  ';
  type[Symtab.real     ] := 'real  ';
  type[Symtab.lreal    ] := 'lreal ';
  type[Symtab.set      ] := 'set   ';
  type[Symtab.string   ] := 'string';
  type[Symtab.nil      ] := 'nil   ';
  type[Symtab.void     ] := 'notyp ';
  type[Symtab.pointer  ] := 'ptr   ';
  type[Symtab.procedure] := 'proc  ';
  type[Symtab.array    ] := 'array ';
  type[Symtab.dynarr   ] := 'dynarr';
  type[Symtab.openarr  ] := 'opnarr';
  type[Symtab.record   ] := 'record';

  class[AST.Ndsgn] := 'Ndsgn';
  class[AST.Nstmt] := 'Nstmt';
  class[AST.Nexpr] := 'Nexpr';
  class[AST.Nmisc] := 'Nmisc';

  dsgn[AST.Danon        ] := 'Danon      ';
  dsgn[AST.Dvar         ] := 'Dvar       ';
  dsgn[AST.Dpar         ] := 'Dpar       ';
  dsgn[AST.Dvarpar      ] := 'Dvarpar    ';
  dsgn[AST.Dconst       ] := 'Dconst     ';
  dsgn[AST.Dstdproc     ] := 'Dstdproc   ';
  dsgn[AST.Dfwdproc     ] := 'Dfwdproc   ';
  dsgn[AST.Dlproc       ] := 'Dlproc     ';
  dsgn[AST.Dxproc       ] := 'Dxproc     ';
  dsgn[AST.Dcproc       ] := 'Dcproc     ';
  dsgn[AST.Diproc       ] := 'Diproc     ';
  dsgn[AST.Dmethod      ] := 'Dmethod    ';
  dsgn[AST.Dfield       ] := 'Dfield     ';
  dsgn[AST.Dtype        ] := 'Dtype      ';
  dsgn[AST.Dmodule      ] := 'Dmodule    ';
  dsgn[AST.Dscope       ] := 'Dscope     ';
  dsgn[AST.Ddarrdesc       ] := 'Ddarrdesc  ';
  dsgn[AST.Darrdesc       ] := 'Darrdesc   ';
  dsgn[AST.Drecdesc       ] := 'Drecdesc   ';
  dsgn[AST.Dderef       ] := 'Dderef     ';
  dsgn[AST.Dindex       ] := 'Dindex     ';
  dsgn[AST.Diguard      ] := 'Diguard    ';
  dsgn[AST.Deguard      ] := 'Deguard    ';
  dsgn[AST.Dproc        ] := 'Dproc      ';

  stmt[AST.Snull        ] := 'Snull      ';
  stmt[AST.Senter       ] := 'Senter     ';
  stmt[AST.Sassign      ] := 'Sassign    ';
  stmt[AST.Scall        ] := 'Scall      ';
  stmt[AST.Sifelse      ] := 'Sifelse    ';
  stmt[AST.Scase        ] := 'Scase      ';
  stmt[AST.Swhile       ] := 'Swhile     ';
  stmt[AST.Srepeat      ] := 'Srepeat    ';
  stmt[AST.Sloop        ] := 'Sloop      ';
  stmt[AST.Sexit        ] := 'Sexit      ';
  stmt[AST.Sreturn      ] := 'Sreturn    ';
  stmt[AST.Swith        ] := 'Swith      ';
  stmt[AST.Sfor         ] := 'Sfor       ';
  stmt[AST.Sassert      ] := 'Sassert    ';

  expr[AST.Enot         ] := 'Enot       ';
  expr[AST.Euminus      ] := 'Euminus    ';
  expr[AST.Euplus       ] := 'Euplus     ';
  expr[AST.Econvert     ] := 'Econvert   ';
  expr[AST.Etimes       ] := 'Etimes     ';
  expr[AST.Ediv         ] := 'Ediv       ';
  expr[AST.Eslash       ] := 'Eslash     ';
  expr[AST.Emod         ] := 'Emod       ';
  expr[AST.Eplus        ] := 'Eplus      ';
  expr[AST.Eminus       ] := 'Eminus     ';
  expr[AST.Eand         ] := 'Eand       ';
  expr[AST.Eor          ] := 'Eor        ';
  expr[AST.Eeql         ] := 'Eeql       ';
  expr[AST.Eneq         ] := 'Eneq       ';
  expr[AST.Elss         ] := 'Elss       ';
  expr[AST.Eleq         ] := 'Eleq       ';
  expr[AST.Egtr         ] := 'Egtr       ';
  expr[AST.Egeq         ] := 'Egeq       ';
  expr[AST.Ein          ] := 'Ein        ';
  expr[AST.Eupto        ] := 'Eupto      ';
  expr[AST.Eis          ] := 'Eis        ';
  expr[AST.Ecall        ] := 'Ecall      ';
  expr[AST.Econst       ] := 'Econst     ';
  expr[AST.Ecast        ] := 'Ecast      ';
  expr[AST.Eadr         ] := 'Eadr       ';

  misc[AST.Marg         ] := 'Marg       ';
  misc[AST.Mdecl        ] := 'Mdecl      ';
  misc[AST.Mifbody      ] := 'Mifbody    ';
  misc[AST.Mwithlist    ] := 'Mwithlist  ';
  misc[AST.Msglcase     ] := 'Msglcase   ';
  misc[AST.Mcasestat    ] := 'Mcasestat  ';
  misc[AST.Minittd      ] := 'Minittd    ';
  misc[AST.Mimport      ] := 'Mimport    ';


  nil[0] := 'n'; nil[1] := 'i'; nil[2] := 'l'; nil[3] := 0X;
  true[0] := 't'; true[1] := 'r'; true[2] := 'u'; true[3] := 'e'; true[4] := 0X;
  false[0] := 'f'; false[1] := 'a'; false[2] := 'l'; false[3] := 's'; false[4] := 'e'; false[5] := 0X;
  rconst[0] := 'r'; rconst[1] := 'e'; rconst[2] := 'a'; rconst[3] := 'l'; rconst[4] := 0X;
  lrconst[0] := 'l'; lrconst[1] := 'r'; lrconst[2] := 'l'; lrconst[3] := ' '; lrconst[4] := 0X;
END O3MTreeDumper.
