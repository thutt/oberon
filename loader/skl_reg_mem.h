/* Copyright (c) 2021 Logic Magicians Software */
#if !defined(_SKL_REG_MEM_H)
#define _SKL_REG_MEM_H

#include "md.h"
#include "skl.h"

namespace skl {
    void op_reg_mem(cpu_t &cpu, md::uint32 inst);
}
#endif
