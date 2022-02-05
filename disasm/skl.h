#if !defined(SKL_H)
#define SKL_H

#include <stdio.h>
namespace skl
{
    void disassemble(FILE *fp, unsigned char *code, unsigned offs, unsigned len);
}

#endif
