/* Copyright (c) 2021 Logic Magicians Software */
#include "md.h"
#include "skl.h"


namespace skl {
    const md::uint32 ZF = 0;
    const md::uint32 SF = 1;
    const md::uint32 CF = 2;
    const md::uint32 OF = 3;


    typedef bool (*relation_t)(md::uint32 flags);
    extern relation_t relation[10]; /* Must have same elements as Jump
                                     * and conditional set
                                     * instructions. */

    static inline md::uint32
    create_flags(bool zf, bool sf, bool cf, bool of)
    {
        return static_cast<md::uint32>((zf << ZF) |
                                       (sf << SF) |
                                       (cf << CF) |
                                       (of << OF));
    }

    static inline bool
    flag(md::uint32 flags, md::uint32 bit)
    {
        return !!(flags & left_shift(1, bit));
    }
}
