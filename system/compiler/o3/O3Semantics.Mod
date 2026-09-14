MODULE O3Semantics; (* semantic rules of the Oberon3 language (type equivalence, compatibility, etc) *)
  IMPORT
    Config := O3Config,
    Symtab := O3Symtab,
    AST := O3TreeNode,
    ASTH := O3TreeHelper,
    E := O3Errors;

  VAR
    level* : SHORTINT;

  PROCEDURE ExprCompatPointer*(ext, base : Symtab.Type) : BOOLEAN;
    VAR b, e : Symtab.Type;
  BEGIN (* ASSERT(ext.type.form = pointer); *)
    IF base.form = Symtab.pointer THEN
      b := base(Symtab.Pointer).to; e := ext(Symtab.Pointer).to; RETURN Symtab.Extends(b, e) OR Symtab.Extends(e, b);
    ELSIF base.form = Symtab.nil THEN RETURN TRUE;
    ELSE RETURN FALSE;
    END;
  END ExprCompatPointer;

  PROCEDURE CheckParamMatch*(ap, fp : Symtab.Symbol; checkNames : BOOLEAN);
    VAR ft, at : Symtab.Type; fpt, apt : Symtab.Procedure;
  BEGIN
    WHILE fp # NIL DO
      IF ap # NIL THEN
        ft := fp.type; at := ap.type;
        WHILE (ft.form = Symtab.openarr) & (at.form = Symtab.openarr) DO
          ft := ft(Symtab.Array).of; at := at(Symtab.Array).of
        END;
        IF ft # at THEN
          IF (ft.form = Symtab.procedure) & (at.form = Symtab.procedure) THEN
            fpt := ft(Symtab.Procedure); apt := at(Symtab.Procedure);
            IF fpt.result = apt.result THEN CheckParamMatch(apt.parms, fpt.parms, FALSE);
            ELSE Config.Error(E.ResultMismatch);
            END;
          ELSE Config.Error(E.ParmMismatch);
          END;
        END;
        IF (fp.kind # ap.kind) OR checkNames & (fp.name^ # ap.name^) THEN Config.Error(E.ParmMismatch) END;
        ap := Symtab.NextParm(ap);
      ELSE Config.Error(E.ParamCountsDiffer);
      END;
      fp := Symtab.NextParm(fp);
    END;
    IF ap # NIL THEN Config.Error(E.ParamCountsDiffer); END;
  END CheckParamMatch;

  PROCEDURE AssignCompat*(to: Symtab.Type; from: AST.Expr) : AST.Expr; (* x := y *)
    VAR
      t, f : SHORTINT;
      ft : Symtab.Type;
      toArr : Symtab.Array;
      error : BOOLEAN;

    PROCEDURE CheckProc(to : Symtab.Procedure; fromSym : Symtab.Symbol);
    BEGIN
      IF fromSym.kind IN {Symtab.var, Symtab.par, Symtab.varpar,
                          Symtab.lproc, Symtab.xproc,
                          Symtab.cproc, Symtab.iproc} THEN
        IF (fromSym.kind = Symtab.lproc) & (fromSym.mnolev # 0) THEN
          Config.Error(E.MustBeGlobalProc)
        END;
        IF to.result = fromSym.type(Symtab.Procedure).result THEN
          CheckParamMatch(to.parms, fromSym.type(Symtab.Procedure).parms, FALSE);
          IF to.sysflag # from.type.sysflag THEN
            Config.Error(E.IncompatibleAssignment);
          END;
        ELSE
          Config.Error(E.ResultMismatch);
        END;
      ELSE
        Config.Error(E.IncompatibleAssignment);
      END;
    END CheckProc;

  BEGIN
    t := to.form; ft := from.type; f := ft.form; error := FALSE;
    CASE t OF
    |  Symtab.undef: (* erroneous type, don't make more errors *)

    |  Symtab.byte:
       IF ~(f IN {Symtab.byte, Symtab.char, Symtab.sint}) THEN
         error := TRUE;
       END;

    |  Symtab.bool, Symtab.char, Symtab.sint, Symtab.set:
       IF t # f THEN
         error := TRUE;
       END;

    |  Symtab.int:
       IF ~(f IN {Symtab.sint, Symtab.int}) THEN
         error := TRUE
       ELSIF f = Symtab.sint THEN
         from := ASTH.NewConvert(from, to);
       END;

    |  Symtab.lint:
       IF ~(f IN Symtab.IntSet) THEN
         error := TRUE;
       ELSIF f IN {Symtab.sint, Symtab.int} THEN
         from := ASTH.NewConvert(from, to);
       END;

    |  Symtab.real:
       IF ~(f IN Symtab.IntSet + {Symtab.real}) THEN
         error := TRUE;
       ELSIF f IN Symtab.IntSet THEN
         from := ASTH.NewConvert(from, to);
       END;

    |  Symtab.lreal:
       IF ~(f IN Symtab.NumSet) THEN
         error := TRUE;
       ELSIF f IN Symtab.IntSet + {Symtab.real} THEN
         from := ASTH.NewConvert(from, to);
       END;

    |  Symtab.void, Symtab.nil:
       error := TRUE;

    |  Symtab.pointer:
       IF (to = ft) OR (f = Symtab.nil) OR (to = Symtab.sysptrtyp) &
                                           (f = Symtab.pointer) THEN (* valid *)
       ELSIF f = Symtab.pointer THEN
         IF ~Symtab.Extends(ft, to) THEN
           error := TRUE;
         END;
       ELSE
         error := TRUE;
       END;

    |  Symtab.procedure:
       IF (to = ft) OR (f = Symtab.nil) THEN  (* valid *)
       ELSIF from.type.form = Symtab.procedure THEN
         CheckProc(to(Symtab.Procedure), from(AST.Design).sym);
       ELSE
         error := TRUE;
       END;

    |  Symtab.array:
       INCL(to.flags, Symtab.pvused); (* idfp of 'from' guarantees assignment
                                       * compatibility with 'to' *)
       toArr := to(Symtab.Array);
       IF (AST.constant IN from.flags) & (f = Symtab.char) THEN
         from := ASTH.NewConvert(from(AST.Expr), Symtab.stringtyp);
         ft := from.type;
         f := Symtab.string;
       END;
       IF toArr = ft THEN (* valid *)
       ELSIF (f = Symtab.string) & (toArr.of = Symtab.chartyp) THEN (* string length valid? *)
         (*
          If a string literal is being assigned to an array variable, then it is
          either a character constant or a true string literal.  If it is a
          character constant, an Econvert node will be inserted into the tree.  If
          it is a string, then it will be an Ndsgn node since the compiler turns
          true string literals into compiler-generated constants.
          *)
         IF (from.class = AST.Ndsgn) & (from.subcl = AST.Dconst) THEN
           IF from(AST.Design).sym(Symtab.SymbolConst).val.i0 > toArr.n THEN
             Config.Error(E.StringDoesNotFit);
           END;
         ELSE
           ASSERT(from.class = AST.Nexpr, 1000);
           ASSERT(from.subcl = AST.Econvert, 1001);
         END;
       ELSE
         error := TRUE;
       END;

    |  Symtab.record:
       INCL(to.flags, Symtab.pvused); (* idfp of 'from' guarantees
                                       * assignment compatibility with 'to' *)
       IF ~Symtab.Extends(from.type, to) THEN
         error := TRUE;
       END;

    |  Symtab.dynarr, Symtab.openarr:
       error := TRUE;
    END;
    IF error THEN Config.Error(E.IncompatibleAssignment);
    ELSIF (AST.constant IN from.flags) & (f < t) &
          (f >= Symtab.sint) & (t IN Symtab.NumSet) THEN
      from := ASTH.NewConvert(from, to); (* variable type conversions handled
                                          * when processing operators *)
    END;
    RETURN from;
  END AssignCompat;

  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN RETURN TRUE;
  END ModuleEnd;

BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
END O3Semantics.
