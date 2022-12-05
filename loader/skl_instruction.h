/* Copyright (c) 2022 Logic Magicians Software */
#if !defined(_SKL_INSTRUCTION_H)
#define _SKL_INSTRUCTION_H

#include "config.h"
#include "heap.h"
#include "o3.h"
#include "md.h"
#include "skl.h"

namespace skl {

    struct instruction_t {
        struct instruction_t *next;
        md::OINST        inst;
        md::OADDR        pc;
        int              opc;
        const char      *mne;
        O3::decode_pc_t  decoded_pc;

        instruction_t(md::OADDR    pc_,
                      md::OINST    inst_,
                      const char **mne_) :
            next(NULL),
            inst(inst_),
            pc(pc_),
            opc(field(inst, 4, 0)),
            mne(mne_[opc])
        {
            O3::decode_pc(pc, decoded_pc);
        }

        virtual ~instruction_t(void) { }
        virtual void interpret(skl::cpuid_t cpu) = 0;
    };

    extern instruction_t **cache;
    extern int             cache_elements;

    bool allocate_instruction_cache(int heap_mb, int stack_mb);
    void release_instruction_cache(void);
    void cache_instruction(instruction_t *cinst);

    static inline instruction_t *
    lookup_instruction(md::OADDR addr)
    {
        int offset = heap::heap_offset(addr);

        assert(((offset & (static_cast<int>(sizeof(md::uint32)) - 1)) == 0) &&
               offset < cache_elements);
        return cache[offset];
    }

}
#endif
