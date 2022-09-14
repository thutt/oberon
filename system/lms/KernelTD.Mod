(* Copyright (c) 1997-2000, 2021-2022 Logic Magicians Software *)
MODULE KernelTD;
  IMPORT Kernel;

  (* This procedure is used to find out what type descriptors are
   * associated with which field of the Module data structure.
   *
   * After compiling, the file is disassembled and the type
   * descriptor symbol names are determined and added into
   * the 'loader' software.
   *)
  PROCEDURE TDAllocation;
    VAR m : Kernel.Module; c : Kernel.Cmd; e : Kernel.Export;
  BEGIN
    NEW(m);
    NEW(m.tdescs, 1);
    NEW(m.exports, 2);
    NEW(m.privates, 3);
    NEW(m.commands, 4);
    NEW(m.pointers, 5);
    NEW(m.imports, 6);
    NEW(m.jumps, 7);
    NEW(m.data, 8);
    NEW(m.tddata, 9);
    NEW(m.code, 10);
    NEW(m.refs, 11);
    NEW(m.name, 12);
    
    NEW(c.name, 13);
    NEW(e.name, 14);
  END TDAllocation;
END KernelTD.
