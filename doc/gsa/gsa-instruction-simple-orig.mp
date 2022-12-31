% Copyright (c) 2001-2022 Logic Magicians Software
prologues:=2;
input boxes;
beginfig(1);        % simplified view of how instructions are linked
  numeric ysep;
  numeric xsep;

  boxit.inst[0](btex$\strut {inst}_0$ etex);
  boxit.inst[1](btex$\strut {inst}_1$ etex);
  boxit.inst[2](btex$\strut {inst}_2$ etex);
  boxit.inst[3](btex$\strut {inst}_3$ etex);

  circleit.res[0](btex$\strut {res}_0$ etex);
  circleit.res[1](btex$\strut {res}_0$ etex);
  circleit.res[2](btex$\strut {res}_0$ etex);
  circleit.res[3](btex$\strut {res}_0$ etex);

  circleit.op[0][0](btex$\strut {op}_0$ etex);
  circleit.op[0][1](btex$\strut {op}_1$ etex);
  circleit.op[1][0](btex$\strut {op}_0$ etex);
  circleit.op[1][1](btex$\strut {op}_1$ etex);
  circleit.op[2][0](btex$\strut {op}_0$ etex);
  circleit.op[2][1](btex$\strut {op}_1$ etex);
  circleit.op[3][0](btex$\strut {op}_0$ etex);
  circleit.op[3][1](btex$\strut {op}_1$ etex);

  for i = 0 upto 3:
    res[i].dx = res[i].dy + 10;
    inst[i].c - res[i].c = op[i][0].c - inst[i].c = op[i][1].c - op[i][0].c = (xsep, 0);
  endfor;
  
  
  inst[0].c - inst[1].c = inst[1].c - inst[2].c = inst[2].c - inst[3].c = (0, ysep);
  
  ypart(inst[0].n - inst[3].s) = 3in;
  xpart(op[0][1].e - res[0].w) = 4in;

  drawboxed(
    res[0], inst[0], op[0][0], op[0][1],
    res[1], inst[1], op[1][0], op[1][1],
    res[2], inst[2], op[2][0], op[2][1],
    res[3], inst[3], op[3][0], op[3][1]);

  for i = 0 upto 3:
    drawarrow res[i].n{up}..tension 5..inst[i].nw;
    drawarrow inst[i].sw{down}..tension 5..res[i].s;
    drawarrow inst[i].ne{up}..tension 5..op[i][0].n;
    drawarrow op[i][0].n{up}..tension 5..op[i][1].n;
    drawarrow op[i][1].s{down}..tension 5..op[i][0].s;
    drawarrow op[i][0].s{down}..tension 5..inst[i].se;
  endfor;

  for i = 1 upto 3:
    drawarrow inst[i - 1].s{right}..tension 5..inst[i].n;
    drawarrow inst[i].n{left}..tension 5..inst[i-1].s;
  endfor;
  
  drawarrow res[0].w{left}..tension 3..
            3/5[res[1].w,res[2].w]{right}..tension 10..
            7/8[op[1][0].s,op[2][0].n]{down}..
            op[2][0].n;

  drawarrow res[1].s..
            2/5[res[1].c,res[2].c]{right}..tension 10..
            7/8[op[1][1].s,op[2][1].n]{down}..
            op[2][1].n;


  drawarrow res[0].w{left}..tension 3..
            3/5[res[2].w,res[3].w]{right}..tension 10..
            7/8[op[2][0].s,op[3][0].n]{down}..
            op[3][0].n;

  drawarrow res[2].s..
            2/5[res[2].c,res[3].c]{right}..tension 10..
            7/8[op[2][1].s,op[3][1].n]{down}..
            op[3][1].n;
endfig;
end;
