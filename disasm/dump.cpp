#include <assert.h>
#include <stdio.h>
#include "objio.h"
#include "dump.h"
#include "skl.h"
#include "x86.h"

namespace dump
{
    static FILE *fp = stdout;

    static void put_hex(int i)
    {
        if (i < 0)
            fprintf(fp, "-0%XH", -i);
        else
            fprintf(fp, "0%XH", i);
    }

    static void header(void)
    {
        int i;

        fprintf(fp, "Module    : %s\n", objio::obj_info->module);
        fprintf(fp, "refsz     : %d (", objio::obj_info->refsize); put_hex(objio::obj_info->refsize);
        fprintf(fp, ")\nexp       : %d (",objio::obj_info->n_exp); put_hex(objio::obj_info->n_exp);
        fprintf(fp, ")\nprv       : %d (",objio::obj_info->n_prv); put_hex(objio::obj_info->n_prv);
        fprintf(fp, ")\ndesc      : %d (",objio::obj_info->n_desc); put_hex(objio::obj_info->n_desc);
        fprintf(fp, ")\ncom       : %d (",objio::obj_info->n_com); put_hex(objio::obj_info->n_com);
        fprintf(fp, ")\nptr       : %d (",objio::obj_info->n_ptr); put_hex(objio::obj_info->n_ptr);
        fprintf(fp, ")\nhelper    : %d (",objio::obj_info->n_helpers); put_hex(objio::obj_info->n_helpers);
        fprintf(fp, ")\nfixups    : %d (",objio::obj_info->n_fixups); put_hex(objio::obj_info->n_fixups);
        fprintf(fp, ")\npc        : %d (",objio::obj_info->pc); put_hex(objio::obj_info->pc);
        fprintf(fp, ")\ndsize     : %d (",objio::obj_info->dsize); put_hex(objio::obj_info->dsize);
        fprintf(fp, ")\nconstx    : %d (",objio::obj_info->constx); put_hex(objio::obj_info->constx);
        fprintf(fp, ")\ntypedescx : %d (",objio::obj_info->typedescx); put_hex(objio::obj_info->typedescx);
        fprintf(fp, ")\ncasex     : %d (",objio::obj_info->casex); put_hex(objio::obj_info->casex);
        fprintf(fp, ")\nexportx   : %d (",objio::obj_info->exportx); put_hex(objio::obj_info->exportx);
        fprintf(fp, ")\n");

        i = 0;
        while (objio::obj_info->imports[i] != NULL)
        {
            fprintf(fp, "import    : %-2d %s\n", i, objio::obj_info->imports[i]);
            ++i;
        }
    }

    static void commands(void)
    {
        objio::command_desc_t *cmd;

        cmd = objio::obj_info->command;
        if (cmd != NULL)
        {
            fprintf(fp, "Commands\n");
            while (cmd != NULL)
            {
                fprintf(fp, "  %s [%d ", cmd->name, cmd->adr); put_hex(cmd->adr);
                fprintf(fp, "]\n");
                cmd = cmd->next;
            }
        }
    }

    static void pointers(void)
    {
        if (objio::obj_info->n_ptr > 0)
        {
            fprintf(fp, "Pointers\n");
            for (int i = 0; i < objio::obj_info->n_ptr; ++i)
            {
                fprintf(fp, "  ");
                put_hex(objio::obj_info->pointers[i]);
                fprintf(fp, "\n");
            }
        }
    }

