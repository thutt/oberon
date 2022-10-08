#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {

    typedef enum env_op_t {
        env_lookup,
        env_copy
    } env_op_t;


    typedef struct vmsvc_env_desc_t : vmsvc_desc_t {
        /* Kernel.VMServiceHwdTrapDesc */
        md::uint32 op;
        md::uint32 key;  // Address of ASCIIZ string in Oberon memory.
    } vmsvc_env_desc_t;


    typedef struct vmsvc_lookup_desc_t : vmsvc_env_desc_t {
        md::int32 len;          // Number of chars, excluding 0X.
        bool      found;
    } vmsvc_lookup_desc_t;


    typedef struct vmsvc_copy_desc_t : vmsvc_env_desc_t {
        md::uint32 addr;
        md::uint32 n;  // Max chars, excluding 0X (space present, though).
    } vmsvc_copy_desc_t;


    static void
    lookup(vmsvc_lookup_desc_t *vmsvc, const char *key)
    {
        const char *val = getenv(key);

        vmsvc->found = val != NULL;
        if (vmsvc->found) {
            vmsvc->len = static_cast<md::int32>(strlen(val));
        }
    }


    static void
    copy(vmsvc_copy_desc_t *vmsvc, const char *key)
    {
        const char *k = getenv(key);
        char       *v = reinterpret_cast<char *>(heap::host_address(vmsvc->addr));

        assert(k != NULL);
        strncpy(v, k, vmsvc->n);
        v[vmsvc->n] = '\0';
    }


    void
    vmsvc_environment(md::OADDR adr)
    {
        md::HADDR         ptr   = heap::host_address(adr);
        vmsvc_env_desc_t *vmsvc = reinterpret_cast<vmsvc_env_desc_t *>(ptr);
        const char       *key   = reinterpret_cast<const char *>(heap::host_address(vmsvc->key));

        switch (vmsvc->op) {
        case env_lookup:
            lookup(reinterpret_cast<vmsvc_lookup_desc_t *>(vmsvc), key);
            break;

        case env_copy:
            copy(reinterpret_cast<vmsvc_copy_desc_t *>(vmsvc), key);
            break;

        default:
            dialog::print("%s: unsupported environment operation: %d\n",
                          __func__, vmsvc->op);
            dialog::fatal(__func__);
        }
    }
}
