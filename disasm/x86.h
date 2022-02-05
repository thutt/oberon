#if !defined(X86_H)
#define X86_H

#include <stdio.h>
namespace x86
{
    void disassemble(FILE *fp, unsigned char *code, int offs, int len);
}

#endif
