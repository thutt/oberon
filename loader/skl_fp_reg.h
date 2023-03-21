/* Copyright (c) 2023 Logic Magicians Software */
#if !defined(_SKL_FP_REG_H)
#define _SKL_FP_REG_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_fp_reg(md::OADDR pc, md::uint32 inst);
}
#endif
