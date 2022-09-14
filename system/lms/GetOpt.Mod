(* Copyright (c) 2022 Logic Magicians Software *)
MODULE GetOpt;
IMPORT Kernel, CommandLine, Console;

TYPE
  Status* = SHORTINT;

CONST (* Status values *)
  Success*  = 0;
  NotFound* = 1;
  Error*    = 2;
  Done*     = 3;

CONST (* Option flags *)
  ValueNeeded* = 0;  (* ValueNeeded ==> next argument is value of option.
                      * ~Valueneeded ==> argument is boolean. *)

CONST (* Option parse-recognition values *)
  ValueHelp*      = 0;          (* Reserved. *)
  ValueArgument*  = 1;          (* Program argument, not an option. *)
  ValueMin*       = 64;         (* First user-supplied option value. *)
  ValueMax*       = 256;        (* Last user-supplied option value. *)

CONST
  EOL = 0FFX;                   (* End-of-line.  Must be > ' '. *)

CONST (* Internal tokens *)
  tkEol      = 0;              (* End-of-line *)
  tkError    = 1;
  tkShortOpt = 2;              (* '-' *)
  tkLongOpt  = 3;              (* '--' *)
  tkIdent    = 4;              (* <identifier> *)

TYPE
  Text = POINTER TO ARRAY OF CHAR;

  Option = POINTER TO OptionDesc;
  OptionDesc = RECORD
    next  : Option;
    value : INTEGER;            (* Value used to signify this option. *)
    flags : SET;
    help  : Text;               (* Help text. *)
    name  : Text;               (* Long option name (ex: '--output'). *)
    short : CHAR;               (* Short option name (0X if none). *)
  END;

  Identifier = RECORD
    beg, end : INTEGER;         (* Open ended range: [beg, end) *)
  END;

  Handle* = POINTER TO HandleDesc;
  HandleDesc = RECORD
    index   : INTEGER;        (* Character index into 'cmdline'. *)
    ch      : CHAR;           (* Current charcter. *)
    options : Option;         (* Unordered list; inv: options # NIL *)
    cmdline : POINTER TO ARRAY OF CHAR;
    ident   : Identifier;       (* cmdline[h.ident.beg..h.ident.end) *)
  END;

  (* Argument parsed from command line. *)
  ArgumentDesc* = RECORD
    option    : Option;
    argument- : CommandLine.Parameter;
    value-    : INTEGER;
  END;


PROCEDURE NewText(s : ARRAY OF CHAR) : Text;
  VAR
    res : Text;
BEGIN
  NEW(res, LEN(s));             (* inv: LEN includes 0X. *)
  COPY(s, res^);
  RETURN res;
END NewText;


PROCEDURE CreateOption(value : INTEGER;
                       flags : SET;
                       short : CHAR;
                       name  : ARRAY OF CHAR;
                       help  : ARRAY OF CHAR) : Option;
  VAR
    opt : Option;
BEGIN
  NEW(opt);
  opt.next  := NIL;
  opt.value := value;
  opt.flags := flags;
  opt.short := short;
  opt.name  := NewText(name);
  opt.help  := NewText(help);
  RETURN opt;
END CreateOption;


(* ValueAllowed:
 *
 *   Ensures that 'value' is within the allowable range of
 *   option numerical values, and that 'value' is not already used.
 *)
PROCEDURE ValueAllowed(h : Handle; value : INTEGER) : BOOLEAN;
  VAR
    res : BOOLEAN;
    opt : Option;
BEGIN
  res := (value >= ValueMin) & (value <= ValueMax);
  opt := h.options;
  WHILE res & (opt # NIL) DO
    res := value # opt.value;
    opt := opt.next;
  END;

  (* res = TRUE  => 'value' is valid and not used.
   * res = FALSE => 'value' is invalid or already used.
   *)
  RETURN res;
END ValueAllowed;


(* Present
 *
 *   Returns TRUE iff either 'short' or 'name' is already specified
 *   in the set of command line options.
 *
 *)
PROCEDURE Present(h : Handle; short : CHAR; name : ARRAY OF CHAR) : BOOLEAN;
  VAR
    res : BOOLEAN;
    opt : Option;
BEGIN
  opt := h.options;
  res := FALSE;
  WHILE ~res & (opt # NIL) DO
    res  := ((short # 0X) & (short = opt.short)) OR (name = opt.name^);
    opt  := opt.next;
  END;
  RETURN res;
END Present;


PROCEDURE NewOption(h     : Handle;
                    value : INTEGER; (* Option value when matched. *)
                    flags : SET;
                    short : CHAR;
                    name  : ARRAY OF CHAR;
                    help  : ARRAY OF CHAR);
  VAR
    opt : Option;
BEGIN
  opt       := CreateOption(value, flags, short, name, help);
  opt.next  := h.options;
  h.options := opt;
END NewOption;


PROCEDURE AddOption*(h     : Handle;
                     value : INTEGER; (* Option value when matched. *)
                     flags : SET;
                     short : CHAR;
                     name  : ARRAY OF CHAR;
                     help  : ARRAY OF CHAR) : BOOLEAN;
  VAR
    opt : Option;
    ok  : BOOLEAN;
BEGIN
  ok := ValueAllowed(h, value) &
        (LEN(name) > 2) &         (* example: 'A' + 0X. *)
        (name[0] # '-') &
        (name[1] # '-') &
        ~Present(h, short, name);
  IF ok THEN
    NewOption(h, value, flags, short, name, help);
  END;
  RETURN ok;
END AddOption;


PROCEDURE Help*(h : Handle);
  VAR
    opt : Option;
BEGIN
  opt := h.options;
  WHILE opt # NIL DO
    Console.Ln;
    Console.Str("  --");
    Console.Str(opt.name^);
    IF opt.short # 0X THEN
      Console.Str(" [-");
      Console.Ch(opt.short);
      Console.Ch(']');
    END;
    IF ValueNeeded IN opt.flags THEN
      Console.Str("  <value>");
    END;
    Console.Ln;
    Console.Str("    ");
    Console.Str(opt.help^);
    Console.Ln;
    opt := opt.next;
  END;
  Console.Ln;
END Help;


PROCEDURE NextCh(h : Handle);
BEGIN
  IF h.index <= LEN(h.cmdline^) - 1 THEN
    INC(h.index);
  END;
  IF h.index < LEN(h.cmdline^) - 1 THEN
    h.ch := h.cmdline[h.index];
  ELSE
    h.ch := EOL;
  END;
END NextCh;


PROCEDURE NextToken(h : Handle; VAR tok : SHORTINT);
BEGIN
  IF (h # NIL) THEN
    WHILE h.ch <= ' ' DO    (* Consume spaces and control characters. *)
      NextCh(h);
    END;

    CASE h.ch OF
    | '-':
      NextCh(h);
      IF h.ch = '-' THEN
        tok := tkLongOpt;
        NextCh(h);
      ELSE
        tok := tkShortOpt;
      END;

    | EOL:
      tok := tkEol;

    ELSE
      (* Anything else is an indentifier, delimited by whitespace. *)
      tok := tkIdent;
      h.ident.beg := h.index;
      REPEAT
        NextCh(h);
      UNTIL (h.ch = '=') OR (h.ch = ' ') OR (h.ch = EOL);
      h.ident.end := h.index;
    END;
  ELSE
    tok := tkEol;
  END;
END NextToken;


PROCEDURE FindShortOption(h : Handle) : Option;
  VAR
    opt : Option;
    ch  : CHAR;
BEGIN
  opt := h.options;
  ch  := h.cmdline[h.ident.beg];
  WHILE opt # NIL DO
    IF ch = opt.short THEN
      RETURN opt;
    END;
    opt := opt.next;
  END;
  RETURN NIL;
END FindShortOption;


PROCEDURE Match(h : Handle; opt : Option) : BOOLEAN;
  VAR
    i   : INTEGER;
    j   : INTEGER;
    l   : INTEGER;
BEGIN
  i   := 0;
  j   := h.ident.beg;
  l   := h.ident.end - h.ident.beg;
  IF LEN(opt.name^) - 1 (* skip 0X. *) = l THEN
    LOOP
      IF opt.name[i] # h.cmdline[j] THEN
        EXIT;
      END;
      INC(i);
      INC(j);
      IF i >= l THEN
        RETURN TRUE;
      END;
    END;
  END;
  RETURN FALSE;
END Match;

PROCEDURE FindLongOption(h : Handle) : Option;
  VAR
    opt : Option;
BEGIN
  opt := h.options;
  WHILE opt # NIL DO
    IF Match(h, opt) THEN
      RETURN opt;
    END;
    opt := opt.next;
  END;
  RETURN NIL;
END FindLongOption;


PROCEDURE error(h : Handle; kind : SHORTINT; s : ARRAY OF CHAR);
  VAR
    i : INTEGER;
BEGIN
  ASSERT(kind IN { tkShortOpt, tkLongOpt });
  CASE kind OF
  | tkShortOpt:
    Console.Ch("-");
  | tkLongOpt:
    Console.Str("--");
  END;
  i := h.ident.beg;
  WHILE i < h.ident.end DO
    Console.Ch(h.cmdline[i]);
    INC(i);
  END;
  Console.Str(": ");
  Console.Str(s);
  Console.Ln;
END error;


PROCEDURE CopyArgument(    h        : Handle;
                       VAR argument : ArgumentDesc);
  VAR
    i   : INTEGER;
    j   : INTEGER;

BEGIN
  NEW(argument.argument, h.ident.end - h.ident.beg + 1);
  i := h.ident.beg;
  j := 0;
  WHILE i < h.ident.end DO
    argument.argument[j] := h.cmdline[i];
    INC(i);
    INC(j);
  END;
  argument.argument[j] := 0X;
END CopyArgument;


PROCEDURE ProcessOption(    kind     : SHORTINT;
                            h        : Handle;
                        VAR argument : ArgumentDesc;
                            opt      : Option) : Status;
  VAR
    tok : SHORTINT;

BEGIN
  ASSERT(kind IN { tkShortOpt, tkLongOpt });
  IF opt # NIL THEN
    argument.option := opt;
    argument.value  := opt.value;
    IF ValueNeeded IN opt.flags THEN
      NextToken(h, tok);
      IF tok = tkIdent THEN
        CopyArgument(h, argument);
      ELSE
        error(h, kind, "expected option value.");
        RETURN Error;
      END;
    END;
    RETURN Success;
  ELSE
    error(h, kind, "unknown option");
    RETURN NotFound;
  END;
END ProcessOption;


PROCEDURE Parse*(h : Handle; VAR argument : ArgumentDesc) : Status;
  VAR
    tok : SHORTINT;
BEGIN
  NextToken(h, tok);
  CASE tok OF
  | tkEol: (* Finished processing command line. *)
    RETURN Done;

  | tkShortOpt:
    NextToken(h, tok);
    CASE tok OF
    | tkError:
      RETURN Error;

    | tkIdent:
      IF (h.ident.end - h.ident.beg = 1)  THEN
        RETURN ProcessOption(tkShortOpt, h, argument, FindShortOption(h));
      ELSE
        error(h, tkShortOpt, "short option may be only one character.");
        RETURN Error;
      END;
    ELSE
      error(h, tkShortOpt, "malformed short option.");
      RETURN Error;
    END;

  | tkLongOpt:
    NextToken(h, tok);
    CASE tok OF
    | tkError:
      RETURN Error;

    | tkIdent:
      RETURN ProcessOption(tkLongOpt, h, argument, FindLongOption(h));
    ELSE
      error(h, tkLongOpt, "malformed long option.");
      RETURN Error;
    END;

  | tkIdent:
    argument.value := ValueArgument;
    argument.option := NIL;
    CopyArgument(h, argument);
    RETURN Success;
  END;
END Parse;


PROCEDURE AddHelp(h : Handle);
BEGIN
  ASSERT(h.options = NIL);     (* First option always. *)
  NewOption(h, ValueHelp, { }, 'h', "help",
            "Display this help text and exit.");
END AddHelp;


PROCEDURE Create*() : Handle;
  VAR
    h  : Handle;
    i  : INTEGER;
    ch : CHAR;
BEGIN
  NEW(h);
  NEW(h.cmdline, Kernel.GetCommandLineLength());
  Kernel.GetCommandLine(h.cmdline^);
  AddHelp(h);
  (* '--help', '-h' is implicitly declared. *)

  (* A typical command line will look like this:
   *
   * /tmp/skl/skl-o2/release/loader/oberon CTGetOpt.Test alpha beta=gamma
   *
   * The command line proper starts after the command name.
   * Elements of the command line are separated by ' '.
   *)
  i := 0;
  REPEAT
    ch := h.cmdline[i];
    INC(i);
  UNTIL (ch = ' ') OR (ch = 0X); (* First ' ' or end of command line. *)

  IF ch = ' ' THEN
    (* Look for second ' ' or end of command line. *)
    REPEAT
      ch := h.cmdline[i];
      INC(i);
    UNTIL (ch = ' ') OR (ch = 0X); (* Second ' ' or end of command line. *)
  END;

  DEC(i);
  h.ch    := h.cmdline[i];
  h.index := i;                 (* First character after command. *)
  RETURN h;
END Create;

END GetOpt.
