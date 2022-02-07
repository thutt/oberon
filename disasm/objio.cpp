#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "objio.h"

namespace objio
{
    static const int max_id_len    = 24; // Must match compiler limit.
    static const int OFTag_x86     = 0xf8310000;
    static const int OFVersion_x86 = 0x15100151;
    static const int OFTag_skl     = 0xf8320000;
    static const int OFVersion_skl = 0x11161967;

    static FILE      *obj_file = NULL;

    objfile_t *obj_info = NULL;


    static void
    read_bytes(void * x, int n_bytes)
    {
        int r;
        long pos;

        pos = ftell(obj_file);
        r = fread(x, 1, n_bytes, obj_file);

        if (r != n_bytes)
        {
            fprintf(stderr, "fatal error reading %d bytes at position %#lx\n", n_bytes, pos);
            exit(1);
        }
    }


    static void
    read_tag(const char *fn, int line, unsigned char expected)
    {
        unsigned char tag;
        long nr;
        nr = fread(&tag, sizeof(tag), 1, obj_file);
        if (nr != 1 || tag != expected) {
            fprintf(stderr, "%s(%d): found tag %#x at %#lx; expected %#x\n",
                    fn, line, tag, ftell(obj_file) - 1, expected);
            exit(-1);
        }
    }


    static void
    read_char(unsigned char &x)
    {
        int r;

        r = fread(&x, sizeof(x), 1, obj_file);
        if (r != 1)
            x = '\0';
    }


    static void
    read_lint(int &x)
    {
        read_bytes(&x, sizeof(x));
    }


    void
    find_string(int index, unsigned char *&s)
    {
        obj_str_desc_t *o = obj_info->strings;

        while ((o != NULL) && (o->i != (-index)))
            o = o->next;

        assert(o != NULL);
        s = o->str;
    }


    static void
    read_num(int &x)
    {
        unsigned char rCH;
        int n;
        long y;

        n = y = 0;
        read_char(rCH);

        while (rCH >= 0x80)
        {
            y += (rCH - 128) << n;
            n += 7;
            read_char(rCH);
        }

        if (n - 25 < 0)
            x = (rCH << 25) >> (25 - n);
        else
            x = (rCH << 25) << (n - 25);
        x += y;
    }


    static void
    read_raw_string(unsigned char *&str)
    {
        int i, len;
        
        read_num(len);
        /* The disassembler does not support fully dynamic string
         * lengths.  Since the bootstrap modules are easily controlled
         * in source form, it is not necessary to go to the extra
         * expense to ensure that all string lengths can be read in
         * correctly.  Modules.Mod does it the complete way
         */
        assert(len <= max_id_len);

        str = new unsigned char[len + 1];
        for (i = 0; i < len; ++i)
            read_char(str[i]);
        str[i] = '\0';
    }


    static void
    read_string(unsigned char *&str)
    {
        int index;

        read_num(index);
        if (index >= 0)
        {
            obj_str_desc_t *o;
            read_raw_string(str);
            o = new obj_str_desc_t(str, index);
            o->next = obj_info->strings;
            obj_info->strings  = o;

            /* free the raw string so that all data refers to the same
             * copy of the string in memory, instead of most copies
             * referring to the same location and the first one being
             * unique.
             */
            delete [] str;
            str = o->str;
        }
        else
            find_string(index, str);
    }


    file_mode_t
    open(const char *module)
    {
        /* pre: ASCIIZ(module) & (module <=> full name of the object file)
         */
        int         tag, version;
        file_mode_t file_mode = fm_x86;

        obj_file = fopen(module, "r");

        if (obj_file != NULL)
        {
            read_lint(tag); read_lint(version);
            if ((tag == OFTag_x86) || (version == OFVersion_x86)) {
                printf("%s: File mode: x86\n", __func__);
                file_mode = fm_x86;
            } else if ((tag == OFTag_skl) || (version == OFVersion_skl)) {
                printf("%s: File mode: SKL\n", __func__);
                file_mode = fm_skl;
            }
            else {
                fprintf(stderr, "invalid object file (tag=%x, version=%x)\n", tag, version);
                exit(1);
            }
            obj_info = new objfile_t(file_mode);
        }
        else
        {
            fprintf(stderr, "unable to open '%s'\n", module);
            exit(1);
        }
        return file_mode;
    }


    void
    close(void)
    {
        fclose(obj_file);
    }


    static void
    backup(int n)
    {
        fseek(obj_file, -n, SEEK_CUR);
    }


