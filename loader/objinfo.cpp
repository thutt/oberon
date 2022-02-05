/* Copyright (c) 2000, 2020 Logic Magicians Software */
/* $Id: objinfo.cpp,v 1.2 2000/06/24 21:28:09 thutt Exp $ */
#include "objinfo.h"

namespace objinfo
{
    const char * const seg_names[segEnd - segBegin] =
    {
        "code",
        "const",
        "case",
        "data",
        "export",
        "command",
        "typedesc",
        "tdesc",
    };
}
