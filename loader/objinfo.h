/* Copyright (c) 2000, 2021 Logic Magicians Software */
#if !defined(_OBJINFO_H)
#define _OBJINFO_H

namespace objinfo
{
    enum export_t /* export block / type descriptor block constants */
    {
        Econst = 1,
        Etype = 2,
        Evar = 3,
        Exproc = 4,
        Eiproc = 4,
        Ecproc = 5,
        Estruc = 6,
        Erectd = 8,
        Edarrtd = 9,
        Earrtd = 10
    };

    enum uses_t
    {
        Uconst = 1,
        Utype = 2,
        Uvar = 3,
        Uxproc = 4,
        Uiproc = 4,
        Ucproc = 5,
        Upbstruc = 6,
        Upvstruc = 7,
        Urectd = 8,
        Udarrtd = 9,
        Uarrtd = 10
    };


    enum td_t
    {
        Trec = 1,
        Tdarray = 2,
        Tarray = 3
    };


    const int FixAbs = 0; /* must match LMCGL */
    const int FixRel = 1;
    const int FixBlk = 2; /* record type descriptor `record block size' */

    /* must match LMCGL */
    const int segUndef = -1;
    const int segBegin = 0;
    const int segCode = 0;
    const int segConst = 1;
    const int segCase = 2;
    const int segData = 3;
    const int segExport = 4;
    const int segCommand = 5;
    const int segTypeDesc = 6;
    const int segTDesc = 7;
    const int segEnd = 8;

    extern const char * const seg_names[segEnd - segBegin];
}
#endif