    static void
    read_symbol_info(symbol_info_desc_t *&info, int n_symbols)
    {
      	int fprint, adr, count;
      	symbol_info_desc_t *ndata;
      	unsigned char tag;
      	unsigned char *name;

        count = 0;
        while (count < n_symbols) {
            read_char(tag);
            ndata = new symbol_info_desc_t(tag);
            ndata->next = info; info = ndata;

            adr = 0;
            fprint = 0;

            switch (tag)
            {
            case e_const:  read_string(name); read_num(fprint); adr = 0; /* const */        break;
            case e_type:   read_string(name); read_num(fprint);           /* type */        break;
            case e_var:    read_string(name); read_num(fprint);                             break;
            case e_xproc:  read_string(name); read_num(fprint);                             break;
            case e_cproc:  read_string(name); read_num(fprint); adr = 0;                    break;
            case e_struc:  read_string(name); read_num(fprint); read_num(ndata->spvfprint); break;
            case e_rectd:  read_string(name); read_num(fprint);                             break;
            case e_darrtd: read_string(name); read_num(fprint);                             break;
            case e_arrtd:  read_string(name); read_num(fprint);                             break;
            default:
                fprintf(stderr, "unknown value '%#x' -- number of symbols %#x of %#x\n" ,
                        tag, count, n_symbols);
                exit(-1);
            }
            ndata->name = name;
            ndata->adr = adr;
            ndata->fprint = fprint;
            ++count;
        }
    }


