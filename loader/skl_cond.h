/* Copyright (c) 2021 Logic Magicians Software */
#if !defined(_SKL_COND_H)
#define _SKL_COND_H

#include "md.h"
#include "skl.h"

namespace skl {
    void op_conditional_set(cpu_t &cpu, md::uint32 inst);
}
#endif
