/* Copyright (c) 2022 Logic Magicians Software
 *
 *  This file is an x86-specific implementation of ALU flag synthesis.
 */
#if !defined(_SKL_FLAGS_ALU_H)
#define _SKL_FLAGS_ALU_H

#include "md.h"

namespace skl {
    static inline md::uint32
    synthesize_flags_int32(md::uint32 l, md::uint32 r)
    {
        bool ZF;          /* Zero flag. */
        bool SF;          /* Sign flag. */
        bool CF;          /* Carry flag. */
        bool OF;          /* Overflow flag. */

        __asm__ __volatile__("cmp %[right], %[left]\n\t"
                             "setz %[ZF]\n\t"
                             "sets %[SF]\n\t"
                             "setc %[CF]\n\t"
                             "seto %[OF]\n\t"

                             "shl    $3, %[OF]\n\t" /* OF = OF << 3 */
                             "shl    $2, %[CF]\n\t" /* CF = CF << 3 */
                             "shl    $1, %[SF]\n\t" /* SF = SF << 3 */

                             "orb    %[OF], %[ZF]\n\t"
                             "orb    %[CF], %[ZF]\n\t"
                             "orb    %[SF], %[ZF]\n\t"
                             : /* output */
                               [ZF]  "=r" (ZF),
                               [SF]  "=r" (SF),
                               [CF]  "=r" (CF),
                               [OF]  "=r" (OF)
                             : /* input */
                               [right] "rm" (r),
                               [left] "r" (l)
                             : /* clobbers */ "cc");

        return static_cast<md::uint32>(ZF);
    }


    static inline unsigned
    synthesize_overflow_double(double l, double r)
    {
        int t0 = (r >= 0) && (l >= md::MinLReal() + r);
        int t1 = (r < 0)  && (l <= md::MaxLReal() + r);
        return !t0 && !t1;
    }


    static inline md::uint32
    synthesize_flags_double(double l, double r)
    {
        double     delta = (l - r);
        md::uint32 ZF    = delta == 0;                    // Zero flag.
        md::uint32 SF    = delta < 0;                     // Sign flag.
        md::uint32 CF    = l < r;                         // Carry flag.
        md::uint32 OF = synthesize_overflow_double(l, r); // Overflow flag.

        return ((ZF << 0) |
                (SF << 1) |
                (CF << 2) |
                (OF << 3));
    }
}
#endif
