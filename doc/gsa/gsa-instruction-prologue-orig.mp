% Copyright (c) 2001-2022 Logic Magicians Software
prologues:=0;

vardef cuta(suffix a, b)(expr p) =
drawarrow p cutbefore bpath.a cutafter bpath.b;
point .5*length p of p
enddef;

input boxes;
beginfig(1);        % $varpar
  numeric ysep;
  numeric rxsep;
  numeric oxsep;
