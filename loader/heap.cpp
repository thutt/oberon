/* Copyright (c) 2000, 2020, 2021, 2022, 2023 Logic Magicians Software */
/* $Id: heap.cpp,v 1.21 2002/02/05 04:41:02 thutt Exp $ */
#include <assert.h>
#include <ctype.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>

#include "config.h"
#include "dialog.h"
#include "kernintf.h"
#include "o3.h"
#include "heap.h"
#include "md.h"

namespace heap
{
    struct open_array_base_t { /* must not have any members */
        /* inv: block_size > 0
         * inv: block_size == number of bytes allocated for this block; header inclusive
         */
        md::int32 block_size;         // offset: 0
    };

    struct simple_elem_open_array_t : open_array_base_t {
        md::uint32 pad;         // offset: 4
        /* inv: bound > 0
         * inv: bound == max valid index
         */
        md::int32  bound;       // offset: 8
        md::uint32 td;          // offset: 12
        // offset: 16 array data starts here
    };

    struct pointer_elem_open_array_t : open_array_base_t {
        md::int32  n_elements;  // offset: 4
        md::int32  arrpos;      // offset: 8
        md::uint32 pad0;        // offset: 12
        md::uint32 pad1;        // offset: 16
        md::uint32 pad2;        // offset: 20
        /* inv: bound > 0
         * inv: bound == max valid index
         */
        md::int32  bound;       // offset: 24
        md::uint32 td;          // offset: 28
        // offset: 32 array data starts here
    };

    struct record_elem_open_array_t : open_array_base_t {
        md::int32  n_elements;  // offset: 4
        md::int32  count;       // offset: 8
        md::int32  arrpos;      // offset: 12
        md::uint32 pad0;        // offset: 16
        md::uint32 pad1;        // offset: 20

        /* inv: bound > 0
         * inv: bound == max valid index
         */
        md::int32  bound;       // offset: 24
        md::uint32 td;          // offset: 28
        // offset: 32 array data starts here
    };

    enum block_tag_t {
        BlkMark = 1 << 0,       // Marked for GC.
        BlkSyst = 1 << 1,       // System block.
        BlkFree = 1 << 2,       // Free block.
        BlkAray = 1 << 3        // Array block.
    };

    static block_tag_t SystemBlock = static_cast<block_tag_t>(BlkMark | BlkSyst);
    static block_tag_t FreeBlock   = (BlkFree);
    static const md::uint32 TagMask = static_cast<md::uint32>(~(BlkMark | BlkSyst | BlkFree | BlkAray));


    /* Heap Paragraph Alignment Value: ensures heap blocks are
     * paragraph aligned and their tag is [block-4].
     */
    static int const HPAV = allocation_block_size - sizeof(md::uint32); // inv: sizeof(int) == 4

    /* This references the beginning of the actual memory which was
     * allocated from the OS.  It is retained only to release the
     * memory.
     */
    md::HADDR        allocated_heap = NULL; /* Heap allocated from OS. */
    md::HADDR        oberon_heap    = NULL; /* Base address of Oberon heap. */
    md::HADDR        oberon_stack   = NULL;
    static md::HADDR curr_heap      = NULL; /* used for allocation */

    /* The allocation size of the entire Oberon heap, including the stack.
     *
     *  total_heap_size_in_bytes = oberon_heap_size_in_bytes +
     *                             oberon_stack_size_in_bytes
     */
    int total_heap_size_in_bytes;
    int oberon_stack_size_in_bytes;
    int oberon_heap_size_in_bytes;

    static md::uint32
    ptr_to_uint32(void *p)
    {
        /* Convert a pointer to a 32-bit integer.  This allows the
         * addresses contained in a heap dumps to be easily matched
         * with data written by debugging statements from Oberon.
         *
         * If the compile time assert fails, it means that the
         * static_cast<> is no longer correct for the target
         * architecture of this program.
         */
        COMPILE_TIME_ASSERT(sizeof(unsigned long) == 2 * sizeof(md::uint32));
        return static_cast<md::uint32>(reinterpret_cast<unsigned long>(p));
    }


