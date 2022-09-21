(* Copyright (c) 2022 Logic Magicians Software
 *
 * To manually test:
 *
 * skl-oberon -- CTGetOpt.Test --gungla
 *   (unknown option)
 *
 * skl-oberon -- CTGetOpt.Test -gungla
 *   (short options must be only 1 character)
 *
 * skl-oberon -- CTGetOpt.Test alpha -v beta gamma
 *   (Argument 'alpha', '--verbose' set, argument 'beta', 'gamma')
 *
 * skl-oberon -- CTGetOpt.Test --symbols alpha -v beta gamma
 *   ('--symbols' 'alpha', '--verbose' set, argument 'beta', 'gamma')
 *
 * skl-oberon -- CTGetOpt.Test --symbols /tmp alpha -v beta gamma
 *   ('--symbols' '/tmp', argument 'alpha', '--verbose' set,
 *    argument 'beta', 'gamma')
 *)
MODULE CTGetOpt;
IMPORT GetOpt, Console;

PROCEDURE AddOption(expect : BOOLEAN;
                    h      : GetOpt.Handle;
                    value  : INTEGER; (* Option value when matched *)
                    flags  : SET;
                    short  : CHAR;
                    name   : ARRAY OF CHAR;
                    help   : ARRAY OF CHAR);
  VAR
    r : BOOLEAN;
BEGIN
  r := GetOpt.AddOption(h, value, flags, short, name, help);
  ASSERT(r = expect);
END AddOption;


PROCEDURE Test*;
VAR
  h   : GetOpt.Handle;
  arg : GetOpt.ArgumentDesc;
  r   : GetOpt.Status;
BEGIN
  h := GetOpt.Create();
  AddOption(TRUE, h, 64, { GetOpt.ValueNeeded },
            0X, "symbols",
            "Add a directory to search for Sym files.");
  AddOption(TRUE, h, 65, { GetOpt.ValueNeeded },
            0X, "no-nil-check",
            "When specified, NIL-pointer deref checks are not generated.");
  AddOption(TRUE, h, 66, {  },
            'v', "verbose",
            "Enable verbosity.");
  AddOption(FALSE, h, 66, {  },
            'v', "verbose",
            "Enable verbosity.");
  REPEAT
    r := GetOpt.Parse(h, arg);
    IF r = GetOpt.Success THEN
      CASE arg.value OF
      | GetOpt.ValueHelp:
        GetOpt.Help(h);
        RETURN;

      | GetOpt.ValueArgument:
        Console.Str("ARGUMENT: '");
        Console.Str(arg.argument^);
        Console.Str("'");
        Console.Ln;

      | 64:
        Console.Str("--symbols: '");
        Console.Str(arg.argument^);
        Console.Str("'");
        Console.Ln;

      | 65:
        Console.Str("--no-nil-check");
        Console.Ln;

      | 66:
        Console.Str("Verbosity enabled");
        Console.Ln;
      END;
    END;
  UNTIL r = GetOpt.Done;
END Test;

END CTGetOpt.
