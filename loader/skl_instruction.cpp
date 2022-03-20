/* Copyright (c) 2022 Logic Magicians Software */
#include <malloc.h>

#include "dialog.h"
#include "heap.h"
#include "skl_instruction.h"


namespace skl {
    int             cache_elements;
    instruction_t **cache;


    void
    release_instruction_cache(void)
    {
        int i;
        for (i = 0; i < cache_elements; ++i) {
            if (cache[i] != NULL) {
                delete cache[i];
            }
        }            
        delete [] cache;
    }


    bool
    allocate_instruction_cache(int heap_mb, int stack_mb)
    {
        int heap_bytes = heap::compute_heap_size(heap_mb, stack_mb);

        cache_elements = heap_bytes / static_cast<int>(sizeof(md::uint32));
        cache          = new instruction_t *[cache_elements](); // Zero-initialized with ().
        return cache != NULL;
    }


    void
    cache_instruction(instruction_t *cinst)
    {
        int offset = heap::heap_offset(cinst->pc);

        assert(((offset & (static_cast<int>(sizeof(md::uint32)) - 1)) == 0) &&
               offset < cache_elements &&
               cache[offset] == NULL);
        cache[offset] = cinst;
    }
}