    static void
    array_alloc_progress(const char *kind,
                         md::HADDR   block,
                         int         size,
                         md::HADDR   pointer,
                         md::uint32  n_elements,
                         md::uint32  element_size,
                         md::HADDR   td_adr,
                         md::HADDR   data)
    {
        dialog::diagnostic("%s: alloc=%xH; blk_size=%5.5xH; ptr=%xH; "
                           "len=%4.4xH; size=%4.4xH; tdadr=%xH data=%xH\n",
                           kind, ptr_to_uint32(block), size,
                           ptr_to_uint32(pointer),
                           n_elements, element_size,
                           ptr_to_uint32(td_adr),
                           ptr_to_uint32(data));
    }

    /* record_elem_array: return descriptor block for heap-based record array
     *
     * pre : p = NULL || (p IS record_elem_open_array_t)
     * post: result = NULL -> p = NULL
     * post: result != NULL -> result IS (record_elem_open_array_t *)
     */
    static const record_elem_open_array_t *
    record_elem_array(const md::HADDR p)
    {
        if (p == NULL) {
            return NULL;
        } else {
            return &(reinterpret_cast<const record_elem_open_array_t *>(p))[-1];
        }
    }

    /* simple_elem_array: return descriptor block for heap-based simple array
     *
     * pre : p = NULL || (p IS simple_elem_open_array_t)
     * post: result = NULL -> p = NULL
     * post: result != NULL -> result IS (simple_elem_open_array_t *)
     */
    static const simple_elem_open_array_t *
    simple_elem_array(const md::HADDR p)
    {
        if (p == NULL) {
            return NULL;
        } else {
            return &(reinterpret_cast<const simple_elem_open_array_t *>(p))[-1];
        }
    }

    /* pointer_elem_array: return descriptor block for heap-based pointer array
     *
     * pre : p = NULL || (p IS pointer_elem_open_array_t)
     * post: result = NULL -> p = NULL
     * post: result != NULL -> result IS (pointer_elem_open_array_t *)
     */
    static const pointer_elem_open_array_t *
    pointer_elem_array(const md::HADDR p)
    {
        if (p == NULL) {
            return NULL;
        } else {
            return &(reinterpret_cast<const pointer_elem_open_array_t *>(p))[-1];
        }
    }


    static void
    tag_info(md::uint32 tag)
    {
        static md::uint32 mask[] = { BlkMark, BlkSyst,
                                     BlkFree, BlkAray };
        const char *name[]       = { "BlkMark", "BlkSyst",
                                     "BlkFree", "BlkAray" };

        COMPILE_TIME_ASSERT(sizeof(tag) == 4 && sizeof(TagMask) == 4);
        tag &= ~TagMask;
        dialog::print("{");
        assert(sizeof(mask) / sizeof(mask[0]) == (sizeof(name) /
                                                  sizeof(name[0])));
        for (size_t i = 0; i < sizeof(mask) / sizeof(mask[0]); ++i) {
            if (tag & mask[i]) {
                dialog::print("%s", name[i]);
                tag &= ~mask[i];
                if (tag != 0) {
                    dialog::print(", ");
                }
            }
        }
        dialog::print("}");
    }

    static void basic_info(const char *l,
                           md::HADDR   blk,
                           md::int32   size,
                           md::uint32  tag,
                           md::OADDR   td,
                           bool        is_array)
    {
        dialog::print("%s Adr: %xH ", l, ptr_to_uint32(blk));

        if (size > 0xffff) {
            /* too big to fit in a 6-byte field */
            if (size > 1024 * 1024) {
                dialog::print("size: %4dMb   td: ", size / (1024 * 1024));
            } else {
                dialog::print("size: %4dKb   td: ", size / 1024);
            }
        }
        else {
            dialog::print("size: %6xH  td: ", size);
        }

        if (td != 0) {;
            if (is_array) {
                md::uint32 td_adr = static_cast<md::uint32>(td);
                md::uint32 masked = td_adr & ~static_cast<md::uint32>(BlkMark |
                                                                      BlkAray);
                md::int32  n      = static_cast<md::int32>(masked);
                bool       s0     = O3::MOD(n, allocation_block_size) != 0;
                dialog::print("%8.8xH%c",
                              td & ~static_cast<md::uint32>(BlkMark | BlkAray),
                              s0 || ((td & BlkAray) == 0) ? '*' : ' ');
            } else {
                dialog::print("%8.8xH%c", td & ~static_cast<md::uint32>(BlkMark),
                              O3::MOD(static_cast<md::int32>(td),
                                      allocation_block_size) != 0 ? '*' : ' ');
            }
        } else {
            dialog::print("%9.9s ", "n/a");
        }
        dialog::print(" flags: ");
        tag_info(tag);

        dialog::print(" ");
    }

