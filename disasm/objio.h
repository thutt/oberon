/* Copyright (c) 2000, 2021-2023 Logic Magicians Software */
#if !defined(OBJIO_H)
#define OBJIO_H
#include <stdlib.h>
#include <string.h>

namespace objio
{
    static const int MaxImports = 31;
    static const int MaxPointerBlock = 100; /* OPM */
    static const int MaxConstBlock = 15000; /* OPL */
    static const int MaxCodeBlock = 96000; /* OPL */
    static const int MaxTypeDescBlock = 5000; /* OPL */

    enum file_mode_t {
        fm_skl,
        fm_x86
    };

    enum segment_type_t
    {
        segUndef = -1,
        segCode,
        segConst,
        segCase,
        segData,
        segExport,
        segCommand,
        segTypeDesc
    };

    enum exported_kind_t  /* exported symbol kinds */
    {
        /* The identifiers here must match those created by the
         * object-file writer embedded in the Oberon compiler.
         */
        e_const  = 1,
        e_type   = 2,
        e_var    = 3,
        e_xproc  = 4,
        e_iproc  = 4,
        e_cproc  = 5,
        e_struc  = 6,
        e_rectd  = 8,
        /* 7 is not used */
        e_darrtd = 9,
        e_arrtd  = 10
    };

    enum used_kind_t
    {
        u_const    = 1,
        u_type     = 2,
        u_var      = 3,
        u_xproc    = 4,
        u_iproc    = 4,
        u_cproc    = 5,
        u_pbstruc  = 6,
        u_pvstruc  = 7,
        u_rectd    = 8,
        u_darrtd   = 9,
        u_arrtd    = 10
    };

    enum tdesc_kind_t  /* type descriptor kinds */
    {
        t_rec     = 1,
        t_darray  = 2,
        t_array   = 3
    };

    enum fixup_kind_t
    {
        fk_none,
        fk_helper,
        fk_fixup
    };

    enum reference_info_kind_t
    {
        ri_var,
        ri_par,
        ri_varpar,
        ri_proc,
        ri_rectd,
        ri_arrtd,
        ri_darrtd
    };

    struct obj_str_desc_t
    {
        obj_str_desc_t  *next;
        int             i;
        unsigned char   *str;

        obj_str_desc_t(const unsigned char *s, int index) :
            next(NULL),
            i(index),
            str((unsigned char *)strdup((const char *)s))
        {
        }
        ~obj_str_desc_t(void) { free(str); }
    };

    struct fixup_desc_t
    {
        fixup_desc_t  *next;
        int           mode, segment, offs;
        unsigned char target; /* 1 -> symbol, 2 -> label, 3 = heap block size */

        // inv: target = 3 -> a0 is the unpadded record size
        int           a0, a1, a2;

        fixup_desc_t(int m, int s, int o, unsigned char t) :
          next(NULL), mode(m), segment(s), offs(o), target(t), a0(0), a1(0), a2(0) { }
    };

    struct helper_loc_desc_t
    {
        helper_loc_desc_t   *next;
        int                 offs;
        helper_loc_desc_t(int o) : next(NULL), offs(o) { }
    };

    struct helper_desc_t
    {
        helper_desc_t       *next;
        unsigned char       *module;
        unsigned char       *func;
        helper_loc_desc_t   *loc;
        helper_desc_t(unsigned char *m, unsigned char *f) :
        next(NULL), module(m), func(f), loc(NULL) { }
    };

    struct command_desc_t
    {
        command_desc_t   *next;
        unsigned char    *name;
        int              adr;
        command_desc_t(unsigned char *n, int a) :
            next(NULL),
            name(n),
            adr(a)
        {
        }
    };

    struct reference_info_desc_t
    {
        reference_info_desc_t *next;
        unsigned char         *name;
        reference_info_kind_t kind;
        unsigned char         form; /* type form */
        int                   adr;
        int                   len;
        reference_info_desc_t *locals;
        reference_info_desc_t(void) :
            next(NULL), name(NULL), kind(ri_var), form('\0'), adr(0), len(0), locals(NULL) { }
    };

