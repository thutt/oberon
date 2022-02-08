/* Copyright (c) 2022 Logic Magicians Software */
#include <malloc.h>

#include "dialog.h"
#include "heap.h"
#include "skl_instruction.h"


namespace skl {
    md::uint32      cache_elements;
    instruction_t **cache;


    void
    release_instruction_cache(void)
    {
        unsigned i;
        for (i = 0; i < cache_elements; ++i) {
            if (cache[i] != NULL) {
                delete cache[i];
            }
        }            
        delete [] cache;
    }


    bool
    allocate_instruction_cache(md::uint32 heap_mb, md::uint32 stack_mb)
    {
        md::uint32 heap_bytes = heap::compute_heap_size(heap_mb, stack_mb);

        cache_elements = heap_bytes / sizeof(md::uint32);
        cache          = new instruction_t *[cache_elements](); // Zero-initialized with ().
        return cache != NULL;
    }


    void
    cache_instruction(instruction_t *cinst)
    {
        unsigned offset = heap::heap_offset(cinst->pc);

        assert(((offset & (sizeof(md::uint32) - 1)) == 0) &&
               offset < cache_elements &&
               cache[offset] == NULL);
        cache[offset] = cinst;
    }
}