    /* [hb, he) represent valid offsets from 'oberon_heap'.
     *
     */
    static void
    internal_dump(md::HADDR hb, md::HADDR he)
    {
        md::uint32 htag;
        md::int32 bsize;
        md::uint32 tdadr;

        if (config::options & config::opt_dump_heap) {
            assert(sizeof(md::uint32) == 4); // inv: block tags are 4 bytes in size
            dialog::print("\n"
                          "Heap begins at: %xH\n"
                          "Heap length   : %xH\n"
                          "Heap end      : %xH\n",
                          ptr_to_uint32(hb), total_heap_size_in_bytes,
                          ptr_to_uint32(he));

            while (hb < he) {
                md::HADDR   hp   = hb;
                md::uint32 *blkp = reinterpret_cast<md::uint32 *>(hp);
                htag             = reinterpret_cast<md::uint32 *>(hp)[0];

                if ((BlkSyst & htag) != 0) { /* sysblk */
                    bsize = static_cast<md::int32>(htag & TagMask);
                    basic_info("sblk", hb, bsize, htag, 0, false);
                } else if ((BlkAray & htag) != 0) { /* array block */
                    open_array_base_t *oab = reinterpret_cast<open_array_base_t *>(&(blkp[1]));
                    md::uint32 array_data;

                    bsize      = oab->block_size;
                    array_data = htag & TagMask; // inv: tdadr <-> address of array block

                    /* Array-block heap tags contain:
                     * `address of array data' + {[BlkMark, ]BlkAray}
                     *
                     * inv: `address of array data' MOD allocation_block_size = 0
                     */
                    assert((htag & (BlkMark | BlkSyst |
                                    BlkFree | BlkAray)) == (BlkMark | BlkAray) ||
                           (htag & (BlkMark | BlkSyst |
                                    BlkFree | BlkAray)) == (BlkAray));
                    assert(O3::MOD(static_cast<md::int32>(array_data & TagMask),
                                   allocation_block_size) == 0); // TD validity check

                    tdadr = reinterpret_cast<md::uint32 *>(array_data)[-1];
                    dialog::diagnostic("hb=%xH, htag=%xH, array_data=%xH, tdadr=%xH\n",
                                       hb, reinterpret_cast<md::uint32 *>(hb)[0],
                                       array_data, tdadr);
                    basic_info("ablk", hb, bsize, htag, tdadr, true);

                    assert((tdadr & (BlkMark | BlkSyst |
                                     BlkFree | BlkAray)) == (BlkMark | BlkAray) ||
                           (tdadr & (BlkMark | BlkSyst |
                                     BlkFree | BlkAray)) == (BlkAray));
                } else if ((BlkFree & htag) != 0) { /* free block */
                    bsize = static_cast<md::int32>(htag & TagMask);
                    basic_info("fblk", hb, bsize, htag, 0, false);
                } else {   /* record block */
                    tdadr = htag & TagMask;

                    // LMMD.RecBlockSize: allocated block size
                    bsize = reinterpret_cast<md::int32 *>(tdadr)[4];
                    basic_info("dblk", hb, bsize, htag, htag & TagMask, false);
                }
                dialog::print("\n");
                hb += bsize;
            }
        }
    }


