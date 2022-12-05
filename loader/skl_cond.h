/* Copyright (c) 2021, 2022 Logic Magicians Software */
#if !defined(_SKL_COND_H)
#define _SKL_COND_H

#include "md.h"
#include "skl_instruction.h"
#include "skl.h"

namespace skl {
    skl::instruction_t *op_conditional_set(md::OADDR pc, md::OINST inst);
}
#endif
