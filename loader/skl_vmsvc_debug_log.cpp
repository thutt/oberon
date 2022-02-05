#include <assert.h>
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "md.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    typedef struct vmsvc_debug_log_desc_t : vmsvc_desc_t {
        md::uint32 op;
        md::uint32 data;
        md::uint32 adr;
    } vmsvc_debug_log_desc_t;


    void
    vmsvc_debug_log(md::uint32 adr)
    {
        md::uint8              *ptr   = heap::host_address(adr);
        vmsvc_debug_log_desc_t *vmsvc = reinterpret_cast<vmsvc_debug_log_desc_t *>(ptr);
        md::uint32              l     = vmsvc->data;

        switch (vmsvc->op) {
        case 0: {               // Character
            dialog::print("%c", l);
            break;
        }

        case 1: {               // String
            md::uint8 *p = heap::host_address(vmsvc->adr);

            dialog::print("%.*s", l, p);
            break;
        }

        case 2: {               // Boolean
            dialog::print("%s", l == 0 ? "FALSE" : "TRUE");
            break;
        }

        case 3: {               // Hex integer
            dialog::print("%8.8xH", l);
            break;
        }

        case 4: {               // Integer
            dialog::print("%u", l);
            break;
        }
            
        case 5: {               // Newline
            dialog::print("\n");
            break;
        }

        case 6: {               // Hex character
            dialog::print("%2.2xX", l);
            break;
        }

        default:
            dialog::internal_error("%s: unhandled Kernel debug log", __func__);
        }

    }
}
