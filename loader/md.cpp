/* Copyright (c) 2000, 2020, 2021 Logic Magicians Software */
#include <assert.h>
#include "md.h"

namespace md
{
    /* Max and Min values for double IEEE 754 format.
     *
     * Unlike integer types, the max positive and min negative values
     * are identical,
     *
     */
    const unsigned MinRealPat      = 0xff7fffff;
    const unsigned MaxRealPat      = 0x7f7fffff;
    const unsigned MinLRealPatL    = 0xffffffff;
    const unsigned MinLRealPatH    = 0xffefffff;
    const unsigned MaxLRealPatL    = 0xffffffff;
    const unsigned MaxLRealPatH    = 0x7fefffff;

    double
    MinLReal(void)
    {
        static bool   inited = false;
        static double result;

        if (!inited) {
            inited = true;
            md::recompose_double(MinLRealPatH, MinLRealPatH, result);
        }
        return result;
    }


    double
    MaxLReal(void)
    {
        static bool   inited = false;
        static double result;

        if (!inited) {
            inited = true;
            md::recompose_double(MaxLRealPatH, MaxLRealPatH, result);
        }
        return result;
    }
}
