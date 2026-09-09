/* Copyright (c) 2022-2026 Logic Magicians Software */
#include <stdlib.h>

#include "dialog.h"
#include "heap.h"
#include "skl_instruction.h"


namespace skl {
    unsigned long   cache_elements;
    instruction_t **cache;


    void
    release_instruction_cache(void)
    {
        if (false) {
            /* There is no actual need to carefully destroy the cache
             * and every skl::instruction_t created because the
             * program is going to exit and the OS will recover all
             * allocated resources.  Disabling this decreases
             * prompt-to-prompt runtime characteristics.
             */
            unsigned long i;
            for (i = 0; i < cache_elements; ++i) {
                if (cache[i] != NULL) {
                    delete cache[i];
                }
            }
            delete [] cache;
        }
    }


    bool
    allocate_instruction_cache(int heap_mb, int stack_mb)
    {
        unsigned long heap_bytes = static_cast<unsigned long>(heap::compute_heap_size(heap_mb,
                                                                                      stack_mb));
        unsigned long elements = heap_bytes / static_cast<unsigned long>(sizeof(md::uint32));

        cache_elements = elements;
        cache          = new instruction_t *[cache_elements](); // Zero-initialized with ().
        return cache != NULL;
    }


    void
    cache_instruction(instruction_t *cinst)
    {
        unsigned int offset = heap::heap_offset(cinst->pc);

        assert(((offset & (static_cast<unsigned int>(sizeof(md::uint32)) - 1)) == 0) &&
               offset < cache_elements &&
               cache[offset] == NULL);
        cache[offset] = cinst;
    }
}
