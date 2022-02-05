/* Copyright (c) 2000, 2021 Logic Magicians Software */
#if !defined(_O3_H)
#define _O3_H

#include "md.h"

namespace O3
{
    typedef char *name_t;
    typedef char decode_pc_t[128]; /* Decoded 'pc' to <Module>.<offset> */

    struct module_t;

    typedef struct bootstrap_symbols_t {
        const char *name;
        md::uint32 adr;
    } bootstrap_symbols_t;

    struct uses_info_t {
        md::uint32  name;       /* POINTER TO ARRAY OF CHAR */
        md::uint32  pbfprint;   /* LONGINT */
        md::uint32  module;     /* (module_t *) */
    };

    struct export_t {
        md::uint32 name;        /* (name_t) (POINTER TO ARRAY OF CHAR)*/
        md::uint32 fprint;      /* LONGINT */
        md::uint32 pvfprint;    /* LONGINT */
        md::uint32 adr;         /* POINTER */
        md::uint16 kind;        /* INTEGER */
    };

    struct cmd_t {
        md::uint32 name;        /* name_t */
        md::uint32 adr;
    };

    typedef md::uint32  typedesc_array_t;
    typedef export_t    export_array_t;
    typedef cmd_t       cmds_array_t;
    typedef md::uint32  ptr_array_t;
    typedef module_t   *imports_array_t;
    typedef md::uint8   data_array_t;
    typedef md::uint8   refs_array_t;

    struct module_t {
        md::uint32 next;        /* Oberon: 'module_t *' */
        md::int32  refcnt;      /* number of references to this module */
        md::int32  sb;          /* static base - offset in module 'data' where data begins  */
        md::uint32 finalize;    /* (void (*finalize)(void)) */
        md::uint32 tdescs;      /* (typedesc_array_t *) */
        md::uint32 exports;     /* (export_array_t *) exported data */
        md::uint32 privates;    /* (export_array_t *) private data */
        md::uint32 commands;    /* (cmds_array_t *) exported commands */
        md::uint32 pointers;    /* (ptr_array_t *) offsets of global pointers; for GC */
        md::uint32 imports;     /* (imports_array_t *) imported modules */
        md::uint32 jumps;       /* (data_array_t *) case tables */
        md::uint32 data;        /* (data_array_t *) data (const & variable) */
        md::uint32 tddata;      /* (data_array_t *) type descriptor records */
        md::uint32 code;        /* POINTER TO ARRAY OF SYSTEM.BYTE. */
        md::uint32 refs;        /* (refs_array_t *) Oberon references (for Post Mortem Debugger */
        md::uint32 name;        /* Oberon: POINTER TO ARRAY OF CHAR. */
    };
    extern const int sizeof_module_t;
    extern bootstrap_symbols_t bootstrap_symbol[];

    extern md::uint32 module_list; /* Oberon: module_t * */
    extern md::int32  n_inited;
    extern md::int32  n_loaded;

    void get_kernel_td_info(module_t *module);
    void fixup_type_descriptors(void);
    void fixup_uses_type_descriptors(void);
    module_t *load(const char *name);
    void dump_module(module_t *module);
    void lookup_kernel_bootstrap_symbols(module_t *m);
    void verify_module_name(module_t *m, const char *mname);
    const char *module_name(module_t *m);

    /* find_module_and_offset:
     *
     *   Given an Oberon heap address, synthesize the module and the
     *   offset in the module's code block.
     *
     *   Only valid for code.
     */
    void find_module_and_offset(md::uint32   address,
                                module_t   *&module,
                                md::uint32  &offs);

    md::uint32 lookup_command(module_t *m, const char *cmd);
    void dump_module_list(void);


    void decode_pc__(md::uint32 pc, decode_pc_t &decode);
    static inline void
    decode_pc(md::uint32 pc, decode_pc_t &decode)
    {
        if (skl_trace) {
            decode_pc__(pc, decode);
        }
    }


    static inline md::uint32
    DIV(md::uint32 x, md::uint32 y)
    {
        if (x >= 0) {
            if (y > 0) {
                return x / y;
            } else {
                return -((x - 1 - y) / -y);
            }
        } else {
            if (y > 0) {
                return -((-x - 1 + y) / y);
            } else {
                return -x / -y;
            }
        }
    }


    static inline md::uint32
    MOD(md::uint32 x, md::uint32 y)
    {
        if (x >= 0) {
            if (y > 0) {
                return x % y;
            } else {
                if (x % -y == 0) {
                    return 0;
                } else {
                    return y + x % -y;
                }
            }
        } else {
            if (y > 0) {
                if (-x % y == 0) {
                    return 0;
                } else {
                    return y - (-x % y);
                }
            } else {
                return -(-x % -y);
            }
        }
    }
}
#endif
