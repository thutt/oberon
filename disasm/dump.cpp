/* Copyright (c) 2000, 2021-2023 Logic Magicians Software */
#include <assert.h>
#include <stdio.h>
#include "global.h"
#include "objio.h"
#include "dump.h"
#include "skl.h"

namespace dump
{
    static FILE *fp = stdout;
    static int n_uses;          // Number of elements in Uses block.


    static void
    put_hex(int i)
    {
        if (i < 0) {
            fprintf(fp, "-0%XH", -i);
        } else {
            fprintf(fp, "0%XH", i);
        }
    }

    static void
    put_dashes(void)
    {
        fprintf(fp, "-----");
    }

    static inline void
    put_hex_or_dashes(int i)
    {
        if (!::show_dashes) {
            put_hex(i);
        } else {
            put_dashes();
        }
    }


    static void
    header(void)
    {
        int i;

        fprintf(fp, "Module    : %s\n", objio::obj_info->module);
        fprintf(fp, "refsz     : %d (", objio::obj_info->refsize);
        put_hex(objio::obj_info->refsize);

        fprintf(fp, ")\nexp       : %d (",objio::obj_info->n_exp);
        put_hex(objio::obj_info->n_exp);

        fprintf(fp, ")\nprv       : %d (",objio::obj_info->n_prv);
        put_hex(objio::obj_info->n_prv);

        fprintf(fp, ")\ndesc      : %d (",objio::obj_info->n_desc);
        put_hex(objio::obj_info->n_desc);

        fprintf(fp, ")\ncom       : %d (",objio::obj_info->n_com);
        put_hex(objio::obj_info->n_com);

        fprintf(fp, ")\nptr       : %d (",objio::obj_info->n_ptr);
        put_hex(objio::obj_info->n_ptr);

        fprintf(fp, ")\nhelper    : %d (",objio::obj_info->n_helpers);
        put_hex(objio::obj_info->n_helpers);

        fprintf(fp, ")\nfixups    : %d (",objio::obj_info->n_fixups);
        put_hex(objio::obj_info->n_fixups);

        fprintf(fp, ")\npc        : %d (",objio::obj_info->pc);
        put_hex(objio::obj_info->pc);

        fprintf(fp, ")\ndsize     : %d (",objio::obj_info->dsize);
        put_hex(objio::obj_info->dsize);

        fprintf(fp, ")\nconstx    : %d (",objio::obj_info->constx);
        put_hex(objio::obj_info->constx);

        fprintf(fp, ")\ntypedescx : %d (",objio::obj_info->typedescx);
        put_hex(objio::obj_info->typedescx);

        fprintf(fp, ")\ncasex     : %d (",objio::obj_info->casex);
        put_hex(objio::obj_info->casex);

        fprintf(fp, ")\nexportx   : %d (",objio::obj_info->exportx);
        put_hex(objio::obj_info->exportx);

        fprintf(fp, ")\n");

        i = 0;
        while (objio::obj_info->imports[i] != NULL) {
            fprintf(fp, "import    : %-2d %s\n", i,
                    objio::obj_info->imports[i]);
            ++i;
        }
    }

    static void
    commands(void)
    {
        objio::command_desc_t *cmd;

        cmd = objio::obj_info->command;
        if (cmd != NULL) {
            fprintf(fp, "Commands\n");
            while (cmd != NULL) {
                fprintf(fp, "  %s [%d ", cmd->name, cmd->adr);
                put_hex(cmd->adr);
                fprintf(fp, "]\n");
                cmd = cmd->next;
            }
        }
    }

    static void
    pointers(void)
    {
        int i;
        if (objio::obj_info->n_ptr > 0) {
            fprintf(fp, "Pointers\n");

            i = 0;
            while (i < objio::obj_info->n_ptr) {
                fprintf(fp, "  ");
                put_hex(objio::obj_info->pointers[i]);
                fprintf(fp, "\n");
                ++i;
            }
        }
    }

