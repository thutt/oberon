(* O3GSANames: Opcode class and subclass text representations *)
MODULE O3GSANames;
  IMPORT
    Types,
    Config := O3Config,
    GSAOpcode := O3GSAOpcode, 
    GSAData := O3GSAData;

CONST
  nofClasses = GSAOpcode.OpcodeClassEnd - GSAOpcode.OpcodeClassBegin;

TYPE
  Class* = ARRAY 16 OF CHAR;
  Subclass* = ARRAY 16 OF CHAR;
  Attribute* = ARRAY 16 OF CHAR;

VAR
  access     : POINTER TO ARRAY OF Subclass;
  alias      : POINTER TO ARRAY OF Subclass;
  attributes : POINTER TO ARRAY OF Attribute;
  class      : POINTER TO ARRAY nofClasses OF Class;
  guard      : POINTER TO ARRAY OF Subclass;
  hwdreg     : POINTER TO ARRAY OF Subclass;
  memory     : POINTER TO ARRAY OF Subclass;
  merge      : POINTER TO ARRAY OF Subclass;
  misc       : POINTER TO ARRAY OF Subclass;
  nlm        : POINTER TO ARRAY OF Subclass;
  pseudomisc : POINTER TO ARRAY OF Subclass;
  region     : POINTER TO ARRAY OF Subclass;
  system     : POINTER TO ARRAY OF Subclass;
  trap       : POINTER TO ARRAY OF Subclass;
  typedesc   : POINTER TO ARRAY OF Subclass;

PROCEDURE DecodeClass*(n : GSAData.Info; VAR p : Class);
  VAR name : Types.Name;
BEGIN 
  WITH n:GSAData.Instruction DO COPY(class[n.class], p);
  | n:GSAData.Result DO COPY("result", p);
  | n:GSAData.Type DO COPY("type", p);
  | n:GSAData.Temporary DO COPY("temporary", p);
  | n:GSAData.Symbol DO COPY("symbol", p);
  | n:GSAData.ConstSet DO COPY("const set", p);
  | n:GSAData.ConstIntRange DO COPY("const intrange", p);
  | n:GSAData.ConstInt DO COPY("const int", p);
  | n:GSAData.ConstBool DO COPY("const bool", p);
  | n:GSAData.ConstReal DO COPY("const real", p);
  | n:GSAData.ConstLReal DO COPY("const lreal", p);
  | n:GSAData.ConstString DO COPY("const string", p);
  ELSE Types.NameOf(Types.TypeOf(n), name); COPY(name^, p);
  END;
END DecodeClass;

PROCEDURE OpcodeClass*(s : INTEGER; VAR p : Class);
BEGIN p := class[s];
END OpcodeClass;

PROCEDURE ArithSubclass*(s : INTEGER; VAR p : Subclass);
BEGIN
  CASE s OF
  | GSAOpcode.asS1: COPY('s1', p);
  | GSAOpcode.asU1: COPY('u1', p);
  | GSAOpcode.asS2: COPY('s2', p);
  | GSAOpcode.asU2: COPY('u2', p);
  | GSAOpcode.asS4: COPY('s4', p);
  | GSAOpcode.asU4: COPY('u4', p);
  | GSAOpcode.asR8: COPY('r8', p);
  | GSAOpcode.asR4: COPY('r4', p);
  | GSAOpcode.asST: COPY('st', p);
  END;
END ArithSubclass;

PROCEDURE DecodeSubclass*(n : GSAData.Info; VAR p : Subclass);
  VAR name : Types.Name;
BEGIN
  WITH n:GSAData.Instruction DO 
    CASE n.class OF
    | GSAOpcode.Maccess, GSAOpcode.Mupdate: COPY(access[n.subcl], p);
    | GSAOpcode.Mmemory: COPY(memory[n.subcl], p);
    | GSAOpcode.Mregion: COPY(region[n.subcl], p);
    | GSAOpcode.Abegin..GSAOpcode.Aend-1: ArithSubclass(n.subcl, p);
    | GSAOpcode.Lbegin..GSAOpcode.Lend-1: ArithSubclass(n.subcl, p);
    | GSAOpcode.Hbegin..GSAOpcode.Hend-1: ArithSubclass(n.subcl, p);
    | GSAOpcode.Cbegin..GSAOpcode.Cend-1: ArithSubclass(n.subcl, p);
    | GSAOpcode.Sbegin..GSAOpcode.Send-1: ArithSubclass(n.subcl, p);
    | GSAOpcode.Tbegin..GSAOpcode.Tend-1: COPY(trap[n.subcl], p);
    | GSAOpcode.Gmisc:   COPY(misc[n.subcl], p);
    | GSAOpcode.Palias:  COPY(alias[n.subcl], p);
    | GSAOpcode.Phwdreg: COPY(hwdreg[n.subcl], p);
    | GSAOpcode.Pnlm:    COPY(nlm[n.subcl], p);
    | GSAOpcode.Pmisc:   COPY(pseudomisc[n.subcl], p);
    | GSAOpcode.Gsystem: COPY(system[n.subcl], p);
    | GSAOpcode.Gguard:  COPY(guard[n.subcl], p);
    | GSAOpcode.Gmerge:  COPY(merge[n.subcl], p);
    | GSAOpcode.Gtypedesc: COPY(typedesc[n.subcl], p);
    ELSE COPY('invalid', p);
    END;
  ELSE Types.NameOf(Types.TypeOf(n), name); COPY(name^, p);
  END;
