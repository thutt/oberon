/* Copyright (c) 2000, 2020, 2021 Logic Magicians Software */
/* $Id: kernintf.h,v 1.10 2002/02/05 04:39:59 thutt Exp $ */
#if !defined(_KERNINTF_H)
#define _KERNINTF_H

#include "heap.h"
#include "o3.h"
#include "md.h"

namespace kernintf
{
    void init_module(O3::module_t *module);
}
#endif