    static void sym_info(objio::symbol_info_desc_t *s)
    {
        fprintf(fp, "  ");
        switch (s->kind)
        {
        case objio::e_const:
            fprintf(fp, "CONST  %s %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_type:
            fprintf(fp, "TYPE   %s %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_cproc:
            fprintf(fp, "CPROC   %s %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_var:
            fprintf(fp, "VAR    %s %8.8x (adr: ", s->name, s->fprint); put_hex(s->voffset); fprintf(fp, ")\n");
            break;

        case objio::e_xproc:
            fprintf(fp, "PROC   %s %8.8x (entry: ", s->name, s->fprint); put_hex(s->pentry); fprintf(fp, ")\n");
            break;

        case objio::e_struc:
            fprintf(fp, "STRUC  %s (pb: %8.8x, pv: %8.8x)\n", s->name, s->fprint, s->spvfprint);
            break; 

        case objio::e_rectd:
            fprintf(fp, "RECTD  %s (pb: %8.8x, pv: %8.8x)\n", s->name, s->fprint, s->spvfprint);
            break;

        case objio::e_darrtd:
            fprintf(fp, "DARRTD %s (pb: %8.8x, pv: %8.8x)\n", s->name, s->fprint, s->spvfprint);
            break;

        case objio::e_arrtd:
            fprintf(fp, "ARRTD  %s (pb: %8.8x, pv: %8.8x)\n", s->name, s->fprint, s->spvfprint);
            break;
        default:  assert(false);
        }
    }

    static void exports(void)
    {
        objio::symbol_info_desc_t *s;
        int i;

        fprintf(fp, "Exports\n");
        s = objio::obj_info->exports;

        i = 0; while (s != NULL) { ++i; s = s->next; }
        s = objio::obj_info->exports;
        while (s != NULL)
        {
            --i;
            fprintf(fp, "%2.2d: ", i);
            sym_info(s);
            s = s->next;
        }
    }

    static void privates(void)
    {
        fprintf(fp, "Privates\n");
        for (objio::symbol_info_desc_t *s = objio::obj_info->privates; s != NULL; s = s->next)
            sym_info(s);
    }

    static void type_descriptors(void)
    {
        fprintf(fp, "Type Descriptors");
        for (objio::symbol_info_desc_t *s = objio::obj_info->typedesc; s != NULL; s = s->next)
        {
            fprintf(fp, "\n  ");

            switch (s->kind)
            {
            case objio::t_rec:
                if (s->name != NULL)
                    fprintf(fp, "RECTD  name=%s", s->name);
                else
                    fprintf(fp, "RECTD fprint=%#8.8x", s->fprint);

                fprintf(fp, " td adr="); put_hex(s->rectd.link);
                fprintf(fp, " recsize="); put_hex(s->rectd.recsize);
                fprintf(fp, " ");
                if (s->rectd.basemod == -1)
                {
                    if (s->ancestor != NULL)
                        fprintf(fp, "ancestor=%s", s->ancestor);
                    else
                        fprintf(fp, "ancestor fp=%8.8x", s->rectd.ancestorfp);
                }
                else
                    fprintf(fp, "ancestor module=%d", s->rectd.basemod);

                fprintf(fp, "\n        nofMeth=%d nofInhMeth=%d nofNewMeth=%d nofPtrs=%d\n",
                        s->rectd.n_meth, s->rectd.n_inhmeth, s->rectd.n_newmeth, s->rectd.n_ptr);
                fprintf(fp, "        Methods\n");

                for (int i = s->rectd.n_meth; i > 0; --i)
                {
                    fprintf(fp, "          ");
                    put_hex(s->rectd.methinfo[i].entry);
                    fprintf(fp, ":");
                    put_hex(s->rectd.methinfo[i].methno);
                    fprintf(fp, "VMT[");
                    put_hex(-4 /* CGL.TBPOffset */ - s->rectd.methinfo[i].methno * 4);
                    fprintf(fp, "]");
                }

                fprintf(fp, "        Pointers\n");
                for (int i = s->rectd.n_ptr; i > 0; --i)
                {
                    fprintf(fp, "           ");
                    put_hex(s->rectd.ptroffs[i]);
                    fprintf(fp, "\n");
                }
                break;

            case objio::t_darray:

                if (s->name != NULL)
                    fprintf(fp, "DARTD  name=%s, fprint=%8.8x ", s->name, s->fprint);
                else
                    fprintf(fp, "DARTD fprint=%8.8x ", s->fprint);

                fprintf(fp, "adr="); put_hex(s->adr);
                fprintf(fp, " nofDim="); put_hex(s->darrtd.n_dim);
                fprintf(fp, "\n");

                switch (s->darrtd.form)
                {
                case 1: /* to basic type */
                    fprintf(fp, "    basic type=%d\n", s->darrtd.element_form);
                    break;
                case 2: /* to pointer */
                    fprintf(fp, "    pointer\n");
                    break;
                case 3: /* to record */
                    fprintf(fp, "    record td=%s->%s [fp=%8.8X]\n",
                            objio::obj_info->imports[s->darrtd.mno], s->rectdname, s->darrtd.fprint);
                    break;
                case 4: /* to array */
                {
                    int i = 0;
                    fprintf(fp, "    lens=[");
                    while (i < s->darrtd.n_static_dim)
                    {
                        put_hex(s->darrtd.static_dim[i]);
                        ++i;
                        if (i < s->darrtd.n_static_dim)
                            fprintf(fp, ", ");
                    }

                    fprintf(fp, "]\n");
                    if (s->darrtd.element_form > 0)
                        fprintf(fp, "    basic type=%d\n", s->darrtd.element_form);
                    else
                    {
                        fprintf(fp, "    record td=%s->%s [fp=0%8.8XH]\n",
                                objio::obj_info->imports[s->darrtd.mno], s->rectdname, s->darrtd.element_form);
                    }
                    break;
                }

                default:
                    assert(false);
                    break;
                }
                break;

            case objio::t_array:
            {
                int i;
                const unsigned char *name = s->name;

                if (name == NULL) {
                    name = (const unsigned char *)"@none";
                }
                
                fprintf(fp, "ARRTD  name=%s, fprint=%8.8x ", name, s->fprint);
                fprintf(fp, "adr="); put_hex(s->adr);
                fprintf(fp, " nofDim=");
                put_hex(s->arrtd.n_dim);                
                fprintf(fp, "\n");
                
                if (s->arrtd.tag == '\1') /* array of simple type */
                    fprintf(fp, "    basic type=%d\n", s->arrtd.form);
                else if ( s->arrtd.tag == '\2') /* array of pointer */
                    fprintf(fp, "    pointer\n");
                else /* array of record */
                    fprintf(fp, "    record td=%s->%s [fp=0%8.8XH]\n",
                            objio::obj_info->imports[s->arrtd.mno], s->arrtdname, s->arrtd.fprint);;

                fprintf(fp, "    lens=[");
                i = 0;
                while (i < s->arrtd.n_dim)
                {
                    fprintf(fp, "%#x", s->arrtd.dim[i]);
                    ++i;
                    if (i < s->arrtd.n_dim) {
                        fprintf(fp, ", ");
                    }
                }

                fprintf(fp, "]\n");
                break;
            }
            }
        }
    }

    static void hex(const unsigned char *lab, int len, const unsigned char *buf)
    {
        int i, j, k;

        if (len != 0)
        {
            fprintf(fp, "%s\n", lab);
            k = 0;
            while (len > 0)
            {
                fprintf(fp, "%#4x: ", k);

                /* print hex part */
                for (i = 0, j = (len < 16) ? len : 16; i < j; ++i)
                    fprintf(fp, "%2x ", buf[k + i]);

                /* print char part */
                fprintf(fp, "  ");
                for (i = 0, j = (len < 16) ? len : 16; i < j; ++i)
                {
                    if ((buf[k + i] < ' ') || (buf[k + i] > 0x7f))
                        fprintf(fp, ".");
                    else
                        fprintf(fp, "%c", buf[k + i]);
                }
                k += j;
                len -= j;
                fprintf(fp, "\n");
            }
        }
    }

    static void consts(void)
    {
        unsigned char label[] = "Constants";
        hex(label, objio::obj_info->constx, objio::obj_info->constants);
    }

    static void type_descriptor_data(void)
    {
        unsigned char label[] = "Type Descriptors";
        hex(label, objio::obj_info->typedescx, objio::obj_info->typedescs);
    }

    static void uses_backwards(objio::use_info_desc_t *sym, int &n)
    {
        if (sym != NULL)
        {
            uses_backwards(sym->next, n);
            fprintf(fp, "  %d: ", n);
            ++n;

            switch (sym->kind)
            {
            case objio::u_const: /* Uconst */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_type: /* Utype */
                put_hex(sym->kind);
                fprintf(fp, "%s.%s 0%8.8XH\n", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                fprintf(fp, "     %s ", sym->type_name);
                put_hex(sym->type_adr);
                fprintf(fp, " 0%8.8XH", sym->type_fprint);
                break;

            case objio::u_var: /* Uvar */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_xproc: /* Uxproc, Uiproc */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_cproc: /* Ucproc */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_pbstruc: /* Upbstruc */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_pvstruc: /* Upvstruc */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_rectd: /* Urectd */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_arrtd: /* Uarrtd */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;

            case objio::u_darrtd: /* Udarrtd */
                fprintf(fp, "%s.%s 0%8.8XH", objio::obj_info->imports[sym->mno], sym->name, sym->fprint);
                break;
            }
            fprintf(fp, "\n");
        }
    }

    static void uses(void)
    {
        int n;
        fprintf(fp, "Uses\n");
        n = 0;
        uses_backwards(objio::obj_info->use, n);
    }

    static void helpers(void)
    {
        objio::helper_desc_t *hlp;
        objio::helper_loc_desc_t *loc;
        int i;

        fprintf(fp, "Compiler Helpers\n");
        hlp = objio::obj_info->helper;
        
        while (hlp != NULL)
        {
            fprintf(fp, "%s.%s\n", hlp->module, hlp->func);
            loc = hlp->loc;
            while (loc != NULL)
            {
                fprintf(fp, "  ");
                i = 0;
                while ((i < 8) && (loc != NULL))
                {
                    put_hex(loc->offs);
                    fprintf(fp, " ");
                    ++i;
                    loc = loc->next;
                }
                fprintf(fp, "\n");
            }
            hlp = hlp->next;
        }
    }

    static void get_seg_name(int seg, unsigned char *&name)
    {
        switch (seg)
        {
        case 0: name = (unsigned char *)"code"; break;
        case 1: name = (unsigned char *)"cnst"; break;
        case 2: name = (unsigned char *)"case"; break;
        case 3: name = (unsigned char *)"data"; break;
        case 4: name = (unsigned char *)"expt"; break;
        case 5: name = (unsigned char *)"cmds"; break;
        case 6: name = (unsigned char *)"tdsc"; break;
        case 7: name = (unsigned char *)"TD  "; break;
        default: name = (unsigned char *)"internal error"; break;
        }
    }

    static void fixups(void)
    {
        objio::fixup_desc_t *fix;
        int seg, i;
        unsigned char *segname;
        unsigned char *fixtype;
        
        fprintf(fp, "Fixups\n");
        i = 0;
        fix = objio::obj_info->fixup;
        while (fix != NULL)
        {
            seg = fix->segment; assert(0 <= seg && seg < 8); /* segment values; see LMCGL.MOD */
            
            get_seg_name(seg, segname);
            switch (fix->mode) {
            case 0:
            case 1:
                fixtype = (fix->mode == 0) ? (unsigned char *)"<ABS" : (unsigned char *)"REL";
                put_hex(i);
                fprintf(fp, ":  %s[", segname);
                put_hex(fix->offs);
                fprintf(fp, "] %s to ", fixtype);
                
                if (fix->target == '\1') /* fixup to a symbol */
                {
                    get_seg_name(fix->a0, segname);
                    fprintf(fp, "(sym) %s (import) %s ", segname,
                            objio::obj_info->imports[-fix->a1]);
                    put_hex(fix->a2);
                }
                else /* fixup to a label */
                {
                    get_seg_name(fix->a0, segname);
                    fprintf(fp, "(lab) %s ", segname);
                    put_hex(fix->a1);
                }
                break;

            case 2:
                fixtype = (unsigned char *)"BLK";
                put_hex(i);
                fprintf(fp, ":  %s[", segname);
                put_hex(fix->offs);
                fprintf(fp, "] %s record size = ", fixtype);
                put_hex(fix->a0);
                break;
            default:                                  assert(false);
            }

            fprintf(fp, "\n");
            ++i;
            fix = fix->next;
        }
    }

    static void code(objio::file_mode_t mode, objio::reference_info_desc_t *sym)
    {
        objio::reference_info_desc_t *locals;
        const char *kind;
        const char *form;

        if (sym != NULL)
        {
            code(mode, sym->next);
            fprintf(fp, "["); put_hex(sym->adr); fprintf(fp, ", "); put_hex(sym->adr + sym->len);
            fprintf(fp, ") %s\n", sym->name);
            locals = sym->locals;
            while (locals != NULL)
            {
                switch (locals->kind)
                {
                case objio::ri_var: kind = "VAR   "; break;
                case objio::ri_rectd: kind = "RECTD "; break;
                case objio::ri_arrtd: kind = "ARRTD "; break;;
                case objio::ri_darrtd: kind = "DARRTD"; break;
                case objio::ri_par: kind = "PAR   "; break;
                case objio::ri_varpar: kind = "VARPAR"; break;
                case objio::ri_proc: kind = "proc err"; break;
                default: kind = "??????"; break;
                }

                switch (locals->form)
                {
                case 1: /* bool  */ form = "BOOL "; break;
                case 2: /* byte  */ form = "BYTE "; break;
                case 3: /* char  */ form = "CHAR "; break;
                case 4: /* sint  */ form = "SINT "; break;
                case 5: /* int   */ form = "INT  "; break;
                case 6: /* lint  */ form = "LINT "; break;
                case 7: /* real  */ form = "REAL "; break;
                case 8: /* lreal */ form = "LREAL"; break;
                case 9: /* set   */ form = "SET  "; break;
                case 13: /* pointer */ form = "PTR  "; break;
                default: form = "STRING"; break;
                }

                fprintf(fp, "   [");
                put_hex(locals->adr);
                fprintf(fp, "] %s %s %s\n", kind, form, locals->name);
                locals = locals->next;
            }
            if (mode == objio::fm_x86) {
                x86::disassemble(fp, objio::obj_info->code, sym->adr, sym->len);
            } else {
                assert(mode == objio::fm_skl);
                skl::disassemble(fp, objio::obj_info->code, sym->adr, sym->len);

            }
            fprintf(fp, "\n");
        }
        else
            fprintf(fp, "\nReference Info\n");
    }

    void file(objio::file_mode_t mode)
    {
        header();
        commands();
        pointers();
        exports();
        privates();
        type_descriptors();
        consts();
        type_descriptor_data();
        uses();
        helpers();
        fixups();
        code(mode, objio::obj_info->refinfo);
    }
}