    static void
    dump_contents(md::HADDR allocated, md::HADDR hb, md::HADDR he)
    {
        const int bytes_per_line = 16;
        int       i;

        /* The memory allocated from the host will be aligned to a
         * page boundary.  The Oberon heap is aligned to a 16-byte
         * boundary - SIZE(LONGINT) for accommodating memory block
         * tags.
         */
        assert(allocated + 16 - sizeof(md::uint32) == hb);

        /* Ensure heap size is a multiple of 16, because the code to
         * handle the (non-uniform) last line is not written.
         */
        assert((he - hb) % bytes_per_line == 0);
        dialog::print("\n\n");

        hb = allocated;

        while (hb < he) {
            md::HADDR p = hb;

            dialog::print("%xH:", heap_address_unchecked(hb));

            i = 0;
            while (i < bytes_per_line) {
                if (i != 0 && (i % 8) == 0) {
                    dialog::print("  %2.2x", p[i]);
                } else {
                    dialog::print(" %2.2x", p[i]);
                }
                ++i;
            }
            dialog::print("  |", p[i]);

            i = 0;
            while (i < bytes_per_line) {
                md::uint8 ch = p[i];
                if (isprint(ch)) {
                    dialog::print("%c", ch);
                } else {
                    dialog::print(".", ch);
                }
                ++i;
            }

            dialog::print("|\n");
            hb = p + bytes_per_line;
        }
    }


    void
    dump(bool full_contents)
    {
        assert(total_heap_size_in_bytes != 0);
        internal_dump(oberon_heap, oberon_heap + total_heap_size_in_bytes);
        if (full_contents) {
            dump_contents(allocated_heap,
                          oberon_heap, oberon_heap + total_heap_size_in_bytes);
        }
    }


    static md::uint32
    compute_heap_size(int sz)
    {
        int        page_size = getpagesize();
        md::uint32 heap_size = static_cast<md::uint32>(((sz + HPAV) + page_size) &
                                                       ~(page_size - 1));

        assert(page_size == 4096);
        assert(O3::MOD(static_cast<md::int32>(heap_size), page_size) == 0);
        return heap_size;
    }


    static void
    validate_heap_upper_bits(void)
    {
        const md::uint64 mask = static_cast<md::uint32>(~0);
        const md::uint64 addr = reinterpret_cast<md::uint64>(allocated_heap);

        /* The memory allocated with mmap() is specifcally placed in
         * the 32-bit address space so that Oberon addresses and host
         * addresses are the same.  This means the upper 32-bits of
         * all host pointers must be 0.
         *
         * If the addresses are not the same, special handling must be
         * written to treat an address as a 'host address' OR an
         * 'oberon address' depending on the context (a host address
         * cannot directly be stored in the Oberon heap, nor can an
         * Oberon address be used, without conversion.
         */
        if ((addr & ~mask) != 0) {
            dialog::fatal("%s: mmap() memory above 4Gb boundary", __func__);
        }
    }


