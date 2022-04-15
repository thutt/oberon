/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_COND_H)
#define _SKL_COND_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_conditional_set(cpu_t *cpu, md::OINST inst);
}
#endif
