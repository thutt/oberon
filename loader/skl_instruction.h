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
        skl::cpu_t      *cpu;
        md::uint32       inst;
        md::uint32       pc;
        unsigned         opc;
        const char      *mne;
        O3::decode_pc_t  decoded_pc;

        instruction_t(skl::cpu_t *cpu_,
                      md::uint32  inst_,
                      const char **mne_) :
            cpu(cpu_),
            inst(inst_),
            pc(cpu_->pc),
            opc(field(inst, 4, 0)),
            mne(mne_[opc])
        {
            O3::decode_pc(pc, decoded_pc);
        }

        virtual ~instruction_t(void) { }
        virtual void interpret(void) = 0;
    };

    extern instruction_t **cache;
    extern md::uint32 cache_elements;

    bool allocate_instruction_cache(md::uint32 heap_mb, md::uint32 stack_mb);
    void release_instruction_cache(void);
    void cache_instruction(instruction_t *cinst);

    static inline instruction_t *
    lookup_instruction(md::uint32 addr)
    {
        unsigned offset = heap::heap_offset(addr);

        assert(((offset & (sizeof(md::uint32) - 1)) == 0) &&
               offset < cache_elements);
        return cache[offset];
    }

}
#endif