    static bool
    internal_make_heap(int s)
    {
        /* The Oberon garbage collection system uses the top two bits
         * to signify information during traversal of pointers.
         * Therefore, the Oberon heap cannot be mapped above
         * 0x40000000.
         *
         * See Kernel.Mod { DescFlagsValidBit, DescFlagsSignBit }.
         * The implementation documentation also talks about how these
         * two bits function.  Reading Project Oberon section 8.3 for
         * more details on the pointer traversal algorithm.
         */
        UNUSED md::HADDR  heap_limit_address   = reinterpret_cast<md::HADDR>(0x40000000);
        void             *heap_desired_address = reinterpret_cast<void *>(0x4000000);
        md::uint32        heap_size            = compute_heap_size(s);
        md::uint32        tag;

        assert((reinterpret_cast<md::HADDR>(heap_desired_address) +
                heap_size) < heap_limit_address);

        /* Since HPAV is added to the beginning of the heap to ensure
         * that all blocks are aligned at a [paragraph] address and
         * that all block tags are aligned at a [paragraph-4] address,
         * HPAV is added to the allocation size so that the heap size
         * will remain a multiple of 16 (which is a requirement so
         * that `free blocks' (FreeBlk) can be placed onto the heap
         * (since the size of the free block is placed in the tag
         * field).
         */
        allocated_heap = static_cast<md::HADDR>(mmap(heap_desired_address,
                                                     heap_size,
                                                     (PROT_READ | PROT_WRITE),
                                                     (MAP_PRIVATE |
                                                      MAP_ANONYMOUS |
                                                      MAP_FIXED),
                                                     -1, 0));
        if (allocated_heap == MAP_FAILED) {
            perror("mmap");
            dialog::fatal("%s:  failed to mmap heap: errno: %d\n",
                          __func__, errno);
        }
        dialog::diagnostic("%s: allocated heap: %xH\n", __func__,
                           heap_address(allocated_heap));
        assert(allocated_heap + heap_size < heap_limit_address);
        if (allocated_heap != NULL) {
            md::OADDR h = host_to_heap(allocated_heap);

            memset(allocated_heap, '\0', heap_size);
            validate_heap_upper_bits();

            /* Heap must be aligned to a power-of-two boundary to
             * make internal oberon alignment work correctly.
             */
            assert(O3::MOD(static_cast<md::int32>(h), 4096) == 0);
            memset(allocated_heap, '\0', static_cast<size_t>(s + HPAV));

            /* Round up the start of the Oberon heap so the heap
             * management routines will work.
             */
            h += static_cast<md::OADDR>(O3::MOD(-static_cast<md::int32>(h),
                                                allocation_block_size));
            assert(O3::MOD(static_cast<md::int32>(h),
                           allocation_block_size) == 0);
            oberon_heap = heap_to_host(h);

            /* Since the allocation blocks must be aligned on
             * paragraph boundaries it comes as no surprise that the
             * actual user-accessiable data stored in a heap-block is
             * not aligned at a paragraph boundary.  Some space is
             * wasted at the beginning of the heap to cause this
             * alignment magic to happen (but it is a very small
             * amount of space).
             */
            oberon_heap += HPAV;

            {
                /* Ensure the 'oberon_heap' alignment is 1 word below
                 * a 16-byte boundary so that the memory allocation
                 * system is primed.
                 */
                h = host_to_heap(oberon_heap + sizeof(md::uint32));
                assert(O3::MOD(static_cast<md::int32>(h),
                               allocation_block_size) == 0);
            }

            /* Set up the heap as one giant free block. */
            tag = static_cast<md::uint32>(s | FreeBlock);
            reinterpret_cast<md::uint32 *>(oberon_heap)[0] = tag;
            reinterpret_cast<md::uint32 *>(oberon_heap)[1] = 0;

            curr_heap = oberon_heap;
        }
        return allocated_heap != NULL ? true : false;
    }


    bool
    make_heap(int heap_mb, int stack_mb)
    {
        bool r;

        oberon_heap_size_in_bytes  = heap_mb * 1024 * 1024;
        oberon_stack_size_in_bytes = stack_mb * 1024 * 1024;

        total_heap_size_in_bytes = heap::compute_heap_size(heap_mb, stack_mb);
        r = internal_make_heap(total_heap_size_in_bytes);
        return r;
    }


    void
    release_heap(int heap_in_megabytes, int stack_in_megabytes)
    {
        assert(total_heap_size_in_bytes == ((heap_in_megabytes +
                                             stack_in_megabytes) *
                                            1024 * 1024));
        munmap(allocated_heap, static_cast<size_t>(total_heap_size_in_bytes));
    }


    md::int32
    record_elem_array_len(const md::HADDR array)
    {
        const record_elem_open_array_t *arr = record_elem_array(array);

        if (arr != NULL) {
            return arr->bound;
        }
        dialog::fatal("array length attempted on NIL dynamic array of records");
        return 0;
    }


    md::int32
    simple_elem_array_len(const md::HADDR array)
    {
        const simple_elem_open_array_t *arr = simple_elem_array(array);

        if (arr != NULL) {
            return arr->bound;
        }
        dialog::fatal("array length attempted on NIL dynamic array of integral type");
        return 0;
    }


