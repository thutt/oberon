(* Copyright (c) 2021 Logic Magicians Software
 *
 * This module allocates some data on the heap, and then invokes the
 * garbage collector.  The heap is dumped to show that the data is
 * garbage collected properly.
 *)
MODULE CTTypeDesc;
  IMPORT Kernel, HostOS, Console;

  TYPE
    Handle* = POINTER TO HandleDesc;
    HandleDesc = RECORD
      next, prev : Handle;
      name : ARRAY 32 OF CHAR;
    END;

  VAR
    FileList : Handle; (* (currently) open files *)

  PROCEDURE NewHandle(VAR h : Handle);
    VAR
      c : Handle;
      tag : LONGINT;
  BEGIN
    NEW(c);
    c.next := NIL;
    c.prev := NIL;
    c.name[0] := 0X;
    h := c;
  END NewHandle;

  PROCEDURE Allocate;
    VAR h : Handle;
  BEGIN
    NewHandle(h);
    h.next := FileList;
    h.prev := FileList;
    COPY("gungla", h.name);
  END Allocate;

  PROCEDURE Test*;
  BEGIN
    Allocate;
    Kernel.DumpHeap;
    Kernel.GC;                  (* No open stack frames with pointers
                                 * allowed in GC! *)
    Kernel.DumpHeap;
    FileList := NIL;
    Kernel.GC;
    Kernel.DumpHeap;
  END Test;

BEGIN
  (* Dummy list header (for ease of list handling). *)
  NewHandle(FileList);
  FileList.next := FileList;
  FileList.prev := FileList;
END CTTypeDesc.
