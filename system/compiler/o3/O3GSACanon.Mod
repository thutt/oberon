(* O3GSACanon: Canonicalize instructions in a region to have a
 *             specific operand ordering.
 *)
MODULE O3GSACanon;
  IMPORT
    Config:=O3Config, 
    GSAOpcode := O3GSAOpcode,
    GSAData := O3GSAData;

  (* inv: (Ai: i IN r.instructions: clobbered(i.info)) *)
  PROCEDURE Perform*(r : GSAData.GlobalRegion);
  BEGIN
(*    Config.LogWStr('Canoncalization of Operands'); Config.LogWLn;
*)
  END Perform;

  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN
  END NILGlobalPointers;
  
  PROCEDURE ModuleBegin(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleBegin;

  PROCEDURE ModuleEnd(FileInfo : Config.SourceInfo) : BOOLEAN;
  BEGIN NILGlobalPointers; RETURN TRUE;
  END ModuleEnd;
  
  PROCEDURE Init;
  BEGIN Config.ControlModule(ModuleBegin, ModuleEnd);
  END Init;
  
BEGIN Init;
END O3GSACanon.