    md::int32
    pointer_elem_array_len(const md::HADDR array)
    {
        const pointer_elem_open_array_t *arr = pointer_elem_array(array);

        if (arr != NULL) {
            return arr->bound;
        }
        dialog::fatal("array length attempted on NIL dynamic array of pointers");
        return 0;
    }


    static md::HADDR
    get_heap_block(int size)
    {
        md::HADDR  retval = curr_heap;
        md::uint32 free_tag;
        md::uint32 allocated_bytes; // Size allocated on heap.
        md::uint32 free_space;

        COMPILE_TIME_ASSERT(sizeof(md::uint32) == 4); // O3 bitsets & heap field
                                                      // sizes are 4 bytes in O3
        curr_heap += size;

        allocated_bytes = heap_address(curr_heap) - heap_address(oberon_heap);
        free_space      = (static_cast<md::uint32>(total_heap_size_in_bytes) -
                           allocated_bytes);
        assert((free_space & ~TagMask) == 0);
        free_tag        = free_space | static_cast<md::uint32>(FreeBlock);

        /* make the remainder of the heap a free block */
        /* free block tags contain the size */
        reinterpret_cast<md::uint32 *>(curr_heap)[0] = free_tag;
        reinterpret_cast<md::uint32 *>(curr_heap)[1] = 0; // pointer to next block on free list
        return retval;
    }


    md::int32
    align_block_size(md::int32 number_of_bytes)
    {
        assert(sizeof(md::uint32) == 4); // O3 heap fields are 4 bytes in size
        // Add the block tag and then round to a multiple of the allocation size
        number_of_bytes +=
            static_cast<md::int32>(sizeof(md::uint32)); // Include block tag.
        return (number_of_bytes +
                O3::MOD(-number_of_bytes,
                        allocation_block_size));
    }


    void
    system_new(md::HADDR &adr, int size)
    {
        md::int32 block_size = align_block_size(size);
        md::int32 tag;

        // returns size of allocated block
        adr = get_heap_block(block_size);
        {
            /* Ensure the block is allocated correctly.  Each block
             * must be sizeof(md::uint32) before a
             * 'allocation_block_size' aligned address.
             */
             UNUSED md::HADDR a = adr + sizeof(md::uint32);
             assert(O3::MOD(static_cast<md::int32>(host_to_heap(a)),
                            allocation_block_size) == 0);
        }
        assert(sizeof(md::uint32) == 4);         // O3 bitsets are 4 bytes
        tag = block_size | SystemBlock;
        reinterpret_cast<md::uint32 *>(adr)[0] = static_cast<md::uint32>(tag); // block tag for GC
        adr += sizeof(md::uint32);
    }


    static int
    new_array(md::HADDR &adr, int size, md::uint32 dataoffs)
    {
        size = align_block_size(size);
        adr = get_heap_block(size);
        COMPILE_TIME_ASSERT(sizeof(md::uint32) == 4); // O3 block fields are 4 bytes in size
        assert((dataoffs % allocation_block_size) == 0);
        reinterpret_cast<md::uint32 *>(adr)[0] =
            heap_address(adr + sizeof(md::uint32) + dataoffs) | (BlkMark | BlkAray);

        COMPILE_TIME_ASSERT(sizeof(md::uint32) == 4); // O3 heap fields are 4 bytes in size
        adr += sizeof(md::uint32);       // bypass tag
        return size;
    }


    void
    fixup_td(md::HADDR   p,
             const char *lab,
             md::HADDR   td_adr,
             bool        is_array)
    {
        md::uint32 flags;

        assert(O3::MOD(static_cast<md::int32>(heap_address(td_adr)),
                       allocation_block_size) == 0);
        if (is_array) {
            flags = BlkMark | BlkAray;
        } else {
            flags = BlkMark;
        }

        if (p != NULL) {
            reinterpret_cast<md::uint32 *>(p)[-1] = heap_address(td_adr) | flags;
            dialog::diagnostic("(%s) td fixup of %xH to %xH\n", lab,
                               heap_address(p),
                               heap_address(td_adr));
        } else {
            dialog::diagnostic("(%s) td fixup of NIL would be %xH\n",
                               lab, heap_address(td_adr));
        }
    }


