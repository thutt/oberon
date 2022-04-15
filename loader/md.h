/* Copyright (c) 2020, 2021, 2022 Logic Magicians Software */
#if !defined(_MD_H)
#define _MD_H
#include <assert.h>
#include <limits.h>

#include "config.h"
#include "dialog.h"


namespace md {                  /* Machine description. */
    typedef unsigned char   uint8;
    typedef unsigned short  uint16;
    typedef unsigned int    uint32;
    typedef signed char     int8;
    typedef signed short    int16;
    typedef signed int      int32;

    typedef unsigned long uint64; /* Must match host machine pointer size. */

    const md::int32 MinLInt  = INT_MIN;
    const md::int32 MaxLInt  = INT_MAX;
    const md::int32 MaxSet   = 31;

    double MinLReal(void);
    double MaxLReal(void);

    typedef md::uint32 OFLAGS;  /* (Oberon Flags)
                                 *
                                 * A 32-bit unsigned value that holds
                                 * Oberon condition codes.
                                 */
    typedef md::uint32 OINST;   /* (Oberon Instruction)
                                 *
                                 * A 32-bit unsigned value that is an
                                 * SKL CPU instruction.
                                 */
    typedef md::uint32 OADDR;   /* (Oberon Address)
                                 *
                                 * An address in the Oberon heap,
                                 * usable by the Oberon CPU.
                                 */
    typedef md::uint8 *HADDR;   /* (Host Address)
                                 *
                                 * An address in the Oberon heap,
                                 * usable by the program running on
                                 * the host.*/


    static inline void
    decompose_double(double d, uint32 &lo, uint32 &hi)
    {
        /* Breaks a double value into two 32-bit unsigned integers. */
        uint32 *p = reinterpret_cast<uint32 *>(&d);

        COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(uint32));
        lo = p[0];
        hi = p[1];
    }

    static inline void
    recompose_double(uint32 lo, uint32 hi, double &d)
    {
        union {
            /* Combines two 32-bit unsigned integers into a double. */
            md::uint32 i[2];
            double     d;
        } v;
        COMPILE_TIME_ASSERT(skl_endian_little);
        COMPILE_TIME_ASSERT(sizeof(double) == 2 * sizeof(uint32));
        v.i[0] = lo;
        v.i[1] = hi;
        d      = v.d;
    }
}
#endif
