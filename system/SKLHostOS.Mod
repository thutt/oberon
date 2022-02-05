(* Copyright (c) 2021-2022 Logic Magicians Software *)
MODULE HostOS;
  IMPORT SYSTEM, Kernel;

  CONST
    SVCGetLocalTime = 0;

  TYPE
    SVCTime = RECORD (Kernel.VMServiceDesc)
      op   : LONGINT;
      time : LONGINT;
    END;

  PROCEDURE GetLocalTime() : LONGINT;
    VAR
      lt : SVCTime;
  BEGIN
    lt.op := SVCGetLocalTime;
    Kernel.VMService(Kernel.VMSVCTime, lt);
    RETURN lt.time;
  END GetLocalTime;

  (* SplitSystemTime: splits the given system time into basic components *)
  PROCEDURE SplitSystemTime*(time : LONGINT; VAR year, month, day, hour, minute, second : LONGINT);
  BEGIN
    ASSERT(FALSE); (* FIXME: 2000.07.12: unimplemented *)
  END SplitSystemTime;

  PROCEDURE SetClock(time, date : LONGINT);
  BEGIN (* FIXME: incomplete implementation *)
  END SetClock;

  PROCEDURE GetSystemTime*(VAR t : LONGINT);
  BEGIN
    t := GetLocalTime();
  END GetSystemTime;

  PROCEDURE SystemToOberonTime(systemtime : LONGINT; VAR time, date : LONGINT);
  BEGIN
    (* FIXME: incomplete implementation *)
    time := 0;
    date := 0;
  END SystemToOberonTime;

  (* tenet: all times in this Oberon implemenation will be in UTC,
   * but converted to local time based on a timezone setting
   *)
  PROCEDURE GetClock(VAR time, date : LONGINT);
    VAR systime : LONGINT;
  BEGIN
    systime := GetLocalTime();
    SystemToOberonTime(systime, time, date);
  END GetClock;

  PROCEDURE Init;
    VAR proc : LONGINT;
  BEGIN
    Kernel.SetClockProc := SetClock;
    Kernel.GetClockProc := GetClock;
  END Init;

BEGIN
  Init;
END HostOS.
