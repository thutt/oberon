/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_GEN_REG_H)
#define _SKL_GEN_REG_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_gen_reg(cpu_t *cpu, md::uint32 inst);
}
#endif
