/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {
    typedef enum vmsvc_file_op_t {
        VMSVC_FILE_OP_OPEN,
        VMSVC_FILE_OP_CLOSE,
        VMSVC_FILE_OP_READ,
        VMSVC_FILE_OP_WRITE,
        VMSVC_FILE_OP_UNLINK,
        VMSVC_FILE_OP_RENAME,
        VMSVC_FILE_OP_SEEK,
        VMSVC_FILE_OP_MKSTEMP
    } vmsvc_file_op_t;


    typedef struct vmsvc_file_desc_t : vmsvc_desc_t {
        md::uint32 op;
    } vmsvc_file_desc_t;


    typedef struct vmsvc_mkstemp_desc_t : vmsvc_file_desc_t {
        md::uint32 templ;
        md::int32  fd;
    } vmsvc_mkstemp_desc_t;


    typedef struct vmsvc_rw_desc_t : vmsvc_file_desc_t {
        md::int32  fd;
        md::int32  bytes;
        md::uint32 buffer;
        md::int32  result;
    } vmsvc_rw_desc_t;


    typedef struct vmsvc_open_desc_t : vmsvc_file_desc_t {
        md::uint32 flags;
        md::uint32 mode;
        md::uint32 pathname;    /* Oberon heap address of pathname. */
        md::int32  fd;
    } vmsvc_open_desc_t;


    typedef struct vmsvc_close_desc_t : vmsvc_file_desc_t {
        md::int32   fd;
    } vmsvc_close_desc_t;


    typedef struct vmsvc_unlink_desc_t : vmsvc_file_desc_t {
        md::uint32 pathname;    /* Oberon heap address of pathname. */
        md::int32  result;
    } vmsvc_unlink_desc_t;


    typedef struct vmsvc_rename_desc_t : vmsvc_file_desc_t {
        md::uint32 old_pathname; /* Oberon heap address of pathname. */
        md::uint32 new_pathname; /* Oberon heap address of pathname. */
        md::int32  result;
    } vmsvc_rename_desc_t;


    typedef struct vmsvc_seek_desc_t : vmsvc_file_desc_t {
        md::int32 fd;
        md::int32 pos;
        md::int32 whence;
        md::int32 new_pos;
    } vmsvc_seek_desc_t;


    typedef struct vmsvc_stat_desc_t : vmsvc_file_desc_t {
        md::uint32 dev;
        md::uint32 ino;
        md::uint32 mode;
        md::uint32 nlink;
        md::uint32 uid;
        md::uint32 gid;
        md::uint32 rdev;
        md::uint32 blksz;
        md::uint32 blkcnt;
        md::uint32 atime;
        md::uint32 mtime;
        md::uint32 ctime;
    } vmsvc_stat_desc_t;


    static void
    open_file(vmsvc_open_desc_t *svc)
    {
        md::HADDR path  = heap::host_address(svc->pathname);
        md::int32 flags = static_cast<md::int32>(svc->flags);
        mode_t    mode  = static_cast<mode_t>(svc->mode);

        svc->fd = open(reinterpret_cast<const char *>(path), flags, mode);
    }


    static void
    make_temp_file(vmsvc_mkstemp_desc_t *svc)
    {
        md::HADDR templ = heap::host_address(svc->templ);
        svc->fd = mkstemp(reinterpret_cast<char *>(templ));
    }


    static void
    write_file(vmsvc_rw_desc_t *svc)
    {
        ssize_t s = ::write(svc->fd, heap::host_address(svc->buffer),
                            static_cast<size_t>(svc->bytes));
        assert(s == static_cast<md::int32>(s));
        svc->result = static_cast<md::int32>(s);
    }


    static void
    read_file(vmsvc_rw_desc_t *svc)
    {
        ssize_t n = ::read(svc->fd, heap::host_address(svc->buffer),
                           static_cast<size_t>(svc->bytes));
        assert(n == static_cast<md::int32>(n));
        svc->result = static_cast<md::int32>(n);
    }


    static void
    close_file(vmsvc_close_desc_t *svc)
    {
        close(svc->fd);
    }


    static void
    unlink_file(vmsvc_unlink_desc_t *svc)
    {
        md::HADDR pathname = heap::host_address(svc->pathname);
        svc->result = unlink(reinterpret_cast<const char *>(pathname));
    }


    static void
    rename_file(vmsvc_rename_desc_t *svc)
    {
        md::HADDR old_pathname = heap::host_address(svc->old_pathname);
        md::HADDR new_pathname = heap::host_address(svc->new_pathname);
        svc->result = rename(reinterpret_cast<const char *>(old_pathname),
                             reinterpret_cast<const char *>(new_pathname));
    }


    static void
    seek_file(vmsvc_seek_desc_t *svc)
    {
        off_t pos = lseek(svc->fd, svc->pos, svc->whence);
        assert(pos == static_cast<md::int32>(pos));
        svc->new_pos = static_cast<md::int32>(pos);
    }


    void
    vmsvc_file(md::OADDR adr)
    {
        md::HADDR          ptr   = heap::host_address(adr);
        vmsvc_file_desc_t *vmsvc = reinterpret_cast<vmsvc_file_desc_t *>(ptr);

        switch (vmsvc->op) {
        case VMSVC_FILE_OP_OPEN:
            open_file(reinterpret_cast<vmsvc_open_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_CLOSE:
            close_file(reinterpret_cast<vmsvc_close_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_READ:
            read_file(reinterpret_cast<vmsvc_rw_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_WRITE:
            write_file(reinterpret_cast<vmsvc_rw_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_UNLINK:
            unlink_file(reinterpret_cast<vmsvc_unlink_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_RENAME:
            rename_file(reinterpret_cast<vmsvc_rename_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_SEEK:
            seek_file(reinterpret_cast<vmsvc_seek_desc_t *>(vmsvc));
            break;

        case VMSVC_FILE_OP_MKSTEMP:
            make_temp_file(reinterpret_cast<vmsvc_mkstemp_desc_t *>(vmsvc));
            break;

        default:
            dialog::not_implemented("%s: undefined file operation '%d'",
                                    __func__, vmsvc->op);
        }
    }
}
