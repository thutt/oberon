/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_FLAGS_H)
#define _SKL_FLAGS_H

#include "md.h"
#include "skl.h"
#include "skl_flags_alu.h"

namespace skl {
    const int ZF = 0;
    const int SF = 1;
    const int CF = 2;
    const int OF = 3;


    static inline md::uint32
    create_flags(bool zf, bool sf, bool cf, bool of)
    {
        return static_cast<md::uint32>((zf << ZF) |
                                       (sf << SF) |
                                       (cf << CF) |
                                       (of << OF));
    }


    static inline bool
    flag(md::uint32 flags, int bit)
    {
        return !!(flags & left_shift(1, bit));
    }


    static inline bool
    relation_eq(md::uint32 flags)
    {
        return flag(flags, ZF);
    }


    static inline bool
    relation_ne(md::uint32 flags)
    {
        return !flag(flags, ZF);
    }


    static inline bool
    relation_ltu(md::uint32 flags)
    {
        return flag(flags, CF);
    }


    static inline bool
    relation_geu(md::uint32 flags)
    {
        return !flag(flags, CF);
    }


    static inline bool
    relation_leu(md::uint32 flags)
    {
        return flag(flags, CF) || flag(flags, ZF);
    }

    static inline bool
    relation_gtu(md::uint32 flags)
    {
        return !flag(flags, CF) && !flag(flags, ZF);
    }


    static inline bool
    relation_lt(md::uint32 flags)
    {
        return flag(flags, SF) != flag(flags, OF);
    }


    static inline bool
    relation_ge(md::uint32 flags)
    {
        return flag(flags, SF) == flag(flags, OF);
    }


    static inline bool
    relation_le(md::uint32 flags)
    {
        return flag(flags, ZF) || flag(flags, SF) != flag(flags, OF);
    }


    static inline bool
    relation_gt(md::uint32 flags)
    {
        return !flag(flags, ZF) && (flag(flags, SF) == flag(flags, OF));
    }
}
#endif
