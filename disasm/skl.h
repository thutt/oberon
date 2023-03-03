/* Copyright (c) 2000, 2021-2023 Logic Magicians Software */
#if !defined(SKL_H)
#define SKL_H

#include <stdio.h>
namespace skl
{
    void disassemble(FILE *fp, unsigned char *code, int offs, int len);
}

#endif
