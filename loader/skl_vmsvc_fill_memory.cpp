#include <assert.h>
#include <string.h>
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    typedef struct vmsvc_fill_memory_desc_t : vmsvc_desc_t {
        /* Kernel.VMServiceStrCmpDesc */
        md::uint32 adr;         // Heap address to fill.
        md::uint32 n_bytes;     // Number of bytes to fill.
        md::uint32 value;       // Byte value to use as a fill.
    } vmsvc_fill_memory_desc_t;


    void
    vmsvc_fill_memory(md::uint32 adr)
    {
        md::uint8                *ptr     = heap::host_address(adr);
        vmsvc_fill_memory_desc_t *vmsvc   = reinterpret_cast<vmsvc_fill_memory_desc_t *>(ptr);
        md::uint8                *mem     = heap::host_address(vmsvc->adr);
        md::uint32                n_bytes = vmsvc->n_bytes;
        md::uint32                value   = vmsvc->value;

        assert((value % 256) == 0); // Ensure byte-sized value.
        memset(mem, static_cast<int>(value), n_bytes);
    }
}