END DecodeSubclass;

PROCEDURE Decode*(n : GSAData.Info; VAR class : Class; VAR subcl : Subclass);
BEGIN DecodeClass(n, class); DecodeSubclass(n, subcl);
END Decode;

PROCEDURE WDecode*(n : GSAData.Info);
  VAR
    c : Class;
    s : Subclass;
BEGIN
  Decode(n, c, s); 
  Config.LogWStr('Node={'); Config.LogWStr(c);
  Config.LogWStr(', '); Config.LogWStr(s); Config.LogW('}');
END WDecode;

PROCEDURE DecodeAttribute*(i : INTEGER; VAR attr : Attribute);
BEGIN
  COPY(attributes[i], attr);
END DecodeAttribute;


PROCEDURE Initialize;
BEGIN
  NEW(class);
  class[GSAOpcode.Maccess] := 'access';
  class[GSAOpcode.Mupdate] := 'update';
  class[GSAOpcode.Mmemory] := 'memory';
  class[GSAOpcode.Mregion] := 'region';
  class[GSAOpcode.Aabs] := 'abs';
  class[GSAOpcode.Aneg] := 'neg';
  class[GSAOpcode.Aadd] := 'add';
  class[GSAOpcode.Asub] := 'sub';
  class[GSAOpcode.Adiv] := 'div';
  class[GSAOpcode.Amul] := 'mul';
  class[GSAOpcode.Amod] := 'mod';
  class[GSAOpcode.Aodd] := 'odd';
  class[GSAOpcode.Aconvert] := 'convert';
  class[GSAOpcode.Anot] := 'not';
  class[GSAOpcode.Lrol] := 'rol';
  class[GSAOpcode.Lror] := 'ror';
  class[GSAOpcode.Llsl] := 'lsl';
  class[GSAOpcode.Llsr] := 'lsr';
  class[GSAOpcode.Lasl] := 'asl';
  class[GSAOpcode.Lasr] := 'asr';

  class[GSAOpcode.Hget] := 'get';
  class[GSAOpcode.Hput] := 'put';
  class[GSAOpcode.Hgetreg] := 'getreg';
  class[GSAOpcode.Hputreg] := 'putreg';
  class[GSAOpcode.Hmemr] := 'memr';
  class[GSAOpcode.Hmemw] := 'memw';

  class[GSAOpcode.Ceql] := 'eql';
  class[GSAOpcode.Cneq] := 'neq';
  class[GSAOpcode.Clss] := 'lss';
  class[GSAOpcode.Cleq] := 'leq';
  class[GSAOpcode.Cgtr] := 'gtr';
  class[GSAOpcode.Cgeq] := 'geq';
    
  class[GSAOpcode.Sdiff] := 'set-diff';
  class[GSAOpcode.Sunion] := 'set-union';
  class[GSAOpcode.Ssub] := 'set-sub';
  class[GSAOpcode.Sintersection] := 'set-intersect';
  class[GSAOpcode.Sneg] := 'set-neg';
  class[GSAOpcode.Sincl] := 'set-incl';
  class[GSAOpcode.Sexcl] := 'set-excl';
  class[GSAOpcode.Srange] := 'set-range';
  class[GSAOpcode.Selement] := 'set-element';
  class[GSAOpcode.Sconvert] := 'set-convert';
  
  class[GSAOpcode.Ttrap] := 'trap';

  class[GSAOpcode.Gmisc] := 'misc';
  class[GSAOpcode.Gsystem] := 'system';
  class[GSAOpcode.Gguard] := 'guard';
  class[GSAOpcode.Gmerge] := 'merge';
  class[GSAOpcode.Gtypedesc] := 'typedesc';
  class[GSAOpcode.Palias] := 'alias';
  class[GSAOpcode.Phwdreg] := 'hwdreg';
  class[GSAOpcode.Pnlm] := 'nlm';

  NEW(access, 6);
  access[GSAOpcode.Mfield] := 'field';
  access[GSAOpcode.Melement] := 'element';
  access[GSAOpcode.Mderef] := 'deref';
  access[GSAOpcode.Mnonlocal] := 'nonlocal';
  access[GSAOpcode.Mvarparm] := 'varparm';

  NEW(misc, 3);
  misc[GSAOpcode.Gcall] := 'call';
  misc[GSAOpcode.Gcopy] := 'copy';
  misc[GSAOpcode.Gcap] := 'cap';

  NEW(pseudomisc, 2);
  pseudomisc[GSAOpcode.Pgate] := 'gate';
  pseudomisc[GSAOpcode.Pimport] := 'import';

  NEW(alias, 4);
  alias[GSAOpcode.Pnoalias] := 'noalias';
  alias[GSAOpcode.Pmayalias] := 'mayalias';
  alias[GSAOpcode.Pdoesalias] := 'doesalias';
  alias[GSAOpcode.Paliasasgn] := 'aliasasgn';

  NEW(hwdreg, 2);
  hwdreg[GSAOpcode.Pmovetoreg] := 'movetoreg';
  hwdreg[GSAOpcode.Pmovefromreg] := 'movefromreg';

  NEW(system, 7);
  system[GSAOpcode.Gbit] := 'bit';
  system[GSAOpcode.Gnewblock] := 'newblock';
  system[GSAOpcode.Gmove] := 'move';
  system[GSAOpcode.Gresetbit] := 'reset-bit';
  system[GSAOpcode.Gsetbit] := 'set-bit';
  system[GSAOpcode.Gfinalize] := 'finalize';
  system[GSAOpcode.Gcondcode] := 'cc';

  NEW(guard, 6);
  guard[GSAOpcode.Gtrue] := 'guard-true';
  guard[GSAOpcode.Gfalse] := 'guard-false';
  guard[GSAOpcode.Gcasesgl] := 'guard-case';
  guard[GSAOpcode.Gcaseelse] := 'guard-celse';
  guard[GSAOpcode.Gbackedge] := 'guard-backedge';
  guard[GSAOpcode.Gexit] := 'guard-exit';

  NEW(merge, 4);
  merge[GSAOpcode.Gif] := 'merge-if';
  merge[GSAOpcode.Gcond] := 'merge-cond';
  merge[GSAOpcode.Gloop] := 'merge-loop';
  merge[GSAOpcode.Gcase] := 'merge-case';

  NEW(typedesc, 3);
  typedesc[GSAOpcode.Ginitrec] := 'init-rectd';
  typedesc[GSAOpcode.Ginitarr] := 'init-arrtd';
  typedesc[GSAOpcode.Ginitdarr] := 'init-darrtd';

  NEW(memory, 11);
  memory[GSAOpcode.Madr] := 'adr';
  memory[GSAOpcode.Mtbpadr] := 'tbpadr';
  memory[GSAOpcode.Mdynarrlen] := 'dynarrlen';
  memory[GSAOpcode.Mheaptag] := 'heaptag';
  memory[GSAOpcode.Minitialize] := 'initialize';
  memory[GSAOpcode.Mstringcopy] := 'stringcopy';
  memory[GSAOpcode.Marraycopy] := 'arraycopy';
  memory[GSAOpcode.Mrecordcopy] := 'recordcopy';
  memory[GSAOpcode.Mnewrecord] := 'newrecord';
  memory[GSAOpcode.Mnewarray] := 'newarray';
  memory[GSAOpcode.Mnewdynarray] := 'newdynarray';
  
  NEW(nlm, 2);
  nlm[GSAOpcode.Pdtor] := 'dtor';
  nlm[GSAOpcode.Pctor] := 'ctor';

  NEW(region, 6);
  region[GSAOpcode.Mgreg] := 'greg';
  region[GSAOpcode.Mreg] := 'reg';
  region[GSAOpcode.Mcasereg] := 'case';
  region[GSAOpcode.Menter] := 'enter';
  region[GSAOpcode.Mexit] := 'exit';
  region[GSAOpcode.Mbody] := 'body';
  
  NEW(trap, 10);
  trap[GSAOpcode.Tindex] := 'index';
  trap[GSAOpcode.Trange] := 'range';
  trap[GSAOpcode.Teguard] := 'eguard';
  trap[GSAOpcode.Tiguard] := 'iguard';
  trap[GSAOpcode.Treturn] := 'return';
  trap[GSAOpcode.Tcase] := 'case';
  trap[GSAOpcode.Tassert] := 'assert';
  trap[GSAOpcode.Thalt] := 'halt';
  trap[GSAOpcode.Twith] := 'with';
  trap[GSAOpcode.Tnil] := 'nil';

  NEW(attributes, 2);
  attributes[GSAData.raLive] := "raLive";                (* Forced always-live.
                                                          * A live instruction's operands
                                                          * must also always be marked live.
                                                          *)
  attributes[GSAData.raUniqueResult] := "unique result"; (* Every return value is unique
                                                          * Example: NEW.
                                                          *)
END Initialize;

BEGIN Initialize;
END O3GSANames.
