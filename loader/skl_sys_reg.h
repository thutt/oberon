/* Copyright (c) 2022 Logic Magicians Software */
#if !defined(_SKL_SYS_REG_H)
#define _SKL_SYS_REG_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_sys_reg(cpu_t *cpu, md::uint32 inst);
}
#endif
