/* Copyright (c) 2022 Logic Magicians Software */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "fileutils.h"

namespace fileutils {
    typedef struct search_info_t {
        int    n;               // Number of elements in search path.
        char  *env;             // strdup()-value of SKL_SEARCH_PATH
        char **elements;

        search_info_t(void) : n(0), env(NULL), elements(NULL)
        {
        }
    } search_info_t;

    static search_info_t *initialize_search_info(void);

    search_info_t *search_info = initialize_search_info();

    FILE *
    find_file_and_open(const char *name)
    {
        FILE         *fp;
        int           i        = 0;
        const size_t  name_len = strlen(name);

        while (i < search_info->n) {
            char        *elem     = search_info->elements[i];
            size_t       elem_len = strlen(elem);
            size_t       path_len = elem_len + 1 /* / */ + name_len + 1 /* 0x0 */;
            char        *pathname = new char[path_len];
            struct stat  stat_buf;

            strcpy(pathname, elem);
            if (pathname[strlen(pathname) - 1] != '/') {
                strcat(pathname, "/");
            }
            strcat(pathname, name);

            if (stat(pathname, &stat_buf) == 0) {
                fp = fopen(pathname, "rb");
                delete [] pathname;
                return fp;
            }

            delete [] pathname;
            ++i;
        }
        return NULL;
    }

    static search_info_t *
    initialize_search_info(void)
    {
        search_info_t *si = new search_info_t();
        char          *p;
        int            i;

        si->env = strdup(getenv("SKL_SEARCH_PATH")); /* Deliberately
                                                      * not deallocated. */

        if (si->env != NULL) {
            /* If SKL_SEARCH_PATH has a value, replace ':' with '\0',
             * counting each ':'.
             */
            si->n = 1;
            p = si->env;
            while (*p != '\0') {
                if (*p == ':') {
                    ++si->n;
                    *p = '\0';
                }
                ++p;
            }

            si->elements = new char *[si->n];
            i            = 0;
            p            = si->env;

            /* Populate si->elements with addresses in 'si->env' */
            while (i < si->n) {
                si->elements[i] = p;
                while (*p != '\0') {
                    ++p;
                }
                ++p;
                ++i;
            }
        }
        return si;
    }
}
