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

    const md::uint32 default_heap_size_in_bytes = 64 * 1024 * 1024;
    const md::uint32 max_heap_size_in_megabytes = 127;

    const md::uint32 default_stack_size_in_bytes = 2 * 1024 * 1024;
    const md::uint32 max_stack_size_in_megabytes = 64;

    extern md::uint8  *allocated_heap;
    extern md::uint8  *oberon_heap;

    extern md::uint8  *oberon_stack; /* Address of stack allocation.
                                      * This is the bottom of the
                                      * stack (the lowest address).
                                      * The stack grows down.
                                      */

    extern md::uint32  total_heap_size_in_bytes;
    extern md::uint32  oberon_stack_size_in_bytes;
    extern md::uint32  oberon_heap_size_in_bytes;

    bool make_heap(md::uint32 heap_mb, md::uint32 stack_mb);
    void release_heap(md::uint32 heap_in_megabytes,
                      md::uint32 stack_in_megabytes);
    void dump(bool full_contents);

    md::uint8 *new_module(md::uint8 *td_adr, md::uint32 bytes);

    int align_block_size(int number_of_bytes);


    md::uint32 copy_command_line(const char *command_line);
    md::uint32 record_elem_array_len(const md::uint8 *array);
    md::uint32 simple_elem_array_len(const md::uint8 *array);
    md::uint32 pointer_elem_array_len(const md::uint8 *array);
    void fixup_td(md::uint8 *p, const char *lab,
                  md::uint8 *tdadr, bool is_array);

    md::uint8 *new_simple_elem_array(md::uint32  n_elements,
                                     md::uint32  elem_size,
                                     md::uint8  *td_adr);

    md::uint8 *new_record_elem_array(md::uint32  n_elements,
                                     md::uint32  elem_size,
                                     md::uint8  *td_adr);

    md::uint8 *new_pointer_elem_array(md::uint32  n_elements,
                                      md::uint32  elem_size,
                                      md::uint8  *td_adr);

    md::uint32 system_new(md::uint8 *&adr, md::uint32 size);


    static inline bool
    heap_pointer_ok(md::uint8 *p)
    {
        if (p != NULL) {
            if (!((allocated_heap <= p) &&
                  (p < (allocated_heap + total_heap_size_in_bytes)))) {
                return false;
            }
        }
        return true;
    }


    static inline md::uint8 *
    heap_to_host(md::uint32 heap)
    {
        md::uint64 result = static_cast<md::uint64>(heap);

        COMPILE_TIME_ASSERT(sizeof(md::uint8 *) == sizeof(md::uint64));
        return reinterpret_cast<md::uint8 *>(result);
    }


    static inline md::uint32
    host_to_heap(md::uint8 *ptr)
    {
        md::uint64 addr   = reinterpret_cast<md::uint64>(ptr);
        md::uint32 result = static_cast<md::uint32>(addr);

        COMPILE_TIME_ASSERT(sizeof(md::uint8 *) == sizeof(md::uint64));
        return result;
    }


    /* Returns true if the 32-bit address is within the Oberon heap. */
    static inline bool
    oberon_address_ok(md::uint32 addr, unsigned n_bytes)
    {
        return (heap_pointer_ok(heap_to_host(addr)) &&
                heap_pointer_ok(heap_to_host(addr + n_bytes)));
    }


    static inline void
    validate_heap_pointer(md::uint8 *p)
    {
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


    /* Given a 32-bit Oberon heap address, convert to a host OS heap
     * address.
     */
    static inline md::uint8 *
    host_address(md::uint32 offset)
    {
        md::uint8 *result = heap_to_host(offset);

        validate_heap_pointer(result);
        assert(offset == host_to_heap(result));
        return result;
    }


    /* Given a host OS heap address, convert to a 32-bit offset in the
     * Oberon heap.
     */
    static inline md::uint32
    heap_address_unchecked(md::uint8 *heap_ptr)
    {
        md::uint32 result = host_to_heap(heap_ptr);
        return result;
    }

    static inline md::uint32
    heap_address(md::uint8 *heap_ptr)
    {
        md::uint32 result = heap_address_unchecked(heap_ptr);
        validate_heap_pointer(heap_ptr);
        assert(heap_ptr == heap_to_host(result));
        return result;
    }

    static inline void
    write_word(md::uint32 addr, md::uint32 value)
    {
        // Writes a 4 byte value to memory.  This write will not
        // generate an exception.
        md::uint32 *p = reinterpret_cast<md::uint32 *>(host_address(addr));
        *p = value;
    }

    static inline md::uint32
    compute_heap_size(md::uint32 heap_mb, md::uint32 stack_mb)
    {
        return ((heap_mb * 1024 * 1024) +
                (stack_mb * 1024 * 1024));
    }
}
#endif