    md::HADDR
    new_module(md::HADDR td_adr, int unpadded_record_size)
    {
        md::HADDR adr;

        /* The modules loaded by the system loader are allocated as
         * system blocks.  This, of course, implies that they will
         * never participate in garbage collection.  At first glance
         * this may appear to be a serious defeciency, but upon deeper
         * thought the reader will realize that these modules cannot
         * be unloaded and reloaded without actually restarting the
         * whole system.  It is believed to be cleaner to disallow the
         * unloading of these bootstrapping modules than to allow them
         * to be unloaded - causing who knows what difficulties.
         * (Actually, nothing prevents the user from attempting to
         * reload the modules; only the original memory block will not
         * be garbage collected.)
         *
         * It would not be that hard to allocate these blocks as
         * non-system blocks, but it does not seem worth the effort to
         * write the code to do so.
         */
        system_new(adr, unpadded_record_size);
        fixup_td(adr, "mod", td_adr, false);
        return adr;
    }


    static void
    alignment_check(const char *label, md::HADDR adr)
    {
        if (adr != NULL) {
            md::uint32 v = heap_address(adr);
            if (O3::MOD(static_cast<md::int32>(v),
                        allocation_block_size) != 0) {
                fprintf(stderr,
                        "Allocated: %xH\n"
                        "Oberon   : [%xH..%xH)   [size: %d]\n"
                        "  Alloc  : %xH   [offset: %xH]\n",
                        ptr_to_uint32(allocated_heap),
                        heap_address(oberon_heap),
                        heap_address(oberon_heap + total_heap_size_in_bytes),
                        total_heap_size_in_bytes,
                        ptr_to_uint32(adr), v);
                dialog::fatal("%s: Allocation by '%s' is not aligned",
                              __func__, label);
            }
        }
    }

    md::HADDR
    new_simple_elem_array(int       n_elements,
                          int       elem_size,
                          md::HADDR td_adr)
    {
        md::HADDR                 result = NULL;
        md::HADDR                 user_block;
        md::HADDR                 blk;
        int                       size_in_bytes;
        simple_elem_open_array_t *arr;

        assert(sizeof(simple_elem_open_array_t) == 16);
        assert(O3::MOD(static_cast<md::int32>(heap_address(td_adr)),
                       allocation_block_size) == 0); /* td must be
                                                      * paragraph
                                                      * block_size-aligned */

        size_in_bytes = n_elements * elem_size;
        if (size_in_bytes != 0) {
            size_in_bytes += static_cast<int>(sizeof(simple_elem_open_array_t));

            COMPILE_TIME_ASSERT(sizeof(md::uint32) == 4); // O3 block tags are 4 bytes in size
            size_in_bytes   = new_array(blk, size_in_bytes,
                                        sizeof(simple_elem_open_array_t));
            arr             = reinterpret_cast<simple_elem_open_array_t *>(blk);
            arr->block_size = static_cast<md::int32>(size_in_bytes);
            arr->pad        = 0xdeadbeef;
            arr->bound      = n_elements;
            arr->td         = heap_address(td_adr) | (BlkMark | BlkAray);
            user_block      = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
            array_alloc_progress("SE",
                                 blk,
                                 size_in_bytes,
                                 user_block,
                                 static_cast<md::uint32>(n_elements),
                                 static_cast<md::uint32>(elem_size),
                                 td_adr,
                                 user_block);
            assert(sizeof(md::uint32) == 4); // O3 heap fields are 4 bytes in size
            result = user_block;
        } else {
            dialog::diagnostic("0-length SE\n");
        }
        alignment_check(__func__, result);
        return result;
    }


