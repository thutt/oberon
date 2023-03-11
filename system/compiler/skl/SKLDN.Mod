MODULE SKLDN; (* node dumper *)
IMPORT
  OPM:=SKLMD,
  T:=SKLT,
  OPS:=SKLOS,
  ST:=SKLST;

  VAR
    type : ARRAY ST.record - ST.undef + 1 OF OPS.Name;
    class : ARRAY 4 OF OPS.Name;
    dsgn : ARRAY T.Dlast - T.Dbegin OF OPS.Name;
    stmt : ARRAY T.Slast - T.Sbegin OF OPS.Name;
    expr : ARRAY T.Elast - T.Ebegin OF OPS.Name;
    misc : ARRAY T.Mlast - T.Mbegin OF OPS.Name;
    nil : ARRAY 4 OF CHAR;
    true : ARRAY 5 OF CHAR;
    false : ARRAY 6 OF CHAR;
    nofNodes : INTEGER;
    rconst, lrconst : ARRAY 5 OF CHAR;

  PROCEDURE ^ PN(n : T.Node);
  PROCEDURE ^ PNL(n : T.Node);

  PROCEDURE WS(n : ARRAY OF CHAR);
  BEGIN
    OPM.LogWStr(n);
  END WS;

  PROCEDURE WB(b : BOOLEAN);
  BEGIN
    IF b THEN
      WS(true);
    ELSE
      WS(false);
    END;
  END WB;
  
  PROCEDURE WN(n : LONGINT);
  BEGIN
    OPM.LogWNum(n, 1);
  END WN;

  PROCEDURE W(ch : CHAR);
  BEGIN
    OPM.LogW(ch);
  END W;

  PROCEDURE NL;
  BEGIN
    OPM.LogWLn;
  END NL;

  PROCEDURE WSet(s : SET);
  BEGIN
    OPM.LogWSet(s);
  END WSet;

  PROCEDURE L(ch : CHAR);
  BEGIN
    W(' ');
    W(ch);
    W('=');
  END L;

  PROCEDURE PR(n : T.Node);
  BEGIN
    IF n # NIL THEN
      WN(n.refno);
    ELSE
      W('-');
    END;
  END PR;

  PROCEDURE PNR(lab : CHAR; n : T.Node);
  BEGIN
    L(lab);
    PR(n);
  END PNR;

  PROCEDURE Ref(n : T.Node);
  BEGIN
    IF (n # NIL) & (n.refno = OPM.InitialNodeRef) THEN
      n.refno := nofNodes;
      INC(nofNodes);
    END;
  END Ref;

  PROCEDURE PT(t : ST.Type);
  BEGIN
    IF t # NIL THEN
      WS(type[t.form]);
    ELSE
      W('?');
    END;
    W(' ');
  END PT;

  PROCEDURE Pad(len : SHORTINT);
  BEGIN
    WHILE len > 0 DO
      DEC(len);
      W(' ');
    END;
  END Pad;

  PROCEDURE PBN(n : T.Node);
  BEGIN
    Ref(n.next);
    OPM.LogWNum(n.refno, 5);
    W(' ');
    W('(');
    OPM.LogWNum(n.pos, 5);
    W(')');
    W(' ');
    WS(class[n.class]);
    W(' ');
    CASE n.class OF
    | T.Ndsgn:
      WS(dsgn[n.subcl]);

    | T.Nstmt:
      WS(stmt[n.subcl]);

    | T.Nexpr:
      WS(expr[n.subcl]);

    | T.Nmisc:
      WS(misc[n.subcl]);
    END;
    PT(n.type);
    PNR('n', n.next);
  END PBN;

  PROCEDURE PrintDesign(n : T.Design);
  BEGIN
    IF n # NIL THEN
      CASE n.subcl OF
      | T.Danon..T.Diproc, T.Dtype, T.Dcommon:

      | T.Dmethod, T.Dfield:
        PN(n(T.Field).base);

      | T.Dmodule, T.Dscope:

      | T.Dderef:
        PN(n(T.Deref).base);

      | T.Dindex:
        PN(n(T.Index).base);
        PN(n(T.Index).index);

      | T.Diguard, T.Deguard:
        PN(n(T.Guard).design);

      | T.Dcast:
        PN(n(T.DesignCast).node);

      | T.Dproc:
      END;

      PBN(n);
      Pad(1);

      CASE n.subcl OF
      | T.Danon:

      | T.Dvar, T.Dpar, T.Dvarpar, T.Dconst, T.Ddarrdesc,
        T.Darrdesc, T.Drecdesc, T.Dcommon: WS(n.sym.name^);

      | T.Dmethod:
        PNR('b', n(T.Field).base);
        L('o');
        WN(n(T.Field).offset);
        Pad(1);
        IF T.super IN n.flags THEN
          W('S');
          Pad(1);
        END;
        WS(n(T.Field).sym.name^);

      | T.Dfield:
        PNR('b', n(T.Field).base);
        L('o');
        WN(n(T.Field).offset);
        Pad(1);
        WS(n(T.Field).sym.name^);

      | T.Dtype:
        WS(n.sym.name^);

      | T.Dmodule, T.Dscope:

      | T.Dderef:
        PNR('b', n(T.Deref).base);

      | T.Dindex:
        PNR('b', n(T.Index).base);
        PNR('I', n(T.Index).index);
        L('o');
        WN(n(T.Field).offset);
        L('s');
        WN(n(T.Index).scale);

      | T.Diguard, T.Deguard:
        PNR('d', n(T.Guard).design);
        Pad(1);
        WS(n.type.sym.name^);

      | T.Dstdproc, T.Dproc:
        WS(n.sym.name^);

      | T.Dcast:
        PNR('n', n(T.DesignCast).node);
      END;
    END;
  END PrintDesign;

  PROCEDURE PrintMisc(n : T.Node);

    PROCEDURE PrintInitTD(n : T.InitTD);
    BEGIN
      PBN(n);
      Pad(1);
      WS(n.td.name^);
    END PrintInitTD;

    PROCEDURE PrintImport(n : T.Import);
    BEGIN
      Ref(n.next);
      PBN(n);
      Pad(1);
      WS(n.module.name^);
    END PrintImport;

  BEGIN
    CASE n.subcl OF
    | T.Mdecl:
      PBN(n);
      L('s');
      WS(n(T.Declaration).sym.name^);
      L('f');
      IF T.fwddecl IN n.flags THEN
        W('y')
      ELSE
        W('n');
      END;

    | T.Minittd:
      PrintInitTD(n(T.InitTD));

    | T.Mimport:
      PrintImport(n(T.Import));
    ELSE
      PBN(n);
    END;
  END PrintMisc;

  PROCEDURE PrintExpr(n : T.Expr);

    PROCEDURE PrintConst(n : T.Expr);
    BEGIN
      PBN(n);
      Pad(1);
      CASE n.type.form OF
      | ST.bool:
        WB(n.val.i0 = OPM.TrueVal);

      | ST.char:
        WN(n.val.i0);
        W('C');

      | ST.sint, ST.int, ST.lint:
        WN(n.val.i0);

      | ST.real:
        WS(rconst);

      | ST.lreal:
        WS(lrconst);

      | ST.set:
        WSet(n.val.set);

      | ST.string:
        W('"');
        WS(n.val.ext^);
        W('"');

      | ST.nil:
        WS(nil);
      END;
    END PrintConst;

    PROCEDURE PrintMExpr(n : T.MExpr);
    BEGIN
      PN(n.op);
      PBN(n);
      PNR('o', n.op);
      IF n.subcl IN {T.Einterfere, T.Eload} THEN
        L('r');
        WSet(n.regs);
      END;
    END PrintMExpr;

    PROCEDURE PrintDExpr(n : T.DExpr);
    BEGIN
      PN(n.lop);
      PN(n.rop);
      PBN(n);
      PNR('l', n.lop);
      PNR('r', n.rop);
    END PrintDExpr;

    PROCEDURE PrintIsTest(n : T.IsTest);
    BEGIN
      PN(n.var);
      PN(n.istype);
      PBN(n);
      PNR('v', n.var);
      PNR('t', n.istype);
    END PrintIsTest;

    PROCEDURE PA(x : T.Node);
      VAR
        n : T.Arg;
    BEGIN
      IF x # NIL THEN
        n := x(T.Arg);
        Ref(n);
        PA(n.next);
        PN(n.arg);
        PBN(n);
        PNR('a', n.arg);
        NL;
      END;
    END PA;

    PROCEDURE PrintFuncCall(n : T.FuncCall);
    BEGIN
      PA(n.args);
      PN(n.func);
      PBN(n);
      PNR('a', n.args);
      PNR('f', n.func);
    END PrintFuncCall;

  BEGIN
    IF n # NIL THEN
      CASE n.subcl OF
      | T.Enot..T.Econvert, T.Eaddress, T.Einterfere, T.Eload, T.Ecast:
        PrintMExpr(n(T.MExpr));

      | T.Etimes..T.Eupto, T.Eash, T.Elsh, T.Erot:
        PrintDExpr(n(T.DExpr));

      | T.Eis:
        PrintIsTest(n(T.IsTest));

      | T.Ecall:
        PrintFuncCall(n(T.FuncCall));

      | T.Econst:
        PrintConst(n);
      END;
    END;
  END PrintExpr;

  PROCEDURE PrintStmt(n : T.StmtList);

    PROCEDURE PBS(n : T.StmtList);
    BEGIN
      Ref(n.prev);
      PBN(n);
      PNR('p', n.prev);
    END PBS;

    PROCEDURE PrintEnter(n : T.Enter);
    BEGIN
      PNL(n.import);
      PNL(n.inittd);
      PNL(n.nestedproc);
      PNL(n.decl);
      PNL(n.body);
      PBS(n);
      PNR('N', n.nestedproc);
      PNR('b', n.body);
      PNR('i', n.import);
      PNR('t', n.inittd);
      Pad(1);
      IF n.info # NIL THEN
        WS(n.info.name^);
      END;
    END PrintEnter;

    PROCEDURE PrintAssign(n : T.Assign);
    BEGIN
      PN(n.lvalue);
      PN(n.rvalue);
      PBS(n);
      PNR('l', n.lvalue);
      PNR('r', n.rvalue);
    END PrintAssign;

    PROCEDURE PrintProcCall(n : T.ProcCall);
    BEGIN
      PN(n.call);
      PBS(n);
      PNR('c', n.call);
    END PrintProcCall;

    PROCEDURE PrintIfElse(n : T.IfElse);

      PROCEDURE PIB(x : T.Node);
        VAR
          n : T.IfBody;
      BEGIN
        IF x # NIL THEN
          n := x(T.IfBody);
          Ref(n);
          PIB(n.elsif);
          PN(n.cond);
          PNL(n.stmt);
          PBN(n);
          PNR('c', n.cond);
          PNR('s', n.stmt);
          PNR('e', n.elsif);
          NL;
        END;
      END PIB;
    BEGIN
      PIB(n.ifstat);
      PN(n.else);
      PBS(n);
      PNR('b', n.ifstat);
      PNR('e', n.else);
    END PrintIfElse;

    PROCEDURE PrintCase(n : T.Case);

      PROCEDURE PSC(x : T.Node);
        VAR
          n : T.SingleCase;
          b : T.CaseBounds;
      BEGIN
        IF x # NIL THEN
          n := x(T.SingleCase);
          Ref(n);
          b := n.bounds;
          PSC(n.next);
          PNL(n.stmt);
          PBN(n);
          PNR('s', n.stmt);
          L('r');
          W('[');
          WHILE b # NIL DO
            W('(');
            WN(b.bound.i0);
            W(',');
            WN(b.bound.i1);
            W(')');
            b := b.next;
            IF b # NIL THEN
              W(',');
            END;
          END;
          W(']');
          NL;
        END;
      END PSC;

      PROCEDURE PCS(n : T.CaseStat);
      BEGIN
        Ref(n);
        PSC(n.case);
        PNL(n.else);
        PBN(n);
        PNR('c', n.case);
        PNR('e', n.else);
        L('l');
        WN(n.range.i0);
        L('h');
        WN(n.range.i1);
      END PCS;

    BEGIN
      PN(n.expr);
      PCS(n.of);
      NL;
      PBS(n);
      PNR('e', n.expr);
      PNR('o', n.of);
    END PrintCase;

    PROCEDURE PrintLoop(n : T.Loop);
    BEGIN
      PNL(n.body);
      PBS(n);
      PNR('b', n.body);
    END PrintLoop;

    PROCEDURE PrintWRLoop(n : T.WhileRepeat);
    BEGIN
      PN(n.cond);
      PNL(n.body);
      PBS(n);
      PNR('c', n.cond);
      PNR('b', n.body);
    END PrintWRLoop;

    PROCEDURE PrintExit(n : T.StmtList);
    BEGIN
      PBS(n);
    END PrintExit;

    PROCEDURE PrintReturn(n : T.Return);
    BEGIN
      PN(n.expr);
      PBS(n);
      PNR('e', n.expr);
      IF n.proc # NIL THEN
        Pad(1);
        WS(n.proc.name^);
      END;
    END PrintReturn;

    PROCEDURE PrintWith(n : T.With);

      PROCEDURE PWL(x : T.Node);
        VAR
          n : T.WithList;
      BEGIN
        IF x # NIL THEN
          n := x(T.WithList);
          Ref(n);
          PWL(n.next);
          PN(n.control);
          PN(n.testtype);
          PNL(n.body);
          PBN(n);
          PNR('c', n.control);
          PNR('t', n.testtype);
          PNR('b', n.body);
          NL;
        END;
      END PWL;

    BEGIN
      PWL(n.wstat);
      PNL(n.else);
      PBS(n);
      PNR('w', n.wstat);
      PNR('e', n.else);
    END PrintWith;

    PROCEDURE PrintFor(n : T.For);
    BEGIN
      PN(n.control);
      PN(n.lower);
      PN(n.upper);
      PNL(n.body);
      PBS(n);
      PNR('c', n.control);
      PNR('l', n.lower);
      PNR('u', n.upper);
      L('s');
      WN(n.step);
      PNR('b', n.body);
    END PrintFor;

    PROCEDURE PrintHalt(n : T.Halt);
    BEGIN
      PN(n.expr);
      PN(n.val);
      PBS(n);
      PNR('e', n.expr);
      PNR('v', n.val);
    END PrintHalt;

  BEGIN
    CASE n.subcl OF
    | T.Snull:
      PBS(n);

    | T.Senter:
      PrintEnter(n(T.Enter));

    | T.Sassign:
      PrintAssign(n(T.Assign));

    | T.Scall:
      PrintProcCall(n(T.ProcCall));

    | T.Sifelse:
      PrintIfElse(n(T.IfElse));

    | T.Scase:
      PrintCase(n(T.Case));

    | T.Swhile, T.Srepeat:
      PrintWRLoop(n(T.WhileRepeat));

    | T.Sloop:
      PrintLoop(n(T.Loop));

    | T.Sexit:
      PrintExit(n(T.StmtList));

    | T.Sreturn:
      PrintReturn(n(T.Return));

    | T.Swith:
      PrintWith(n(T.With));

    | T.Sfor:
      PrintFor(n(T.For));

    | T.Sassert:
      PrintHalt(n(T.Halt));
    END;
  END PrintStmt;

  PROCEDURE PN(n : T.Node);
  BEGIN
    IF n # NIL THEN
      Ref(n);
      CASE n.class OF
      | T.Ndsgn:
        PrintDesign(n(T.Design));

      | T.Nstmt:
        PrintStmt(n(T.StmtList));

      | T.Nexpr:
        PrintExpr(n(T.Expr));

      | T.Nmisc:
        PrintMisc(n);
      END;
      NL;
    END;
  END PN;

  PROCEDURE PNL(n : T.Node);
  BEGIN
    WHILE n # NIL DO
      PN(n);
      n := n.next;
    END;
  END PNL;

  PROCEDURE Dump*(n : T.Node);
  BEGIN
    nofNodes := 0;
    NL;
    PNL(n);
  END Dump;

BEGIN
  type[ST.undef    ] := 'undef ';
  type[ST.bool     ] := 'bool  ';
  type[ST.byte     ] := 'byte  ';
  type[ST.char     ] := 'char  ';
  type[ST.sint     ] := 'sint  ';
  type[ST.int      ] := 'int   ';
  type[ST.lint     ] := 'lint  ';
  type[ST.real     ] := 'real  ';
  type[ST.lreal    ] := 'lreal ';
  type[ST.set      ] := 'set   ';
  type[ST.string   ] := 'string';
  type[ST.nil      ] := 'nil   ';
  type[ST.void     ] := 'notyp ';
  type[ST.pointer  ] := 'ptr   ';
  type[ST.procedure] := 'proc  ';
  type[ST.array    ] := 'array ';
  type[ST.dynarr   ] := 'dynarr';
  type[ST.record   ] := 'record';

  class[T.Ndsgn] := 'Ndsgn';
  class[T.Nstmt] := 'Nstmt';
  class[T.Nexpr] := 'Nexpr';
  class[T.Nmisc] := 'Nmisc';

  dsgn[T.Danon        ] := 'Danon      ';
  dsgn[T.Dvar         ] := 'Dvar       ';
  dsgn[T.Dpar         ] := 'Dpar       ';
  dsgn[T.Dvarpar      ] := 'Dvarpar    ';
  dsgn[T.Dconst       ] := 'Dconst     ';
  dsgn[T.Dstdproc     ] := 'Dstdproc   ';
  dsgn[T.Dfwdproc     ] := 'Dfwdproc   ';
  dsgn[T.Dlproc       ] := 'Dlproc     ';
  dsgn[T.Dxproc       ] := 'Dxproc     ';
  dsgn[T.Dcproc       ] := 'Dcproc     ';
  dsgn[T.Diproc       ] := 'Diproc     ';
  dsgn[T.Dmethod      ] := 'Dmethod    ';
  dsgn[T.Dfield       ] := 'Dfield     ';
  dsgn[T.Dtype        ] := 'Dtype      ';
  dsgn[T.Dmodule      ] := 'Dmodule    ';
  dsgn[T.Dscope       ] := 'Dscope     ';
  dsgn[T.Ddarrdesc    ] := 'Ddarrdesc  ';
  dsgn[T.Darrdesc     ] := 'Darrdesc   ';
  dsgn[T.Drecdesc     ] := 'Drecdesc   ';
  dsgn[T.Dderef       ] := 'Dderef     ';
  dsgn[T.Dindex       ] := 'Dindex     ';
  dsgn[T.Diguard      ] := 'Diguard    ';
  dsgn[T.Deguard      ] := 'Deguard    ';
  dsgn[T.Dproc        ] := 'Dproc      ';
  dsgn[T.Dcommon      ] := 'Dcommon    ';
  dsgn[T.Dcast        ] := 'Dcast      ';

  stmt[T.Snull        ] := 'Snull      ';
  stmt[T.Senter       ] := 'Senter     ';
  stmt[T.Sassign      ] := 'Sassign    ';
  stmt[T.Scall        ] := 'Scall      ';
  stmt[T.Sifelse      ] := 'Sifelse    ';
  stmt[T.Scase        ] := 'Scase      ';
  stmt[T.Swhile       ] := 'Swhile     ';
  stmt[T.Srepeat      ] := 'Srepeat    ';
  stmt[T.Sloop        ] := 'Sloop      ';
  stmt[T.Sexit        ] := 'Sexit      ';
  stmt[T.Sreturn      ] := 'Sreturn    ';
  stmt[T.Swith        ] := 'Swith      ';
  stmt[T.Sfor         ] := 'Sfor       ';
  stmt[T.Sassert      ] := 'Sassert    ';

  expr[T.Enot         ] := 'Enot       ';
  expr[T.Euminus      ] := 'Euminus    ';
  expr[T.Euplus       ] := 'Euplus     ';
  expr[T.Econvert     ] := 'Econvert   ';
  expr[T.Etimes       ] := 'Etimes     ';
  expr[T.Ediv         ] := 'Ediv       ';
  expr[T.Eslash       ] := 'Eslash     ';
  expr[T.Emsk         ] := 'Emsk       ';
  expr[T.Emod         ] := 'Emod       ';
  expr[T.Eplus        ] := 'Eplus      ';
  expr[T.Eminus       ] := 'Eminus     ';
  expr[T.Eand         ] := 'Eand       ';
  expr[T.Eor          ] := 'Eor        ';
  expr[T.Eeql         ] := 'Eeql       ';
  expr[T.Eneq         ] := 'Eneq       ';
  expr[T.Elss         ] := 'Elss       ';
  expr[T.Eleq         ] := 'Eleq       ';
  expr[T.Egtr         ] := 'Egtr       ';
  expr[T.Egeq         ] := 'Egeq       ';
  expr[T.Ein          ] := 'Ein        ';
  expr[T.Eupto        ] := 'Eupto      ';
  expr[T.Eis          ] := 'Eis        ';
  expr[T.Ecall        ] := 'Ecall      ';
  expr[T.Econst       ] := 'Econst     ';
  expr[T.Eaddress     ] := 'Eaddress   ';
  expr[T.Eash] := 'Eash       ';
  expr[T.Elsh] := 'Elsh       ';
  expr[T.Erot] := 'Erot       ';

  expr[T.Einterfere] := 'Einterfere ';
  expr[T.Eload] := 'Eload      ';
  expr[T.Ecast] := 'Ecast      ';

  misc[T.Merror       ] := 'Merror     ';
  misc[T.Mnone        ] := 'Mnone      ';
  misc[T.Mnop         ] := 'Mnop       ';
  misc[T.Marg         ] := 'Marg       ';
  misc[T.Mdecl        ] := 'Mdecl      ';
  misc[T.Mifbody      ] := 'Mifbody    ';
  misc[T.Mwithlist    ] := 'Mwithlist  ';
  misc[T.Msglcase     ] := 'Msglcase   ';
  misc[T.Mcasestat    ] := 'Mcasestat  ';
  misc[T.Minittd      ] := 'Minittd    ';
  misc[T.Mimport      ] := 'Mimport    ';


  nil[0] := 'n';
  nil[1] := 'i';
  nil[2] := 'l';
  nil[3] := 0X;

  true[0] := 't';
  true[1] := 'r';
  true[2] := 'u';
  true[3] := 'e';
  true[4] := 0X;

  false[0] := 'f';
  false[1] := 'a';
  false[2] := 'l';
  false[3] := 's';
  false[4] := 'e';
  false[5] := 0X;

  rconst[0] := 'r';
  rconst[1] := 'e';
  rconst[2] := 'a';
  rconst[3] := 'l';
  rconst[4] := 0X;

  lrconst[0] := 'l';
  lrconst[1] := 'r';
  lrconst[2] := 'l';
  lrconst[3] := ' ';
  lrconst[4] := 0X;
END SKLDN.
