% Copyright (c) 2001-2022 Logic Magicians Software
% GSA Type hierarchy
% 2001.07.20: A defect in the NEC SuperScript 1800N postscript printer or metapost
%             causes this diagram to hang the printer.
prologues:=2;
input boxes;

beginfig(1);
  boxit.info(btex Info etex);
  boxit.location(btex Location etex);
  boxit.symlocation(btex SymLocation etex);
  boxit.operand(btex Operand etex);
  boxit.node(btex Node etex);
  boxit.usable(btex Usable etex);
  boxit.addressable(btex Addressable etex);
  boxit.type(btex Type etex);
  boxit.symbol(btex Symbol etex);
  boxit.temporary(btex Temporary etex);
  boxit.result(btex Result etex);
  boxit.instruction(btex Instruction etex);
  boxit.gate(btex Gate etex);
  boxit.region(btex Region etex);
  boxit.guard(btex Guard etex);
  boxit.merge(btex Merge etex);
  boxit.globalregion(btex GlobalRegion etex);
  boxit.case(btex Case etex);
  boxit.condmerge(btex CondMerge etex);
  boxit.const(btex Const etex);
  boxit.constset(btex ConstSet etex);
  boxit.constintrange(btex ConstIntRange etex);
  boxit.constint(btex ConstInt etex);
  boxit.constbool(btex ConstBool etex);
  boxit.constreal(btex ConstReal etex);
  boxit.constlreal(btex ConstLReal etex);
  boxit.conststring(btex ConstString etex);

  height  = 8in;
  width = 5.0in;
  
  % level 0: Info
  
  % level 1: Node, Location
  location.c - node.c = (level1sep, 0);
  ypart node.c - ypart info.c = levelsep;
  xpart node.c + level1sep / 2 = xpart info.c;
  xpart location.e - xpart node.w = width / 2;

  % level 2: Usable, Operand, SymLocation
  symlocation.c = location.c + (0, levelsep);

  ypart operand.c = ypart usable.c = ypart node.c + levelsep;
  xpart operand.c = xpart node.c - (level2sep / 3) / 2;
  xpart usable.c  = xpart node.c + (level2sep / 3) / 2;
  xpart usable.e - xpart operand.w = width / 3;

  % level 3: Addressable, Result
  xpart result.c - xpart addressable.c = level3sep;
  ypart result.c = ypart usable.c + levelsep;
  ypart addressable.c = ypart usable.c + levelsep / 2;
  xpart addressable.c  = part usable.c - level3sep / 2;
  xpart result.e - xpart addressable.w = width / 2;

  % level 4: Type, Symbol, Const, Temporary, Instruction,
  ypart type.c = ypart addressable.c + levelsep;
  ypart const.c = ypart addressable.c + levelsep;
  ypart symbol.c = ypart addressable.c + levelsep / 2;
  ypart temporary.c = ypart addressable.c + levelsep;
  instruction.c  = (xpart result.c, ypart result.c + levelsep);

  xpart symbol.c = xpart addressable.c - level4sep;
  xpart const.c = xpart symbol.c + level4sep;
  xpart type.c = xpart const.c + level4sep;
  xpart temporary.c = xpart symbol.c - level4sep / 3;
  xpart type.e - xpart symbol.w = width / 3;

  % level 5: Gate, Region
  ypart gate.c = ypart instruction.c + levelsep;
  ypart region.c = ypart instruction.c + levelsep;
  xpart gate.c - xpart region.c = level5sep;
  xpart region.c + level5sep / 2 = xpart instruction.c;
  xpart gate.e - xpart region.w = width / 4;

  % level 6: Guard, Merge, GlobalRegion, Case
  ypart guard.c = ypart region.c + levelsep;
  ypart globalregion.c = ypart case.c = ypart region.c + levelsep;
  case.c - globalregion.c = globalregion.c - merge.c = (level6sep, 0);
  xpart merge.c - xpart guard.c = .8level6sep;
  xpart merge.c = xpart region.c;
  
  xpart case.e - xpart guard.w = width / 2;
  
  % level 7: CondMerge
  condmerge.c = merge.c + (0, levelsep / 2);
  
  % level 8: ConstSet, ConstIntRange, ConstInt, ConstBool, ConstReal, ConstLReal, ConstString
  level8sep = 1.5(xpart const.e - xpart const.w);
  constset.c = const.c + (-level8sep, levelsep / 2);
  constintrange.e = constset.e + (0, levelsep / 2);
  constint.e = constintrange.e + (0, levelsep / 2);
  constbool.c = const.c + (0, 2levelsep);
  constlreal.w = conststring.w + (0, levelsep / 2);
  constreal.w = constlreal.w + (0, levelsep / 2);
  conststring.c = const.c + (level8sep, levelsep / 2);

  levelsep = height / 9;
  
  drawboxed(info);
  drawboxed(node, location);
  drawboxed(usable, operand, symlocation);
  drawboxed(result, addressable);
  drawboxed(type, symbol, const, temporary, instruction);
  drawboxed(gate, region);
  drawboxed(guard, merge, globalregion, case);
  drawboxed(condmerge);
  drawboxed(constset, constintrange, constint, constbool, constreal, constlreal, conststring);

  % arrows
  drawarrow info.n..node.s;
  drawarrow info.n..location.s;
  drawarrow location.n..symlocation.s;
  drawarrow node.n..operand.s;
  drawarrow node.n..usable.s;
  drawarrow usable.n..addressable.s;
  drawarrow usable.n..result.s;
  drawarrow addressable.n..type.s;
  drawarrow addressable.n..symbol.s;
  drawarrow addressable.n..const.s;
  drawarrow symbol.n..temporary.s;
  drawarrow result.n..instruction.s;
  drawarrow instruction.n..gate.s;
  drawarrow instruction.n..region.s;
  drawarrow region.n..guard.s;
  drawarrow region.n..merge.s;
  drawarrow region.n..globalregion.s;
  drawarrow region.n..case.s;
  drawarrow merge.n..condmerge.s;
  drawarrow const.n..constset.e;
  drawarrow const.n..constintrange.e;
  drawarrow const.n..constint.e;
  drawarrow const.n..constbool.s;
  drawarrow const.n..constreal.w;
  drawarrow const.n..constlreal.w;
  drawarrow const.n..conststring.w;
endfig;
end;