    struct symbol_info_desc_t
    {
        symbol_info_desc_t  *next;
        unsigned char       *name;
        unsigned char       *ancestor;
        int                 fprint;
        int                 adr;
        unsigned char       *rectdname;
        unsigned char       *arrtdname;
        unsigned char       kind;
        union
        {
            int voffset;            // e_var
            int pentry;             // e_xproc
            int spvfprint;          // e_struct
            struct                  // e_rectd
            {
                int link;
                int recsize;
                int basemod;
                int ancestorfp;
                int n_meth;
                int n_inhmeth;
                int n_newmeth;
                int n_ptr;
                struct
                {
                    int methno;
                    int entry;
                } methinfo[128];
                int ptroffs[512];   // OPM.MaxRecPtrs
            } rectd;

            struct
            {
                int           form; // type of descriptor (1, 2, 3)
                int           n_dim; // number of dimensions
                unsigned char element_tag; // 0 -> element_form, 1 -> element_form = TD
                int           element_form; // element type form or type descriptor address
                int           mno; // record type descriptor module number
                int           fprint; // record type descriptor fingerprint
                int           n_static_dim; // number of static array dimensions; inv: 0 < n_static_dim <= 33
                int           static_dim[32];
            } darrtd;

            struct
            {
                unsigned char tag;
                int           kind; // type of descriptor (1, 2, 3)
                int           form;
                int           mno;
                int           fprint;
                int           n_dim;
                int           dim[32]; // array dimensions
            } arrtd;
        };
        symbol_info_desc_t(unsigned char ch) : next(NULL), name(NULL), ancestor(NULL), fprint(0),
                                               adr(0), rectdname(NULL), arrtdname(NULL), kind(ch) { }
    };

    struct use_info_desc_t
    {
        use_info_desc_t   *next;
        unsigned char     *name;
        int               fprint;
        int               adr;
        int               type_adr;
        unsigned char     *type_name;
        int               type_fprint;
        int               mno;
        unsigned char     kind;
        union
        {
            // per-symbol-type storage
        };
        use_info_desc_t(unsigned char tag, int i) :
            next(NULL),
            name(NULL),
            fprint(0),
            adr(0),
            type_adr(0),
            type_name(NULL),
            type_fprint(0),
            mno(i),
            kind(tag)
        {
        }
    };

    struct objfile_t
    {
        int refsize;
        int n_exp;
        int n_prv;
        int n_desc;
        int n_com;
        int n_ptr;
        int pc;
        int dsize;
        int constx;
        int typedescx;
        int casex;
        int exportx;
        int n_imports; // number of imported modules
        int n_helpers; // number of compiler helper fixup lists
        int n_fixups; // total number of fixups output
        file_mode_t file_mode;
        unsigned char *module;
        unsigned char *imports[MaxImports]; // 0..n_Imports
        symbol_info_desc_t *typedesc;
        symbol_info_desc_t *exports;
        symbol_info_desc_t *privates;
        use_info_desc_t *use;
        command_desc_t *command;
        reference_info_desc_t *refinfo;
        helper_desc_t *helper;
        fixup_desc_t *fixup;
        obj_str_desc_t *strings;
        int pointers[MaxPointerBlock];
        unsigned char constants[MaxConstBlock];
        unsigned char typedescs[MaxTypeDescBlock];
        unsigned char code[MaxCodeBlock];

        objfile_t(file_mode_t mode) :
            file_mode(mode),
            module(NULL), typedesc(NULL),
            exports(NULL), privates(NULL),
            use(NULL), command(NULL),
            refinfo(NULL), helper(NULL),
            fixup(NULL), strings(NULL)
            {
                for (unsigned i = 0; i < sizeof(imports) / sizeof(imports[0]); ++i)
                    imports[i] = NULL;
            }
        ~objfile_t(void)
            {
                delete module;
                delete typedesc;
                delete exports;
                delete privates;
                delete use;
                delete command;
                delete refinfo;
                delete helper;
                delete fixup;
                delete strings;
                for (unsigned i = 0; i < sizeof(imports) / sizeof(imports[0]); ++i)
                    delete imports[i];
            }
    };

    extern objfile_t *obj_info;
    file_mode_t open(const char *module);
    void close(void);
    void read(void);
    fixup_kind_t code_fixup(int pc);
    helper_desc_t *get_helper(int pc);
    fixup_desc_t *get_fixup(int pc);
}
#endif