    md::HADDR
    new_record_elem_array(int       n_elements,
                          int       elem_size,
                          md::HADDR td_adr)
    {
        md::int32                 size;
        md::HADDR                 result = NULL;
        md::HADDR                 blk;
        record_elem_open_array_t *arr;

        assert(sizeof(record_elem_open_array_t) == 32);
        assert(O3::MOD(static_cast<md::int32>(heap_address(td_adr)),
                       allocation_block_size) == 0);
        size = n_elements * elem_size;

        if (size != 0) {
            md::HADDR data_adr;
            md::HADDR pointer;

            size += static_cast<md::int32>(sizeof(record_elem_open_array_t));

            assert(sizeof(md::uint32) == 4); // O3 heap fields are 4 bytes
            size            = new_array(blk, size, sizeof(record_elem_open_array_t));
            arr             = reinterpret_cast<record_elem_open_array_t *>(blk);
            arr->block_size = size;
            arr->n_elements = n_elements;
            arr->count      = 0;
            arr->arrpos     = 0;
            arr->pad0       = 0xdeadbeef;
            arr->pad1       = 0xdeadbeef;
            arr->bound      = n_elements;
            arr->td         = heap_address(td_adr) | (BlkMark | BlkAray);

            data_adr = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
            pointer = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
            array_alloc_progress("RE",
                                 blk,
                                 size,
                                 pointer,
                                 static_cast<md::uint32>(n_elements),
                                 static_cast<md::uint32>(elem_size),
                                 td_adr,
                                 data_adr);
            assert(sizeof(md::uint32) == 4); // O3 heap fields are 4 bytes in size
            result = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
        } else {
            dialog::diagnostic("0-length RE\n");
        }
        alignment_check(__func__, result);
        return result;
    }


    md::HADDR
    new_pointer_elem_array(int       n_elements,
                           int       elem_size,
                           md::HADDR td_adr)
    {
        md::int32                  size;
        md::HADDR                  result = NULL;
        md::HADDR                  blk;
        md::uint32                 td;
        pointer_elem_open_array_t *arr;

        assert(sizeof(pointer_elem_open_array_t) == 32);
        assert(O3::MOD(static_cast<md::int32>(heap_address(td_adr)),
                       allocation_block_size) == 0);
        assert(sizeof(md::uint32) == 4); // pointers in O3 are 4 bytes

        size = n_elements * static_cast<md::int32>(sizeof(md::uint32));

        if (size != 0) {
            md::HADDR data_adr;
            md::HADDR pointer;

            td = static_cast<md::uint32>((static_cast<md::int32>
                                          (heap_address(td_adr)) |
                                          (BlkMark | BlkAray)));

            size            += static_cast<md::int32>(sizeof(pointer_elem_open_array_t));
            size            = new_array(blk, size, sizeof(pointer_elem_open_array_t));
            arr             = (pointer_elem_open_array_t *)blk;
            arr->block_size = size;
            arr->n_elements = n_elements;
            arr->arrpos     = 0;
            arr->pad0       = 0xdeadbeef;
            arr->pad1       = 0xdeadbeef;
            arr->pad2       = 0xdeadbeef;
            arr->bound      = n_elements;
            arr->td         = td;

            data_adr = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
            pointer  = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
            array_alloc_progress("PE",
                                 blk,
                                 size,
                                 pointer,
                                 static_cast<md::uint32>(n_elements),
                                 0,
                                 td_adr,
                                 data_adr);
            assert(sizeof(md::uint32) == 4); // pointers in O3 are 4 bytes
            result = reinterpret_cast<md::HADDR>(&reinterpret_cast<md::uint32 *>(&arr->td)[1]);
        } else {
            dialog::diagnostic("0-length PE\n");
        }
        alignment_check(__func__, result);
        return result;
    }

    md::OADDR
    copy_command_line(const char *command_line)
    {
        /* Copy command line to a system block in the heap. */
        size_t    len = strlen(command_line) + 1;
        md::OADDR result;
        md::HADDR block;

        system_new(block, static_cast<int>(len));
        result = heap_address(block);
        strcpy(reinterpret_cast<char *>(block), command_line);
        return result;
    }
}
