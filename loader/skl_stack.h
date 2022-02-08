/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_STACK_H)
#define _SKL_STACK_H

#include "md.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_stack(cpu_t *cpu, md::uint32 inst);
}
#endif