    static void
    header_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x80);
        read_lint(obj_info->refsize);
        read_lint(obj_info->n_exp);
        read_lint(obj_info->n_prv);
        read_lint(obj_info->n_desc);
        read_lint(obj_info->n_com);
        read_lint(obj_info->n_ptr);
        read_lint(obj_info->n_helpers);
        read_lint(obj_info->n_fixups);
        read_lint(obj_info->pc);
        read_lint(obj_info->dsize);
        read_lint(obj_info->constx);
        read_lint(obj_info->typedescx);
        read_lint(obj_info->casex);
        read_lint(obj_info->exportx);
        read_lint(obj_info->n_imports);
        read_string(obj_info->module);
    }

    static void
    import_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x81);
        obj_info->imports[0] = obj_info->module;
        for (int i = 1; i <= obj_info->n_imports; ++i)
            read_string(obj_info->imports[i]);
    }

    static void
    export_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x82);
        obj_info->exports = NULL;
        read_symbol_info(obj_info->exports, obj_info->n_exp);
    }

    static void
    private_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x83);
        obj_info->privates = NULL;
        read_symbol_info(obj_info->privates, obj_info->n_prv);
    }

    static void
    name_num(unsigned char *&name, int &num)
    {
        unsigned char ch;

        read_char(ch);
        if (ch != '\0')
        {
            backup(1);
            read_string(name);
            num = 0;
        }
        else
        {
            name = NULL;
            read_num(num);
        }
    }


    static void
    typedesc_record(symbol_info_desc_t *ndata)
    {
        int i, fprint;
        unsigned char *name;

        name_num(name, fprint);
        read_num(ndata->rectd.recsize);
        read_num(ndata->rectd.basemod);

        if (ndata->rectd.basemod != -1) {
            read_string(ndata->ancestor);
            read_num(ndata->rectd.ancestorfp);
        }

        read_num(ndata->rectd.n_meth);
        read_num(ndata->rectd.n_inhmeth);
        read_num(ndata->rectd.n_newmeth);
        read_num(ndata->rectd.n_ptr);

        for (i = ndata->rectd.n_newmeth; i > 0; --i) {
            read_num(ndata->rectd.methinfo[i].methno);
            read_num(ndata->rectd.methinfo[i].entry);
        }

        for (i = ndata->rectd.n_ptr; i > 0; --i) {
            read_num(ndata->rectd.ptroffs[i]);
        }
    }


    static void
    typedesc_darray(symbol_info_desc_t *ndata)
    {
        int i, fprint;
        unsigned char tag;
        unsigned char *name;

        read_string(name);
        read_num(fprint);
        read_char(tag);
        i = tag;
        ndata->darrtd.form = i;
        read_num(ndata->darrtd.n_dim);

        switch (i) {
        case 1: /* simple element */
            read_num(ndata->darrtd.element_form);
            break;

        case 2: /* pointer element */
            read_num(ndata->darrtd.element_form);
            break;

        case 3: /* record element */
            read_num(ndata->darrtd.mno);
            read_string(ndata->rectdname);
            read_num(ndata->darrtd.fprint);
            break;

        case 4: /* array element */
            read_char(ndata->darrtd.element_tag);
            assert((ndata->darrtd.element_tag == '\0') || // Simple element
                   (ndata->darrtd.element_tag == '\1') || // Pointer
                   (ndata->darrtd.element_tag == '\2'));  // Record

            if (ndata->darrtd.element_tag == '\0') {
                read_num(ndata->darrtd.element_form); /* element form */
            } else if (ndata->darrtd.element_tag == '\1') {
                read_num(ndata->darrtd.element_form); /* element form */
            } else {
                (ndata->darrtd.element_tag == '\2');
                ndata->darrtd.element_form = -1; /* sentinel */
                read_num(ndata->darrtd.mno);
                read_string(ndata->rectdname);
                read_num(ndata->darrtd.fprint);
            }
            read_num(ndata->darrtd.n_static_dim);

            for (i = 0; i < ndata->darrtd.n_static_dim; ++i) {
                read_num(ndata->darrtd.static_dim[i]);
            }
            break;
        }
    }


    static void
    typedesc_array(symbol_info_desc_t *ndata)
    {
        int i, fprint;
        unsigned char tag;
        unsigned char *name;

        read_string(name);
        read_num(fprint);
        read_char(tag);
        i = tag;
        ndata->arrtd.tag = tag;

        switch (i) {
        case 1: /* static array of simple type */
            read_num(ndata->arrtd.form);
            break;

        case 2: /* static array of pointer */
            read_num(ndata->arrtd.form);
            break;

        case 3: /* static array of record */
            read_num(ndata->arrtd.mno);
            read_string(ndata->arrtdname);
            read_num(ndata->arrtd.fprint);
            break;

        default:
            assert(0);
        }

        read_num(ndata->arrtd.n_dim);
        for (i = 0; i < ndata->arrtd.n_dim; ++i) {
            read_num(ndata->arrtd.dim[i]);
        }
    }


    static void
    typedesc_block(void)
    {
        int n_desc;
        symbol_info_desc_t *list, *ndata;
        unsigned char tag;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x84);
        n_desc = 0;
        list = NULL;

        while (n_desc < obj_info->n_desc) {
            read_char(tag);
            ndata       = new symbol_info_desc_t(tag);
            ndata->next = list;
            list        = ndata;

            switch (tag) {
            case t_rec:
                typedesc_record(ndata);
                break;

            case t_darray:
                typedesc_darray(ndata);
                break;

            case t_array:
                typedesc_array(ndata);
                break;

            default:
                fprintf(stderr, "nofdesc=%#x, tag=%#x\n", n_desc, tag);
                assert(0);
            }
            ++n_desc;
        }
        obj_info->typedesc = list;
    }

    static void command_block(void)
    {
        unsigned char *name;
        command_desc_t *cmd;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x85);
        for (int i = 0; i < obj_info->n_com; ++i)
        {
            read_string(name);
            cmd = new command_desc_t(name, 0); /* actual address is a fixup; not stored here */
            cmd->next = obj_info->command; obj_info->command = cmd;
        }
    }

    static void pointer_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x86);
        for (int i = 0; i < obj_info->n_ptr; ++i)
            read_num(obj_info->pointers[i]);
    }

    static void constant_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x87); read_bytes(obj_info->constants, obj_info->constx);
    }

    static void typedescdata_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x88); read_bytes(obj_info->typedescs, obj_info->typedescx);
    }

    static void code_block(void)
    {
        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x89); read_bytes(obj_info->code, obj_info->pc);
    }

    static void uses_block(void)
    {
        use_info_desc_t *nuses;
        unsigned char tag;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x8a);
        for (int i = 0; i < obj_info->n_imports; ++i)
        {
            read_char(tag);
            while (tag != '\0')
            {
                nuses = new use_info_desc_t(tag, i + 1);
                nuses->next = obj_info->use;
                obj_info->use = nuses;

                switch (tag)
                {
                case 1:  /* Uconst */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 2:  /* Utype */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 3:  /* Uvar */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 4:  /* Uxproc, Uiproc */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 5:  /* Ucproc */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 6:  /* Upbstruc */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 7:  /* Upvstruc */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 8:  /* Urectd */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 9:  /* Udarrtd */ read_string(nuses->name); read_num(nuses->fprint); break;
                case 10:  /* Uarrtd */ read_string(nuses->name); read_num(nuses->fprint); break;
                }
                read_char(tag);

                if (tag == 6)
                { /* Upbstruc */
                    read_string(nuses->type_name); read_num(nuses->fprint); read_char(tag);
                }
                else if (tag == 7)
                { /* Upvstruc */
                    read_string(nuses->type_name); read_num(nuses->fprint); read_char(tag);
                }
            }
        }
    }

    static void helper_fixup_block(void)
    {
        int offs;
        helper_desc_t *help;
        helper_loc_desc_t *loc;
        unsigned char *module;
        unsigned char *func;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x8b);
        for (int i = 0; i < obj_info->n_helpers; ++i)
        {
            read_string(module);
            read_string(func);
            help = new helper_desc_t(module, func);
            help->next = obj_info->helper; obj_info->helper = help;

            read_num(offs);
            while (offs != -1)
            {
                loc = new helper_loc_desc_t(offs);
                loc->next = help->loc;
                help->loc = loc;
                read_num(offs);
            }
        }
    }

    static void fixup_block(void)
    {
        fixup_desc_t *fixup;
        int mode, segment, offs, kind, mnolev, adr, seg;
        unsigned char fixup_type;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x8c);
        for (int i = 0; i < obj_info->n_fixups; ++i)
        {
            read_num(mode); read_num(segment); read_num(offs);
            switch (mode)
            {
            case 0:
            case 1:
                read_char(fixup_type);
                assert(fixup_type  == '\1' || fixup_type == '\2');

                if (fixup_type == '\1') {
                    read_num(kind);
                    read_num(mnolev);
                    read_num(adr);
                } else {
                    read_num(seg);
                    read_num(adr);
                }

                fixup = new fixup_desc_t(mode, segment, offs, fixup_type);

                if (fixup_type == '\1') {
                    fixup->a0 = kind;
                    fixup->a1 = mnolev;
                    fixup->a2 = adr;
                } else {
                    fixup->a0 = seg;
                    fixup->a1 = adr;
                    fixup->a2 = 0;
                }
                break;

            case 2: /* FixBlk */
                read_num(adr);
                fixup = new fixup_desc_t(mode, segment, offs, 3);
                fixup->a0 = adr;
                break;

            default: assert(false);
            }
            fixup->next = obj_info->fixup;
            obj_info->fixup = fixup;
        }
    }

    static void reference_block(void)
    {
        reference_info_desc_t *sym;
        reference_info_desc_t *locals;
        unsigned char tag;

        read_tag(__PRETTY_FUNCTION__, __LINE__, 0x8d);
        obj_info->refinfo = NULL;
        read_char(tag);

        while (tag == 0x97) /* OPM.RefPointTag */
        {
            sym = new reference_info_desc_t();;
            sym->next = obj_info->refinfo;
            obj_info->refinfo = sym;
            sym->kind = ri_proc;
            read_num(sym->adr);
            read_num(sym->len);
            read_raw_string(sym->name);
            read_char(tag);

            while ((tag != 0x97) && (tag != 0x0)) /* eof character -- beware that no tag #$0 can be used */
            {
                locals = new reference_info_desc_t();

                switch (tag)
                {
                case  1: /* ST.var */ locals->kind = ri_var; break;
                case  2: /* ST.par */  locals->kind = ri_par; break;
                case  3: /* ST.varpar */ locals->kind = ri_varpar; break;
                case 16: /* ST.darrdesc */ locals->kind = ri_darrtd; break;
                case 17: /* ST.arrdesc */ locals->kind = ri_arrtd; break;
                case 18: /* ST.recdesc */ locals->kind = ri_rectd; break;
                }
                read_char(tag);
                locals->form = tag;
                read_num(locals->adr);
                read_raw_string(locals->name);
                locals->next = sym->locals;
                sym->locals = locals;
                read_char(tag);
            }
        }
    }

    void read(void)
    {
        header_block();
        import_block();
        export_block();
        private_block();
        typedesc_block();
        command_block();
        pointer_block();
        constant_block();
        typedescdata_block();
        code_block();
        uses_block();
        helper_fixup_block();
        fixup_block();
        reference_block();
    }

    static helper_desc_t *find_helper_internal(int pc)
    {
        for (helper_desc_t *hf = obj_info->helper; hf != NULL; hf = hf->next)
            for (helper_loc_desc_t *hl = hf->loc; hl != NULL; hl = hl->next)
                if (hl->offs == pc)
                    return hf;
        return NULL;
    }

    static fixup_desc_t *find_fixup_internal(int pc)
    {
        for (fixup_desc_t *ff = obj_info->fixup; ff != NULL; ff = ff->next)
            if ((ff->segment == segCode) && (ff->offs == pc))
                return ff;
        return NULL;
    }

    static bool find_helper(int pc)
    {
        return find_helper_internal(pc) != NULL;
    }

    static bool find_fixup(int pc)
    {
        return find_fixup_internal(pc) != NULL;
    }

    fixup_desc_t *get_fixup(int pc)
    {
        return find_fixup_internal(pc);
    }

    helper_desc_t *get_helper(int pc)
    {
        return find_helper_internal(pc);
    }

    fixup_kind_t code_fixup(int pc)
    {
        if (find_fixup(pc))
            return fk_fixup;
        if (find_helper(pc))
            return fk_helper;
        return fk_none;
    }
}
