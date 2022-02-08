/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_INT_REG_H)
#define _SKL_INT_REG_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_int_reg(cpu_t *cpu, md::uint32 inst);
}
#endif