    static void
    sym_info(objio::symbol_info_desc_t *s)
    {
        fprintf(fp, "  ");
        switch (s->kind) {
        case objio::e_const:
            fprintf(fp, "CONST  %s  pb: %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_type:
            fprintf(fp, "TYPE   %s  pb: %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_cproc:
            fprintf(fp, "CPROC  %s  pb: %8.8x\n", s->name, s->fprint);
            break;

        case objio::e_var:
            fprintf(fp, "VAR    %s  pb: %8.8x (adr: ", s->name, s->fprint);
            put_hex(s->voffset);
            fprintf(fp, ")\n");
            break;

        case objio::e_xproc:
            fprintf(fp, "PROC   %s  pb: %8.8x (entry: ", s->name, s->fprint);
            put_hex(s->pentry);
            fprintf(fp, ")\n");
            break;

        case objio::e_struc:
            fprintf(fp, "STRUC  %s (pb: %8.8x, pv: %8.8x)\n",
                    s->name, s->fprint, s->spvfprint);
            break;

        case objio::e_rectd:
            fprintf(fp, "RECTD  %s (pb: %8.8x, pv: %8.8x)\n",
                    s->name, s->fprint, s->spvfprint);
            break;

        case objio::e_darrtd:
            fprintf(fp, "DARRTD %s (pb: %8.8x, pv: %8.8x)\n",
                    s->name, s->fprint, s->spvfprint);
            break;

        case objio::e_arrtd:
            fprintf(fp, "ARRTD  %s (pb: %8.8x, pv: %8.8x)\n",
                    s->name, s->fprint, s->spvfprint);
            break;
        default:  assert(false);
        }
    }

    static void
    sym_info_backwards(int &i, objio::symbol_info_desc_t *s)
    {
        if (s != NULL) {
            sym_info_backwards(i, s->next);
            fprintf(fp, "%2.2d: ", i);
            ++i;
            sym_info(s);
        }
    }


    static void
    exports(void)
    {
        int i = 1;
        fprintf(fp, "Exports\n");
        sym_info_backwards(i, objio::obj_info->exports);
    }

    static void
    privates(void)
    {
        int i = 1;

        fprintf(fp, "Privates\n");
        sym_info_backwards(i, objio::obj_info->privates);
    }

    static void
    type_descriptors(void)
    {
        objio::symbol_info_desc_t *s = objio::obj_info->typedesc;
        fprintf(fp, "Type Descriptors");
        while (s != NULL) {
            fprintf(fp, "\n  ");

            switch (s->kind) {
            case objio::t_rec: {
                int i;
                if (s->name != NULL) {
                    fprintf(fp, "RECTD  name=%s", s->name);
                } else {
                    fprintf(fp, "RECTD fprint=%#8.8x", s->fprint);
                }

                fprintf(fp, " td adr="); put_hex(s->rectd.link);
                fprintf(fp, " recsize="); put_hex(s->rectd.recsize);
                fprintf(fp, " ");
                if (s->rectd.basemod == -1) {
                    if (s->ancestor != NULL) {
                        fprintf(fp, "ancestor=%s", s->ancestor);
                    } else {
                        fprintf(fp, "ancestor fp=%8.8x", s->rectd.ancestorfp);
                    }
                } else {
                    fprintf(fp, "ancestor module=%d", s->rectd.basemod);
                }

                fprintf(fp, "\n        "
                        "nofMeth=%d nofInhMeth=%d nofNewMeth=%d nofPtrs=%d\n",
                        s->rectd.n_meth, s->rectd.n_inhmeth, s->rectd.n_newmeth,
                        s->rectd.n_ptr);
                fprintf(fp, "        Methods\n");

                i = s->rectd.n_meth;
                while (i > 0) {
                    fprintf(fp, "          ");
                    put_hex(s->rectd.methinfo[i].methno);
                    fprintf(fp, " VMT[");
                    put_hex(-4 /* CGL.TBPOffset */ -
                            s->rectd.methinfo[i].methno * 4);
                    fprintf(fp, "]  ");
                    put_hex(s->rectd.methinfo[i].entry);
                    fprintf(fp, "\n");
                    --i;
                }

                fprintf(fp, "        Pointers\n");
                i = s->rectd.n_ptr;
                while (i > 0) {
                    fprintf(fp, "           ");
                    put_hex(s->rectd.ptroffs[i]);
                    fprintf(fp, "\n");
                    --i;
                }
                break;
            }

            case objio::t_darray:

                if (s->name != NULL) {
                    fprintf(fp, "DARTD  name=%s, fprint=%8.8x ",
                            s->name, s->fprint);
                } else {
                    fprintf(fp, "DARTD fprint=%8.8x ", s->fprint);
                }

                fprintf(fp, "adr="); put_hex(s->adr);
                fprintf(fp, " nofDim="); put_hex(s->darrtd.n_dim);
                fprintf(fp, "\n");

                switch (s->darrtd.form) {
                case 1: /* to basic type */
                    fprintf(fp, "    basic type=%d\n", s->darrtd.element_form);
                    break;
                case 2: /* to pointer */
                    fprintf(fp, "    pointer\n");
                    break;
                case 3: /* to record */
                    fprintf(fp, "    record td=%s->%s [fp=%8.8X]\n",
                            objio::obj_info->imports[s->darrtd.mno],
                            s->rectdname, s->darrtd.fprint);
                    break;
                case 4: { /* to array */
                    int i = 0;
                    fprintf(fp, "    lens=[");
                    while (i < s->darrtd.n_static_dim) {
                        put_hex(s->darrtd.static_dim[i]);
                        ++i;
                        if (i < s->darrtd.n_static_dim) {
                            fprintf(fp, ", ");
                        }
                    }

                    fprintf(fp, "]\n");
                    if (s->darrtd.element_form > 0) {
                        fprintf(fp, "    basic type=%d\n",
                                s->darrtd.element_form);
                    } else {
                        fprintf(fp, "    record td=%s->%s [fp=0%8.8XH]\n",
                                objio::obj_info->imports[s->darrtd.mno],
                                s->rectdname,
                                s->darrtd.element_form);
                    }
                    break;
                }

                default:
                    assert(false);
                    break;
                }
                break;

            case objio::t_array: {
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

                if (s->arrtd.tag == '\1') { /* array of simple type */
                    fprintf(fp, "    basic type=%d\n", s->arrtd.form);
                } else if ( s->arrtd.tag == '\2') { /* array of pointer */
                    fprintf(fp, "    pointer\n");
                } else { /* array of record */
                    fprintf(fp, "    record td=%s->%s [fp=0%8.8XH]\n",
                            objio::obj_info->imports[s->arrtd.mno],
                            s->arrtdname, s->arrtd.fprint);;
                }

                fprintf(fp, "    lens=[");
                i = 0;
                while (i < s->arrtd.n_dim) {
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
            s = s->next;
        }
    }

    static void
    hex(const unsigned char *lab, int len, const unsigned char *buf)
    {
        int i, j, k;

        if (len != 0) {
            fprintf(fp, "%s\n", lab);
            k = 0;
            while (len > 0) {
                fprintf(fp, "%#4x: ", k);

                /* print hex part */
                i = 0;
                j = (len < 16) ? len : 16;
                while (i < j) {
                    fprintf(fp, "%2x ", buf[k + i]);
                    ++i;
                }

                /* print char part */
                fprintf(fp, "  ");
                i = 0;
                j = (len < 16) ? len : 16;
                while (i < j) {
                    if ((buf[k + i] < ' ') || (buf[k + i] > 0x7f)) {
                        fprintf(fp, ".");
                    } else {
                        fprintf(fp, "%c", buf[k + i]);
                    }
                    ++i;
                }
                k += j;
                len -= j;
                fprintf(fp, "\n");
            }
        }
    }

    static void
    consts(void)
    {
        unsigned char label[] = "Constants";
        hex(label, objio::obj_info->constx, objio::obj_info->constants);
    }

    static void
    type_descriptor_data(void)
    {
        unsigned char label[] = "Type Descriptors";
        hex(label, objio::obj_info->typedescx, objio::obj_info->typedescs);
    }

    static void
    uses_backwards(objio::use_info_desc_t *sym, int &n)
    {
        if (sym != NULL) {
            uses_backwards(sym->next, n);
            fprintf(fp, "  %d: ", n);
            ++n;

            switch (sym->kind) {
            case objio::u_const: /* Uconst */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_type: /* Utype */
                fprintf(fp, "%s.%s 0%8.8XH\n",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                fprintf(fp, "     %s ", sym->type_name);
                put_hex(sym->type_adr);
                fprintf(fp, " 0%8.8XH", sym->type_fprint);
                break;

            case objio::u_var: /* Uvar */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_xproc: /* Uxproc, Uiproc */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_cproc: /* Ucproc */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_pbstruc: /* Upbstruc */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_pvstruc: /* Upvstruc */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_rectd: /* Urectd */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_arrtd: /* Uarrtd */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;

            case objio::u_darrtd: /* Udarrtd */
                fprintf(fp, "%s.%s 0%8.8XH",
                        objio::obj_info->imports[sym->mno],
                        sym->name, sym->fprint);
                break;
            }
            fprintf(fp, "\n");
        }
    }

    static void
    uses(void)
    {
        fprintf(fp, "Uses\n");
        n_uses = 0;
        uses_backwards(objio::obj_info->use, n_uses);
    }

    static void
    helpers(void)
    {
        objio::helper_desc_t *hlp;
        objio::helper_loc_desc_t *loc;
        int i;

        fprintf(fp, "Compiler Helpers\n");
        hlp = objio::obj_info->helper;

        while (hlp != NULL) {
            fprintf(fp, "%s.%s\n", hlp->module, hlp->func);
            loc = hlp->loc;
            while (loc != NULL) {
                fprintf(fp, "  ");
                i = 0;
                while ((i < 8) && (loc != NULL)) {
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

    static void
    get_seg_name(int seg, const char *&name)
    {
        switch (seg) {
        case 0: name = "code"; break;
        case 1: name = "cnst"; break;
        case 2: name = "case"; break;
        case 3: name = "data"; break;
        case 4: name = "expt"; break;
        case 5: name = "cmds"; break;
        case 6: name = "tdsc"; break;
        case 7: name = "TD  "; break;
        default: name = "internal error"; break;
        }
    }

    static unsigned char const *
    get_imported_symbol(int use_num)
    {
        objio::use_info_desc_t *use  = objio::obj_info->use;
        int                     i;

        assert(n_uses > 0);
        i = use_num;
        while (n_uses - 1 - i > 0) {
            use = use->next;
            ++i;
        }
        assert(i >= 0 && use != NULL);
        return use->name;
    }


    static void
    fixups(void)
    {
        objio::fixup_desc_t *fix;
        int seg, i;
        const char *segname;
        const char *fixtype;

        fprintf(fp, "Fixups\n");
        i = 0;
        fix = objio::obj_info->fixup;
        while (fix != NULL) {
            seg = fix->segment;
            assert(0 <= seg && seg < 8); /* segment values; see LMCGL.MOD */

            get_seg_name(seg, segname);
            switch (fix->mode) {
            case 0:
            case 1: {
                fixtype = (fix->mode == 0) ? "ABS" : "REL";
                put_hex(i);
                fprintf(fp, ":  %s[", segname);
                put_hex(fix->offs);
                fprintf(fp, "] %s to ", fixtype);

                if (fix->target == '\1') { /* fixup to a symbol */
                    get_seg_name(fix->a0, segname);
                    if (fix->a1 < 0) { /* Imported symbol? */
                        fprintf(fp, "(sym) %s %s.%s", segname,
                                objio::obj_info->imports[-fix->a1],
                                get_imported_symbol(fix->a2));
                    } else { /* Current module symbol. */
                        fprintf(fp, "(sym) %s[",
                                segname);
                        put_hex(fix->a2);
                        fprintf(fp, "]");
                    }
                } else { /* fixup to a label */
                    get_seg_name(fix->a0, segname);
                    fprintf(fp, "(lab) %s ", segname);
                    put_hex(fix->a1);
                }
                break;
            }

            case 2:
                fixtype = "BLK";
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

    static void
    code(objio::file_mode_t mode, objio::reference_info_desc_t *sym)
    {
        objio::reference_info_desc_t *locals;
        const char *kind;
        const char *form;

        if (sym != NULL) {
            code(mode, sym->next);
            fprintf(fp, "[");
            put_hex_or_dashes(sym->adr);
            fprintf(fp, ", ");
            put_hex_or_dashes(sym->adr + sym->len);
            fprintf(fp, ") %s\n", sym->name);
            locals = sym->locals;
            while (locals != NULL) {
                switch (locals->kind) {
                case objio::ri_var: kind = "VAR   "; break;
                case objio::ri_rectd: kind = "RECTD "; break;
                case objio::ri_arrtd: kind = "ARRTD "; break;;
                case objio::ri_darrtd: kind = "DARRTD"; break;
                case objio::ri_par: kind = "PAR   "; break;
                case objio::ri_varpar: kind = "VARPAR"; break;
                case objio::ri_proc: kind = "proc err"; break;
                default: kind = "??????"; break;
                }

                switch (locals->form) {
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

            assert(mode == objio::fm_skl);
            skl::disassemble(fp, objio::obj_info->code, sym->adr, sym->len);
            fprintf(fp, "\n");
        } else {
            fprintf(fp, "\nReference Info\n");
        }
    }

    void
    file(objio::file_mode_t mode)
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
