/* Copyright (c) 2021, 2022 Logic Magicians Software */
#include <assert.h>
#include <dirent.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "o3.h"
#include "skl_vmsvc.h"

namespace skl {
    typedef enum vmsvc_directory_op_t {
        VMSVC_DIRECTORY_OPEN_DIR,
        VMSVC_DIRECTORY_READ_DIR,
        VMSVC_DIRECTORY_CLOSE_DIR,
        VMSVC_DIRECTORY_OP_MKTREE,
        VMSVC_DIRECTORY_OP_RMTREE
    } vmsvc_directory_op_t;


    typedef struct vmsvc_directory_desc_t : vmsvc_desc_t {
        md::uint32 op;
    } vmsvc_file_desc_t;


    typedef struct vmsvc_mktree_desc_t : vmsvc_directory_desc_t {
        md::uint32 path;
        md::int32  mode;
        md::int32  result;
    } vmsvc_tree_desc_t;


    static char *
    full_path(const char *path, const char *fname)
    {
        void *m = malloc(strlen(path)  +
                         1             + /* '/' */
                         strlen(fname) +
                         1);             /* '\0' */
        char *p = reinterpret_cast<char *>(m);
        strcpy(p, path);
        strcat(p, "/");
        strcat(p, fname);
        return p;
    }


    static void
    mktree(vmsvc_tree_desc_t *svc)
    {
        md::HADDR     opath = heap::host_address(svc->path);
        char         *path  = strdup(reinterpret_cast<const char *>(opath));
        char         *p     = path + 1; // Skip leading '/', if any.
        const mode_t  mode  = static_cast<mode_t>(svc->mode);
        int           r;
        size_t        l;

        svc->result = 0;
        l           = strlen(path);
        r           = 0;

        if (l == 0) {
            r = -1;              /* Zero-byte pathname => error. */
        } else if  (path[l - 1] == '/') {
            path[l - 1] = '\0';  /* Remove trailing '/'. */
        }

        while (r == 0 && p != NULL) {
            /* Consecutively replace each '/' with '\0' (and restore)
             * to build subdirectories.
             */
            p = strchr(p, '/');
            if (p != NULL ) {
                struct stat statbuf;

                *p = '\0';
                if (stat(path, &statbuf) != 0) {
                    r = mkdir(path, mode); /* Create missing path elements. */
                } else if (!S_ISDIR(statbuf.st_mode)) {
                    r = -1; /* Non-directory encountered in path. */
                }
                *p = '/';
                ++p;
            }
        }
        if (r == 0) {
            r = mkdir(path, mode); /* Make final leaf directory. */
        }
        if (r != 0) {
            svc->result = -1;
        }
        free(path);
    }


    static bool
    recursive_delete(const char *path, bool delete_directories)
    {
        bool           result;
        struct dirent *dirent;
        DIR           *dh;

        result = true;
        dh     = opendir(path);
        if (dh == NULL) {
            return false;       /* Directory open failed. */
        }

        while (result) {
            dirent = readdir(dh);
            if (dirent == NULL) {
                break;
            }

            if (strcmp(dirent->d_name, ".") != 0 &&
                strcmp(dirent->d_name, "..") != 0) {
                char *p = full_path(path, dirent->d_name);
                if (dirent->d_type == DT_DIR) {
                    if (!recursive_delete(p, delete_directories)) {
                        result = false; /* Subdirectory delete failed. */
                    }
                    if (delete_directories) {
                        if (rmdir(p) != 0) {
                            result = false; /* Directory removal failed. */
                        }
                    }
                } else if (unlink(p) != 0) {
                    result = false; /* File delete failed. */
                }
                free(p);
            }
        }
        closedir(dh);
        return result;
    }


    static void
    rmtree(vmsvc_tree_desc_t *svc)
    {
        md::HADDR  opath = heap::host_address(svc->path);
        char      *path  = strdup(reinterpret_cast<const char *>(opath));

        svc->result = 0;
        if (!recursive_delete(path, false) || /* Delete all files. */
            !recursive_delete(path, true)  || /* Delete now-empty subdirs. */
            rmdir(path) != 0) {
            svc->result = -1;
        }
        free(path);
    }


    void
    vmsvc_directory(md::OADDR adr)
    {
        md::HADDR               ptr   = heap::host_address(adr);
        vmsvc_directory_desc_t *vmsvc = reinterpret_cast<vmsvc_file_desc_t *>(ptr);

        switch (vmsvc->op) {
        case VMSVC_DIRECTORY_OPEN_DIR:
            dialog::not_implemented("%s: open directory", __func__);

        case VMSVC_DIRECTORY_READ_DIR:
            dialog::not_implemented("%s: read directory", __func__);

        case VMSVC_DIRECTORY_CLOSE_DIR:
            dialog::not_implemented("%s: close directory", __func__);


        case VMSVC_DIRECTORY_OP_MKTREE:
            mktree(reinterpret_cast<vmsvc_tree_desc_t *>(vmsvc));
            break;

        case VMSVC_DIRECTORY_OP_RMTREE:
            rmtree(reinterpret_cast<vmsvc_tree_desc_t *>(vmsvc));
            break;

        default:
            dialog::not_implemented("%s: undefined file operation '%d'",
                                    __func__, vmsvc->op);
        }
    }
}
