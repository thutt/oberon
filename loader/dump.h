/* Copyright (c) 2021 Logic Magicians Software */
#if !defined(_DUMP_H)
#define _DUMP_H
namespace dump
{
    void hex(const unsigned char *lab, const unsigned char *buf,
             int len, int address_offset);
}
#endif
