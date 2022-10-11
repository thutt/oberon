% Copyright (c) 2001-2022 Logic Magicians Software
  % result x separator
  rxsep = 3.8in/(n_res+1);

  % operand x separator
  oxsep = 3.8in/(n_op+1);

  % bound y dimension of picture
  ypart (res[0].n - op[0].s) = 1.4in;

  % make ellipses out of results
  for i = 0 upto n_res:
    res[i].dx = res[i].dy + 5;
  endfor;

  % make ellipses out of operands
  for i = 0 upto n_op:
    op[i].dx = op[i].dy + 5;
  endfor;
  
  res[0].w - (20, ysep) = inst.w;
  op[0].w + (-20, ysep) = inst.w;

  for i = 1 upto n_res:
    res[i].c - (rxsep, 0) = res[i - 1].c;
  endfor;

  for i = 1 upto n_op:
    op[i].c - (oxsep, 0) = op[i - 1].c;
  endfor;

  for i = 0 upto n_res:
    drawboxed(res[i]);
  endfor;

  for i = 0 upto n_op:
    drawboxed(op[i]);
  endfor;

  drawboxed(inst);

  label.lft("results", cuta(inst, res[0])(inst.nw{up}..tension 5..res[0].w));
  label.lft("operands", cuta(inst, op[0])(inst.sw{down}..tension 5..op[0].w));
  label.top("fres", cuta(res[n_res], res[0])(res[n_res].n{up}..tension 10..res[0].n));
  label.bot("bres", cuta(res[0], res[n_res])(res[0].s{down}..tension 10..res[n_res].s));

  if n_op = 0: 
    label.top("fop", cuta(op[n_op], op[0])(op[n_op].n{up}..op[0].w));
    label.bot("bop", cuta(op[0], op[n_op])(op[0].s{down}..op[n_op].e));
  else:
    label.top("fop", cuta(op[n_op], op[0])(op[n_op].n{up}..tension 10..op[0].n));
    label.bot("bop", cuta(op[0], op[n_op])(op[0].s{down}..tension 10..op[n_op].s));
  fi;

  for i = 0 upto n_res - 1:
    drawarrow res[i].n{up}..tension 5..res[i + 1].w;
    drawarrow res[i + 1].s{down}..tension 5..res[i].e;
  endfor;

  for i = 0 upto n_op - 1:
    drawarrow op[i].n{up}..tension 5..op[i + 1].w;
    drawarrow op[i + 1].s{down}..tension 5..op[i].e;
  endfor;

endfig;
end;
