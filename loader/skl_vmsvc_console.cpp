#include <assert.h>
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    typedef struct vmsvc_console_desc_t : vmsvc_desc_t {
        /* Console.SVCConsole */
        md::uint32 op;
        md::uint32 len;
        md::uint32 buffer;
    } vmsvc_console_desc_t;


    void
    vmsvc_console(md::OADDR adr)
    {
        md::HADDR             ptr    = heap::host_address(adr);
        vmsvc_console_desc_t *vmsvc  = reinterpret_cast<vmsvc_console_desc_t *>(ptr);
        md::HADDR             buffer = heap::host_address(vmsvc->buffer);

        assert(vmsvc->op == 0); // SKLConsole.svcWrite

        dialog::print("%*s", vmsvc->len, buffer);
    }
}
