/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>

#include "config.h"
#include "heap.h"
#include "o3.h"
#include "md.h"
#include "skl.h"
#include "skl_flags.h"

namespace skl {
    typedef bool (*relation_t)(md::uint32 flags);

    static bool rel_eq(md::uint32 flags);
    static bool rel_ne(md::uint32 flags);
    static bool rel_ltu(md::uint32 flags);
    static bool rel_geu(md::uint32 flags);
    static bool rel_leu(md::uint32 flags);
    static bool rel_gtu(md::uint32 flags);
    static bool rel_lt(md::uint32 flags);
    static bool rel_ge(md::uint32 flags);
    static bool rel_le(md::uint32 flags);
    static bool rel_gt(md::uint32 flags);

    relation_t relation[10] = {
        rel_eq, /* OPC_JEQ */
        rel_ne, /* OPC_JNE */
        rel_lt, /* OPC_JLT */
        rel_ge, /* OPC_JGE */
        rel_le, /* OPC_JLE */
        rel_gt, /* OPC_JGT */
        rel_ltu, /* OPC_JLTU */
        rel_geu, /* OPC_JGEU */
        rel_leu, /* OPC_JLEU */
        rel_gtu, /* OPC_JGTU */
    };


    static bool
    rel_eq(md::uint32 flags)
    {
        return relation_eq(flags);
    }


    static bool
    rel_ne(md::uint32 flags)
    {
        return relation_ne(flags);
    }


    static bool
    rel_ltu(md::uint32 flags)
    {
        return relation_ltu(flags);
    }


    static bool
    rel_geu(md::uint32 flags)
    {
        return relation_geu(flags);
    }


    static bool
    rel_leu(md::uint32 flags)
    {
        return relation_leu(flags);
    }

    static bool
    rel_gtu(md::uint32 flags)
    {
        return relation_gtu(flags);
    }


    static bool
    rel_lt(md::uint32 flags)
    {
        return relation_lt(flags);
    }


    static bool
    rel_ge(md::uint32 flags)
    {
        return relation_ge(flags);
    }


    static bool
    rel_le(md::uint32 flags)
    {
        return relation_le(flags);
    }


    static bool
    rel_gt(md::uint32 flags)
    {
        return relation_gt(flags);
    }
}
