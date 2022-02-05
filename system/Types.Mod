MODULE Types;
  IMPORT SYSTEM, Modules, Kernel, Console;

  TYPE
    ADDRESS = LONGINT;
    Name* = Kernel.Name;
    Type* = Kernel.TypeDesc;

  PROCEDURE This*(mod: Modules.Module; name: ARRAY OF CHAR): Type;
    VAR type: Type; i, j, addr: LONGINT; ch : CHAR;
  BEGIN
    IF name # "" THEN
      i := LEN(mod.tdescs^);
      WHILE i > 0 DO
        DEC(i); type := SYSTEM.VAL(Type, mod.tdescs[i]);
        IF type.name # 0 (* NIL *) THEN addr := type.name; j := 0;
          LOOP SYSTEM.GET(addr, ch);
            IF (j > LEN(name)) OR (ch # name[j]) THEN EXIT;
            ELSIF ch = 0X THEN RETURN type;
            END;
            INC(j); INC(addr);
          END;
        ELSE RETURN NIL;
        END;
      END
    END ;
    RETURN NIL
  END This;

  PROCEDURE ModuleOf*(t : Type) : Modules.Module;
  BEGIN RETURN SYSTEM.VAL(Modules.Module, t.module);
  END ModuleOf;
  
  PROCEDURE BaseOf*(t: Type; level: INTEGER): Type;
  BEGIN (* t.ancesotr is the address of the extension table *)
    IF level <= t.extLev THEN SYSTEM.GET(t.ancestor + level * SIZE(ADDRESS), t); RETURN t
    ELSE RETURN NIL;
    END;
  END BaseOf;

  PROCEDURE LevelOf*(t: Type): INTEGER;
  BEGIN RETURN SHORT(t.extLev);
  END LevelOf;

  PROCEDURE TypeOf*(o: SYSTEM.PTR): Type;
    VAR type: Type;
  BEGIN SYSTEM.GET(SYSTEM.VAL(LONGINT, o) - 4, type); RETURN type;
  END TypeOf;

  PROCEDURE NameOf*(t : Type; VAR name : Name);
    VAR i, addr : LONGINT; ch : CHAR;
  BEGIN
    IF t.name # 0 THEN addr := t.name; i := 0;
      REPEAT SYSTEM.GET(addr, ch); INC(addr); INC(i); UNTIL ch = 0X;
      NEW(name, i);
      REPEAT DEC(addr); SYSTEM.GET(addr, ch); DEC(i); name[i] := ch; UNTIL i = 0;
    ELSE name := NIL;
    END;
  END NameOf;

  PROCEDURE NewObj*(VAR o: SYSTEM.PTR; t: Type);
    CONST EAX = 0; ECX = 1; EDX = 2;
    VAR otype: Type;
  BEGIN
    SYSTEM.GET(SYSTEM.VAL(LONGINT, o) - 4, otype); otype := SYSTEM.VAL(Type, o);
    IF BaseOf(t, LevelOf(otype)) # otype THEN o := NIL; RETURN END;
    SYSTEM.PUTREG(EDX, t);
    SYSTEM.PUTREG(EAX, SYSTEM.ADR(o));
    Kernel.NewRecord;
  END NewObj;

END Types.
