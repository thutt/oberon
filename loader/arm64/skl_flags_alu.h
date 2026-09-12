/* Copyright (c) 2022-2026 Logic Magicians Software
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
        unsigned ZF, SF, CF, OF;

        __asm__ __volatile__("cmp %w[left], %w[right]\n\t"
                             "cset %w[ZF], eq\n\t"    /* Zero flag.     */
                             "cset %w[SF], mi\n\t"    /* Sign flag.     */
                             "cset %w[CF], lo\n\t"    /* Carry flag.    */
                             "cset %w[OF], vs\n\t"    /* Overflow flag. */
                             : [ZF] "=r" (ZF),
                               [SF] "=r" (SF),
                               [CF] "=r" (CF),
                               [OF] "=r" (OF)
                             : [left] "r" (l),
                               [right] "r" (r)
                             : "cc");

        return (ZF << 0) | (SF << 1) | (CF << 2) | (OF << 3);
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
        md::uint32 ZF    = delta == 0;                       // Zero flag.
        md::uint32 SF    = delta < 0;                        // Sign flag.
        md::uint32 CF    = l < r;                            // Carry flag.
        md::uint32 OF    = synthesize_overflow_double(l, r); // Overflow flag.

        return ((ZF << 0) |
                (SF << 1) |
                (CF << 2) |
                (OF << 3));
    }
}
#endif
