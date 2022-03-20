/* Copyright (c) 2000, 2020, 2021, 2022 Logic Magicians Software */
/* $Id: heap.h,v 1.14 2002/09/23 13:33:06 thutt Exp $ */
#if !defined(_HEAP_H)
#define _HEAP_H

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

#include "config.h"
#include "dialog.h"
#include "md.h"

namespace heap
{
    /* Block Size: Used as an atomic allocation size in the heap.
     * This value should be considered immutable since it is tightly
     * coupled with the heap allocation & GC in the Oberon system.
     * Changing this value will require a redesign of the whole memory
     * management scheme in Oberon.
     */


    static int const allocation_block_size = 16;

    const int default_heap_size_in_bytes = 64 * 1024 * 1024;
    const int max_heap_size_in_megabytes = 127;

    const int default_stack_size_in_bytes = 2 * 1024 * 1024;
    const int max_stack_size_in_megabytes = 64;

    extern md::HADDR allocated_heap;
    extern md::HADDR oberon_heap;

    extern md::HADDR oberon_stack; /* Address of stack allocation.
                                    * This is the bottom of the stack
                                    * (the lowest address).  The stack
                                    * grows down.
                                    */

    extern int total_heap_size_in_bytes;
    extern int oberon_stack_size_in_bytes;
    extern int oberon_heap_size_in_bytes;

    bool make_heap(int heap_mb, int stack_mb);
    void release_heap(int heap_in_megabytes, int stack_in_megabytes);
    void dump(bool full_contents);

    md::HADDR new_module(md::HADDR td_adr, int unpadded_record_size);

    int align_block_size(int number_of_bytes);

    md::OADDR copy_command_line(const char *command_line);
    md::int32 record_elem_array_len(const md::HADDR array);
    md::int32 simple_elem_array_len(const md::HADDR array);
    md::int32 pointer_elem_array_len(const md::HADDR array);
    void fixup_td(md::HADDR   p,
                  const char *lab,
                  md::HADDR   tdadr,
                  bool        is_array);

    md::HADDR new_simple_elem_array(int       n_elements,
                                    int       elem_size,
                                    md::HADDR td_adr);

    md::HADDR new_record_elem_array(int       n_elements,
                                    int       elem_size,
                                    md::HADDR td_adr);

    md::HADDR new_pointer_elem_array(int       n_elements,
                                     int       elem_size,
                                     md::HADDR td_adr);

    void system_new(md::HADDR &adr, int size);


    static inline bool
    heap_pointer_ok(md::HADDR p)
    {
        if (p != NULL) {
            if (!((allocated_heap <= p) &&
                  (p < (allocated_heap + total_heap_size_in_bytes)))) {
                return false;
            }
        }
        return true;
    }


    static inline md::HADDR
    heap_to_host(md::OADDR heap)
    {
        md::uint64 result = static_cast<md::uint64>(heap);

        COMPILE_TIME_ASSERT(sizeof(md::HADDR) == sizeof(md::uint64));

        /* The Oberon heap is identity mapped to simplify address
         * space conversions.
         */
        return reinterpret_cast<md::HADDR>(result);
    }


    static inline md::OADDR
    host_to_heap(md::HADDR ptr)
    {
        md::uint64 addr   = reinterpret_cast<md::uint64>(ptr);
        md::OADDR  result = static_cast<md::OADDR>(addr);

        COMPILE_TIME_ASSERT(sizeof(md::HADDR) == sizeof(md::uint64));
        return result;
    }


    /* Returns true if the 32-bit address is within the Oberon heap. */
    static inline bool
    oberon_address_ok(md::OADDR addr, int n_bytes)
    {
        md::OADDR end = addr + static_cast<md::OADDR>(n_bytes);
        return (heap_pointer_ok(heap_to_host(addr)) &&
                heap_pointer_ok(heap_to_host(end)));
    }


    static inline void
    validate_heap_pointer(md::HADDR p)
    {
        if (skl_alpha || skl_beta) {
            if (!heap_pointer_ok(p)) {
                const char *status[] = {
                    "bad",
                    "good"
                };
                fprintf(stderr, "Heap beg [%p]  %p  %s\n",
                        allocated_heap, p, status[allocated_heap <= p]);
                fprintf(stderr, "Heap end [%p]  %p  %s\n",
                        allocated_heap + total_heap_size_in_bytes, p,
                        status[p < allocated_heap + total_heap_size_in_bytes]);
                dialog::fatal("%s: Pointer not inside heap.", __func__);
            }
        }
    }


    /* Given a 32-bit Oberon heap address, convert to a host OS heap
     * address.
     */
    static inline md::HADDR
    host_address(md::OADDR offset)
    {
        md::HADDR result = heap_to_host(offset);

        validate_heap_pointer(result);
        assert(offset == host_to_heap(result));
        return result;
    }


    /* Given a host OS heap address, convert to a 32-bit offset in the
     * Oberon heap.
     */
    static inline md::OADDR
    heap_address_unchecked(md::HADDR heap_ptr)
    {
        md::OADDR result = host_to_heap(heap_ptr);
        return result;
    }


    static inline md::OADDR
    heap_address(md::HADDR heap_ptr)
    {
        md::OADDR result = heap_address_unchecked(heap_ptr);
        validate_heap_pointer(heap_ptr);
        assert(heap_ptr == heap_to_host(result));
        return result;
    }


    /* Given an Oberon address, return the ordinal index from the
     * beginning of the Oberon heap.
     *
     * Used by instruction cache system.
     */
    static inline int
    heap_offset(md::OADDR addr)
    {
        int offset = 0;
        assert((addr & (sizeof(md::OADDR) - 1)) == 0); /* Word aligned. */
        assert(oberon_address_ok(addr, sizeof(md::OADDR)));
        COMPILE_TIME_ASSERT(sizeof(allocated_heap) == 2 * sizeof(int));
        offset = static_cast<int>(heap_to_host(addr) - allocated_heap);
        /* Index must not be bigger than number of words in heap. */
        assert(offset < (total_heap_size_in_bytes /
                         static_cast<int>(sizeof(md::OADDR))));
        return offset;
    }

    static inline void
    write_word(md::OADDR addr, md::uint32 value)
    {
        // Writes a 4 byte value to memory.  This write will not
        // generate an exception.
        md::uint32 *p = reinterpret_cast<md::uint32 *>(host_address(addr));
        *p = value;
    }

    static inline int
    compute_heap_size(int heap_mb, int stack_mb)
    {
        return ((heap_mb * 1024 * 1024) +
                (stack_mb * 1024 * 1024));
    }
}
#endif
