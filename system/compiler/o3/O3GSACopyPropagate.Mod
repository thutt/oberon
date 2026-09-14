(* Copy Propagation: Replace all `copy' instructions with a `Result'
 * of the originally computed value. 
 *)
MODULE O3GSACopyPropagate;
  IMPORT 
    Config:=O3Config, 
    GSAData := O3GSAData,
    GSAOpcode := O3GSAOpcode;


  PROCEDURE UseReplace(x, y: GSAData.Usable);
    VAR
      u, n : GSAData.Operand;
  BEGIN
    u := x.uses.fuses;
    WHILE u # x.uses DO
      n := u.fuses;
      IF (u.owner.class # GSAOpcode.Mmemory) THEN
        GSAData.UseDelete(u);
        GSAData.UseInsert(u, y);
      END;
      u := n;
    END;
  END UseReplace;


  PROCEDURE Perform*(r : GSAData.GlobalRegion);
    PROCEDURE traverse(r : GSAData.Region);
      VAR i : GSAData.Instruction; rgn : GSAData.Region;
    BEGIN
      i := r.instructions.finst;
      WHILE (i # r.instructions) DO
        IF (i.class = GSAOpcode.Gmisc) & (i.subcl = GSAOpcode.Gcopy) THEN
          UseReplace(i, i.operands.fop.def);
        END;
        i := i.finst;
      END;
      
      rgn := r.regions.freg;
      WHILE rgn # r.regions DO traverse(rgn); rgn := rgn.freg; END;
    END traverse;
  BEGIN traverse(r);
  END Perform;

  (** Module initialization *)
  PROCEDURE NILGlobalPointers;
  BEGIN END NILGlobalPointers;
  
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
END O3GSACopyPropagate.
