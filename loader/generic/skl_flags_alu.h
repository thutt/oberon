/* Copyright (c) 2022 Logic Magicians Software
 *
 *  This file is a generic implementation of ALU flag synthesis.  It
 *  will work for any GCC target architecture that is not superceded
 *  by a specific architecture version.
 */
#if !defined(_SKL_FLAGS_ALU_H)
#define _SKL_FLAGS_ALU_H

#include "md.h"

namespace skl {
    static inline unsigned
    synthesize_OF(md::int32 l, md::int32 r)
    {
        unsigned sign_mask = left_shift(1, 31);
        int      res       = l - r; // Result sign.
        unsigned not_equal = static_cast<unsigned>(l ^ r);
        unsigned sign_diff = static_cast<unsigned>(l ^ res);

        return !!((not_equal & sign_diff) & sign_mask);
    }


    static inline unsigned
    synthesize_ZF(md::uint32 l, md::uint32 r)
    {
        return (l - r) == 0;
    }


    static inline unsigned
    synthesize_SF(md::int32 l, md::int32 r)
    {
        return (l - r) < 0;
    }


    static inline unsigned
    synthesize_CF(md::uint32 l, md::uint32 r)
    {
        return l < r;
    }


    static inline md::uint32
    synthesize_flags_int32(md::uint32 l, md::uint32 r)
    {
        md::int32  ll = static_cast<md::int32>(l);
        md::int32  lr = static_cast<md::int32>(r);
        md::uint32 ZF = synthesize_ZF(l, r)   << 0; // Zero flag.
        md::uint32 SF = synthesize_SF(ll, lr) << 1; // Sign flag.
        md::uint32 CF = synthesize_CF(l, r)   << 2; // Carry flag.
        md::uint32 OF = synthesize_OF(ll, lr) << 3; // Overflow flag.
        return OF | CF | SF | ZF;
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
