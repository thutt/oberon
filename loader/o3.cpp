/* Copyright (c) 2000, 2021, 2022 Logic Magicians Software */
#include <string.h>

#include "fileutils.h"
#include "heap.h"
#include "objinfo.h"
#include "o3.h"
#include "md.h"

namespace O3
{
    /* Maximum length of strings which is supported by the bootstrap
     * loader.  Normally a fully dynamic string should be supported
     * (and it is in the system proper), but for the bootstrap system,
     * we can cheat by having a hard upper-bound.
     */
    const int NAME_LEN = 32;
    typedef char string_t[NAME_LEN];

    /* The address of these symbols in Kernel are pushed onto the
     * stack in specific cicrumstances to ensure the Virtual Machine
     * Engine will gracefully exit to the host OS at the right times.
     */
    bootstrap_symbols_t bootstrap_symbol[] = {
        { "BootstrapModuleInit", 0 },
    };

    /* Items in Kernel.Mod which have type descriptors.  These all
     * need to be located and assigned to dynamically allocated
     * records of the proper type.
     */
    enum td_names_t
    {
        /* do not add anything prior to td_module */
        td_module,              /* Kernel.Module */
        td_vmsvc,               /* Kernel.VMServiceDesc */
        td_tdescs,              /* Kernel.Module.type descriptor addresses */
        td_exports,             /* Kernel.Module.exports */
        td_privates,            /* Kernel.Module.privates */
        td_commands,            /* Kernel.Module.commands */
        td_pointers,            /* Kernel.Module.pointers */
        td_imports,             /* Kernel.Module.imports */
        td_jumps,               /* Kernel.Module.jumps */
        td_data,                /* Kernel.Module.data */
        td_tddata,              /* Kernel.Module.td_data */
        td_code,                /* Kernel.Module.code */
        td_refs,                /* Kernel.Module.refs */
        td_name,                /* Kernel.Name */
        n_td_names
    };

    /* Type descriptor, in-memory layouts used for validation of
     * `Kernel' type descriptor fixups
     */
    struct td_record {
        md::OFLAGS flags;
        md::OADDR  extension_table;
        md::int32  extension_level;
        md::int32  record_size;
        md::int32  block_size;
        md::int32  n_pointers;
        md::OADDR  record_name; /* (const char *) POINTER TO ARRAY OF CHAR */
        md::OADDR  module_descriptor;
        md::OADDR  finalization;
        md::OADDR  pointer_offset; // variably-sized array: pointer_offset[n_pointers + 1]
    };


    struct td_simple_array {
        md::OFLAGS flags;
        md::int32  element_form;
        md::int32  n_dimensions;
    };


    struct td_record_array {
        md::OFLAGS flags;
        md::OADDR  td;          /* (td_record *) */
        md::int32  n_dimensions;
    };


    struct td_record_pointer_array {
        md::OFLAGS flags;
        md::uint32 reserved;
        md::int32  n_dimensions;
    };


    /* Type descriptor validation data
     * (Not provided to Oberon)
     */
    struct typedesc_info_geometry_t {
        md::OFLAGS flags;
        typedesc_info_geometry_t(md::OFLAGS f) : flags(f) { }
    };

    struct typedesc_geometry_record_t : typedesc_info_geometry_t
    {
        int         extension_level;
        int         record_size_in_bytes;
        int         n_pointers;
        const char *record_name;
        typedesc_geometry_record_t(md::OFLAGS  f,
                                   int         ext,
                                   int         size,
                                   int         n_ptr,
                                   const char *name) :
            typedesc_info_geometry_t(f),
            extension_level(ext),
            record_size_in_bytes(size),
            n_pointers(n_ptr),
            record_name(name) { }
    };

    struct typedesc_geometry_simple_array_t : typedesc_info_geometry_t
    {
        int element_form;
        int n_dimensions;
        typedesc_geometry_simple_array_t(md::OFLAGS f,
                                         int        form,
                                         int        n_dim) :
            typedesc_info_geometry_t(f),
            element_form(form),
            n_dimensions(n_dim) { }
    };

    struct typedesc_geometry_record_array_t : typedesc_info_geometry_t
    {
        td_record  *td_physcial_address;
        int         n_dimensions;
        const char *record_name;
        typedesc_geometry_record_array_t(md::OFLAGS f,
                                         int n_dim,
                                         const char *name) :
            typedesc_info_geometry_t(f),
            n_dimensions(n_dim),
            record_name(name) { }
    };

    struct typedesc_geometry_record_pointer_array_t : typedesc_info_geometry_t
    {
        int n_dimensions;
        typedesc_geometry_record_pointer_array_t(md::OFLAGS f, int n_dim) :
            typedesc_info_geometry_t(f),
            n_dimensions(n_dim)
            {
            }
    };

    /* typedesc_info_t is used to store type descriptor information
     * for bootstrapping fixups.
     *
     * Not exposed to Oberon.
     */
    struct typedesc_info_t
    {
        md::OADDR                 adr;
        string_t                  name; /* name as it appears in the export table */
        bool                      (*validity_check)(md::uint32 physical_address,
                                                    typedesc_info_geometry_t &geometry);
        typedesc_info_geometry_t  &geometry;
    };

    struct object_module_str_t
    {
        object_module_str_t *next;
        long i;
        string_t str;
        object_module_str_t(char *s, long index) : next(NULL), i(index)
            {
                strncpy(str, s, NAME_LEN);
                str[NAME_LEN - 1] = '\0';
            }
        ~object_module_str_t(void) { }
    };

    struct objf_header_t {
        md::int32 refSize;
        md::int32 n_exports;
        md::int32 nofPrv;
        md::int32 nofDesc;
        md::int32 nofCom;
        md::int32 nofPtr;
        md::int32 codeSize;
        md::int32 dataSize;     /* header info */
        md::int32 constSize;
        md::int32 typedescSize;
        md::int32 caseSize;
        md::int32 exportSize;
        md::int32 nofImports;
        md::int32 nofHelpers;
        md::int32 n_fixups;     /* header info */
        string_t  name;
    };

    struct uses_list_t {        /* Not exposed to Oberon */
        name_t       name;
        uses_list_t *next;
    };

    /* Module initialization code procedure signature */
    typedef void (*init_code_t)(void);

    /* type descriptor validation records */
    typedesc_geometry_record_t tdesc_moduledesc =
        typedesc_geometry_record_t(0x40000000, 0,
                                   0x40, 0x0d,
                                   "ModuleDesc");
    typedesc_geometry_record_t tdesc_vmservicedesc = typedesc_geometry_record_t(0x40000000, 0,
                                                                                4, 0,
                                                                                "VMServiceDesc");
    typedesc_geometry_simple_array_t
    tdesc_tdescs = typedesc_geometry_simple_array_t(0x40000001, 6, 1);
    typedesc_geometry_record_array_t tdesc_exports         = typedesc_geometry_record_array_t(0x40000003, 1,
                                                                                              "Export");
    typedesc_geometry_record_array_t tdesc_privates        = typedesc_geometry_record_array_t(0x40000003, 1,
                                                                                              "Export");
    typedesc_geometry_record_array_t tdesc_commands        = typedesc_geometry_record_array_t(0x40000003, 1,
                                                                                              "Cmd");
    typedesc_geometry_simple_array_t tdesc_pointers        = typedesc_geometry_simple_array_t(0x40000001, 6, 1);
    typedesc_geometry_record_pointer_array_t tdesc_imports = typedesc_geometry_record_pointer_array_t(0x40000002, 1);
    typedesc_geometry_simple_array_t tdesc_jumps           = typedesc_geometry_simple_array_t(0x40000001, 2, 1);
    typedesc_geometry_simple_array_t tdesc_data            = typedesc_geometry_simple_array_t(0x40000001, 2, 1);
    typedesc_geometry_simple_array_t tdesc_tddata          = typedesc_geometry_simple_array_t(0x40000001, 2, 1);
    typedesc_geometry_simple_array_t tdesc_code            = typedesc_geometry_simple_array_t(0x40000001, 2, 1);
    typedesc_geometry_simple_array_t tdesc_refs            = typedesc_geometry_simple_array_t(0x40000001, 3, 1);
    typedesc_geometry_simple_array_t tdesc_name            = typedesc_geometry_simple_array_t(0x40000001, 3, 1);

    /* Use kerneltd.mod to determine the relationship between the type
     * descriptor name and the variable in the Kernel module.
     *
     * MODULE KernelTD;
     *   IMPORT Kernel;
     *
     *   (* This procedure is used to find out what type descriptors
     *      are associated with which field of the Module data structure *)
     *   PROCEDURE TDAllocation;
     *     VAR m : Kernel.Module; c : Kernel.Cmd; e : Kernel.Export;
     *   BEGIN
     *     NEW(m);
     *     NEW(m.tdescs, 1);
     *     NEW(m.exports, 2);
     *     NEW(m.privates, 3);
     *     NEW(m.commands, 4);
     *     NEW(m.pointers, 5);
     *     NEW(m.imports, 6);
     *     NEW(m.jumps, 7);
     *     NEW(m.data, 8);
     *     NEW(m.tddata, 9);
     *     NEW(m.code, 10);
     *     NEW(m.refs, 11);
     *     NEW(m.name, 12);
     *
     *     NEW(c.name, 13);
     *     NEW(e.name, 14);
     *   END TDAllocation;
     * END KernelTD.
     */

    bool validate_record_td(md::uint32 physical_address,
                            typedesc_info_geometry_t &geometry);
    bool validate_simple_array_td(md::uint32 physical_address,
                                  typedesc_info_geometry_t &geometry);
    bool validate_record_array_td(md::uint32 physical_address,
                                  typedesc_info_geometry_t &geometry);
    bool validate_record_pointer_array_td(md::uint32 physical_address,
                                          typedesc_info_geometry_t &geometry);

    /* These type descriptors are found by modifying
     * LMSTH.NewTypeDesc() to print 'type.sym.name^' and 'descName^',
     * and then looking at Kernel.ModuleDesc and associating the type
     * descriptors for each field in the table below.
     */
    static typedesc_info_t td_info[n_td_names] = { /* Not visible to Oberon. */
        { 0, ".ModuleDesc", validate_record_td, tdesc_moduledesc }, /* record */
        { 0, ".VMServiceDesc", validate_record_td, tdesc_vmservicedesc }, /* record */
        { 0, ".td_1",       validate_simple_array_td, tdesc_tdescs }, /* array of simple */
        { 0, ".td_7",       validate_record_array_td, tdesc_exports }, /* array of record */
        { 0, ".td_7",       validate_record_array_td, tdesc_privates }, /* array of record */
        { 0, ".td_6",       validate_record_array_td, tdesc_commands }, /* array of record */
        { 0, ".td_0",       validate_simple_array_td, tdesc_pointers }, /* array of simple */
        { 0, ".td_2",       validate_record_pointer_array_td, tdesc_imports }, /* array of record */
        { 0, ".td_4",       validate_simple_array_td, tdesc_jumps }, /* array of simple */
        { 0, ".td_4",       validate_simple_array_td, tdesc_data }, /* array of simple */
        { 0, ".td_4",       validate_simple_array_td, tdesc_tddata }, /* array of simple */
        { 0, ".td_4",       validate_simple_array_td, tdesc_code }, /* array of simple */
        { 0, ".td_5",       validate_simple_array_td, tdesc_refs }, /* array of simple */
        { 0, ".td_3",       validate_simple_array_td, tdesc_name }, /* array of simple */
    };

    /* uses_info: normally this is kept locally to the load() function;
     *
     * Oberon's block structure takes care of scoping issues with
     * recursive loading.  However, since this is a bootstrap loader,
     * it is guaranteed that no recursive loading will take place; the
     * modules are loaded in an order that prevents any recursive
     * invocation.
     */
    static uses_info_t  uses_info[151];
    static uses_list_t *uses_list;

    md::OADDR module_list;      /* Oberon: module_t * */
    const int sizeof_module_t = 0x40;
    md::int32 n_inited        = 0; // number of modules initialized
    md::int32 n_loaded        = 0; // number of modules actually loaded

    static char                *current_module_name    = NULL;
    static object_module_str_t *current_module_strings = NULL;

    static void
    indent(int n)
    {
        while (n-- > 0)
            dialog::print(" ");
    }


    static void
    print_header(const char *header, md::uint32 p, int len)
    {
        dialog::print("%15s: addr=%#x  len=%#x\n", header, p, len);
    }


    static void
    print_simple_elem_array_info(const char *header, md::uint32 a)
    {
        int len = 0;

        if (a != 0) {
            len = heap::simple_elem_array_len(heap::host_address(a));
        }
        print_header(header, a, len);
    }


    static void
    print_pointer_elem_array_info(const char *header, md::uint32 a)
    {
        int len = 0;

        if (a != 0) {
            len = heap::pointer_elem_array_len(heap::host_address(a));
        }
        print_header(header, a, len);
    }


    static void
    print_record_elem_array_info(const char *header, md::uint32 a)
    {
        int len = 0;

        if (a != 0) {
            len = heap::record_elem_array_len(heap::host_address(a));
        }
        print_header(header, a, len);
    }


    void
    dump_module(module_t *module)
    {
        if (config::options & config::opt_progress)
        {
            dialog::print("module: %s, next: %p, refcnt: %d\n",
                          heap::host_address(module->name),
                          heap::host_address(module->next),
                          module->refcnt);

            indent(2); print_record_elem_array_info("Exports", module->exports);
            indent(2); print_record_elem_array_info("Privates", module->privates);
            indent(2); print_simple_elem_array_info("Type Desc", module->tdescs);
            indent(2); print_record_elem_array_info("Commands", module->commands);
            indent(2); print_simple_elem_array_info("Pointers", module->pointers);
            indent(2); print_pointer_elem_array_info("Imports", module->imports);
            indent(2); print_simple_elem_array_info("Case Table", module->jumps);
            indent(2); print_simple_elem_array_info("Data", module->data);
            indent(2); dialog::print("%15s: %#x\n", "static base", module->sb);
            indent(2); print_simple_elem_array_info("Code", module->code);
            indent(2); print_simple_elem_array_info("td data", module->tddata);
            indent(2); print_simple_elem_array_info("Reference Info", module->refs);
        }
    }


    bool
    validate_record_td(md::uint32                adr,
                       typedesc_info_geometry_t &geometry)
    {
        td_record *td = reinterpret_cast<td_record *>(heap::host_address(adr));
        typedesc_geometry_record_t &g = static_cast<typedesc_geometry_record_t &>(geometry);

        int last_index;

        if (td != NULL) {
            if (td->extension_level != g.extension_level) {
                return false;
            }
            if (td->record_size != g.record_size_in_bytes) {
                return false;
            }
            if (td->n_pointers != g.n_pointers) {
                return false;
            }
            if (strcmp(reinterpret_cast<const char *>(heap::host_address(td->record_name)),
                       g.record_name) != 0) {
                return false;
            }

            if (td->n_pointers > 0) {
                /* Validate end of pointer table sentinel value.
                 *
                 * The last entry in the table of pointers generated
                 * in the type descriptor is a sentinel value that is
                 * set to sum to zero with the calculation employed
                 * below.  The pointer table begins directly at
                 * 'pointer_offset' and continues for 'td->n_pointers'
                 * elements.
                 */
                md::int32 *tbl = reinterpret_cast<md::int32 *>(&td->pointer_offset);
                md::int32 sentinel;

                last_index = 9 + (td->n_pointers /
                                  static_cast<int>(sizeof(md::uint32)));
                sentinel = tbl[last_index + 1];
                if (sentinel +
                    (9 + td->n_pointers) * static_cast<int>(sizeof(md::uint32)) != 0) {
                    return false;
                }
            }
            return true;
        }
        else {
            return false;
        }
    }


    bool
    validate_simple_array_td(md::uint32                adr,
                             typedesc_info_geometry_t &geometry)
    {
        td_simple_array *td = reinterpret_cast<td_simple_array *>(heap::host_address(adr));
        typedesc_geometry_simple_array_t &g = static_cast<typedesc_geometry_simple_array_t&>(geometry);

        dialog::diagnostic("simple td information: %#x %#x %#x\n", td->flags,
                           td->element_form, td->n_dimensions);
        return (td != NULL &&
                td->flags == g.flags &&
                td->element_form == g.element_form &&
                td->n_dimensions == g.n_dimensions) ? true : false;
    }


    bool
    validate_record_array_td(md::uint32                adr,
                             typedesc_info_geometry_t &geometry)
    {
        td_record_array *td = reinterpret_cast<td_record_array *>(heap::host_address(adr));
        typedesc_geometry_record_array_t &g = static_cast<typedesc_geometry_record_array_t&>(geometry);
        md::HADDR   rtdp   = heap::host_address(td->td);
        td_record  *rtd    = reinterpret_cast<td_record *>(rtdp);
        md::HADDR   uint8p = heap::host_address(rtd->record_name);
        const char *name   = reinterpret_cast<const char *>(uint8p);


        dialog::diagnostic("record array information: %#x %#x `%s'\n",
                           td->flags,
                           td->n_dimensions,
                           name);
        return (td != NULL &&
                td->flags == g.flags &&
                td->n_dimensions == g.n_dimensions &&
                strcmp(name, g.record_name) == 0) ? true : false;
    }


    bool
    validate_record_pointer_array_td(md::uint32                adr,
                                     typedesc_info_geometry_t &geometry)
    {
        td_record_pointer_array *td =
            reinterpret_cast<td_record_pointer_array *>(heap::host_address(adr));
        typedesc_geometry_record_pointer_array_t &g =
            static_cast<typedesc_geometry_record_pointer_array_t&>(geometry);

        dialog::diagnostic("record array information: %#x %#x\n",
                           td->flags, td->n_dimensions);
        return (td != NULL &&
                td->flags == g.flags &&
                td->n_dimensions == g.n_dimensions) ? true : false;
    }


    static export_t *
    get_module_export(const module_t *module, int n)
    {
        md::HADDR       expp    = heap::host_address(module->exports);
        export_array_t *exports = reinterpret_cast<export_array_t *>(expp);

        return &exports[n];
    }


    static const export_t *
    get_module_private(const module_t *module, int n)
    {
        md::HADDR       prip = heap::host_address(module->privates);
        export_array_t *pri  = reinterpret_cast<export_array_t *>(prip);

        return &pri[n];
    }


    static const char *
    get_export_name(const export_t *exp)
    {
        return reinterpret_cast<const char *>(heap::host_address(exp->name));
    }


    static cmd_t *
    get_module_command(const module_t *module, int n)
    {
        md::HADDR     cmdp = heap::host_address(module->commands);
        cmds_array_t *cmds = reinterpret_cast<cmds_array_t *>(cmdp);

        return &cmds[n];
    }

    void
    get_kernel_td_info(module_t *module)
    {
        /* This function locates the kernel type descriptors in
         * 'Kernel.Obj' memory and assigns their physical addresses to
         * their associated array for use in bootstrap fixups
         * processing.  This information is only used by the bootstrap
         * loader to handle these special fixups in the Kerl module.
         * They are special because the full loader (Modules) and the
         * full heap are not yet present in memory, so we've got to
         * dope the first blocks on the heap so that the GC can
         * properly work once bootstrapped.
         *
         * It takes a linear search approach for each of the entries
         * in the array; this is slow, but it only occurs during
         * bootstrapping and it simplifies the implementation
         * considerably: considering it's only a few (13 entries as of
         * 2000.06.19) entries, a linear search will not hurt.
         */
        int len = heap::record_elem_array_len(heap::host_address(module->exports));

        dialog::diagnostic("Searching for Kernel Type Descriptors:\n");

        for (size_t f = 0; f < sizeof(td_info) / sizeof(td_info[0]); ++f) {
            dialog::diagnostic("'%s' ", td_info[f].name);
            for (int i = 0; i < len; ++i) {
                const export_t *exp = get_module_export(module, i);

                if (strcmp(td_info[f].name, get_export_name(exp)) == 0) {
                    if (td_info[f].validity_check != NULL &&
                        !td_info[f].validity_check(exp->adr,
                                                   td_info[f].geometry)) {
                        dialog::fatal("type descriptor misidentified (td='%s')\n",
                                      td_info[f].name);
                    }

                    td_info[f].adr = exp->adr;
                    dialog::diagnostic("[var at %#x (td at %#x)] %s\n",
                                       exp->adr,
                                       td_info[f].adr,
                                       td_info[f].name);
                    break;
                }
            }
        }

        /* sanity check: ensure that all type descriptors were actually found */
        len = heap::record_elem_array_len(heap::host_address(module->exports));
        for (int i = 0; i < static_cast<int>(sizeof(td_info) /
                                             sizeof(td_info[0])); ++i) {
            dialog::diagnostic("Kernel.%s: TD address: %#x\n",
                               td_info[i].name, td_info[i].adr);
            if (td_info[i].adr == 0) {
                dialog::fatal("type descriptor for Kernel.%s not found\n",
                              td_info[i].name);
            } else if (MOD(static_cast<md::int32>(td_info[i].adr),
                           heap::allocation_block_size) != 0) {
                dialog::fatal("Type descriptor Kernel.%s not aligned (%#x)\n",
                              td_info[i].name, td_info[i].adr);
            }
        }
    }


    static md::uint32
    get_function_address(module_t *module, const char *function)
    {
        /* pre : module != NULL && defined(*module)
         * pre : ASCIIZ(function)
         * post: result = NULL -> function not found
         * post: result != NULL -> function found & defined(*result)
         */
        if (module->exports != 0) {
            int i = 0;
            while (i < heap::record_elem_array_len(heap::host_address(module->exports))) {
                const export_t *exp = get_module_export(module, i);
                if (strcmp(function, get_export_name(exp)) == 0) {
                    return exp->adr;
                }
                ++i;
            }
        }
        return 0;
    }


    void
    fixup_type_descriptors(void)
    {
        module_t *m = reinterpret_cast<module_t *>(heap::host_address(module_list));
        while (m != NULL) {
            dialog::diagnostic("Fixup type descriptors for %s\n",
                               heap::host_address(m->name));
            heap::fixup_td(reinterpret_cast<md::HADDR>(m), "mod",
                           heap::host_address(td_info[td_module].adr),   false);
            heap::fixup_td(heap::host_address(m->tdescs), "tdsc",
                           heap::host_address(td_info[td_tdescs].adr),   true);
            heap::fixup_td(heap::host_address(m->exports), "exp",
                           heap::host_address(td_info[td_exports].adr),  true);
            heap::fixup_td(heap::host_address(m->privates), "prv",
                           heap::host_address(td_info[td_privates].adr), true);
            heap::fixup_td(heap::host_address(m->commands), "cmd",
                           heap::host_address(td_info[td_commands].adr), true);
            heap::fixup_td(heap::host_address(m->pointers), "ptr",
                           heap::host_address(td_info[td_pointers].adr), true);
            heap::fixup_td(heap::host_address(m->imports), "imp",
                           heap::host_address(td_info[td_imports].adr),  true);
            heap::fixup_td(heap::host_address(m->jumps), "jmp",
                           heap::host_address(td_info[td_jumps].adr),    true);
            heap::fixup_td(heap::host_address(m->data), "dat",
                           heap::host_address(td_info[td_data].adr),     true);
            heap::fixup_td(heap::host_address(m->tddata), "tdd",
                           heap::host_address(td_info[td_tddata].adr),   true);
            heap::fixup_td(heap::host_address(m->code), "cod",
                           heap::host_address(td_info[td_code].adr),     true);
            heap::fixup_td(heap::host_address(m->refs), "ref",
                           heap::host_address(td_info[td_refs].adr),     true);
            heap::fixup_td(heap::host_address(m->name), "nam",
                           heap::host_address(td_info[td_name].adr),     true);

            if (m->commands != 0) {
                int i   = 0;
                int len = heap::record_elem_array_len(heap::host_address(m->commands));

                while (i < len) {
                    const cmd_t *cmd = get_module_command(m, i);
                    heap::fixup_td(heap::host_address(cmd->name), "cmd ",
                                   heap::host_address(td_info[td_name].adr), true);
                    ++i;
                }
            }

            if (m->exports != 0) {
                int i   = 0;
                int len = heap::record_elem_array_len(heap::host_address(m->exports));

                while (i < len) {
                    const export_t *exp = get_module_export(m, i);
                    heap::fixup_td(heap::host_address(exp->name), "ex2 ",
                                   heap::host_address(td_info[td_name].adr), true);
                    ++i;
                }
            }

            if (m->privates != 0) {
                int i   = 0;
                int len = heap::record_elem_array_len(heap::host_address(m->privates));

                while (i < len) {
                    const export_t *pri = get_module_private(m, i);
                    heap::fixup_td(heap::host_address(pri->name), "pr2 ",
                                   heap::host_address(td_info[td_name].adr), true);
                    ++i;
                }
            }
            m = reinterpret_cast<module_t *>(heap::host_address(m->next));
        }
    }


    void
    fixup_uses_type_descriptors(void)
    {
        /* fixes up all 'uses' records */
        uses_list_t *prev;

        while (uses_list != NULL) {
            md::HADDR name = reinterpret_cast<md::HADDR>(uses_list->name);

            prev = uses_list;
            heap::fixup_td(name, "use",
                           heap::host_address(td_info[td_name].adr), true);
            uses_list = uses_list->next;
            delete prev;
        }
    }


    static md::HADDR
    data_base(module_t *module)
    {
        md::HADDR hp = heap::host_address(module->data);
        return &hp[module->sb];
    }


    static void
    read_bytes(FILE *fp, unsigned char *buf, int n_bytes)
    {
        size_t read = fread(buf, sizeof(buf[0]),
                            static_cast<size_t>(n_bytes), fp);
        if (static_cast<int>(read) != n_bytes) {
            dialog::fatal("expected to read %#x bytes but read only %#x");
        }
    }


    static void
    read_ch(FILE *fp, char &ch)
    {
        size_t r = fread(&ch, sizeof(ch), 1, fp);
        if (r != 1) {
            dialog::not_implemented(__func__);
        }
    }


    static void
    read_lint(FILE *fp, md::int32 &x)
    {
        size_t r = fread(&x, sizeof(x), 1, fp);
        if (r != 1) {
            dialog::not_implemented(__func__);
        }
    }


    static void
    read_tag(FILE *fp, char tag)
    {
        char ch;
        read_ch(fp, ch);

        if (ch != tag) {
            dialog::fatal("Corrupt Obj File: %s [%XX not found at %s]\n",
                          current_module_name, tag, ftell(fp) - 1);
        }
    }


    static void
    find_str(long index, string_t &s)
    {
        object_module_str_t *o;
        o = current_module_strings;

        while (o != NULL && o->i != -index) {
            dialog::diagnostic("index '%d' o->i '%d' o->str '%s'\n",
                               index, o->i, o->str);
            o = o->next;
        }

        assert(o != NULL);
        strncpy(s, o->str, NAME_LEN);
        s[NAME_LEN - 1] = '\0';
    }


    static void
    new_object_module_str(long index, string_t &str)
    {
        object_module_str_t *o;
        o = new object_module_str_t(str, index);
        o->next = current_module_strings;
        current_module_strings = o;
    }


    static void
    read_num(FILE *fp, int &res)
    {
        char rCH;
        int  n;
        long y;
        long x;

        n = 0;
        y = 0;
        read_ch(fp, rCH);

        while (static_cast<unsigned char>(rCH) >= 0x80) {
            y += (static_cast<unsigned char>(rCH) - 128) << n;
            n += 7;
            read_ch(fp, rCH);
        }

        if (n - 25 < 0) {
            x = (rCH << 25) >> (25 - n);
        } else {
            x = (rCH << 25) << (n - 25);
        }
        x += y;
        res = static_cast<int>(x);
    }


    static void
    read_raw_str(FILE *fp, string_t x)
    {
        int len;

        read_num(fp, len); /* length of the string */

        /* The bootstrap loader does not support fully dynamic string
         * lengths.  Since the bootstrap modules are easily controlled
         * in source form, it is not necessary to go to the extra
         * expense to ensure that all string lengths can be read in
         * correctly.  Modules.Mod does it the complete, correct, way.
         */
        assert(len < NAME_LEN);
        memset(x, '\0', NAME_LEN);
        for (int i = 0; i < len; ++i) {
            read_ch(fp, x[i]);
        }
    }


    static void
    read_str(FILE *fp, string_t &x)
    {
        int index;

        read_num(fp, index);
        if (index < 0) {
            find_str(index, x);
        } else {
            read_raw_str(fp, x);
            new_object_module_str(index, x);
        }
    }


    static void
    add_module(module_t *m)
    {
        module_t  *l  = reinterpret_cast<module_t *>(heap::host_address(module_list));
        md::HADDR  mp = reinterpret_cast<md::HADDR>(m);

        if (l != NULL) {
            while (l->next != 0) {
                l = reinterpret_cast<module_t *>(heap::host_address(l->next));
            }
            l->next = heap::heap_address(mp);
        } else {
            module_list = heap::heap_address(mp);
        }
        m->next = 0;
    }


    static module_t *
    find_module(name_t name)
    {
        module_t *m = reinterpret_cast<module_t *>(heap::host_address(module_list));

        while (m != NULL) {
            const char *mname = reinterpret_cast<const char *>(heap::host_address(m->name));
            if (strcmp(mname, name) == 0) {
                break;
            }
            m = reinterpret_cast<module_t *>(heap::host_address(m->next));
        }
        return m;
    }


    static md::uint32
    new_string(const char *str)
    {
        md::HADDR  n;
        char      *name;

        /* pre : ASCIIZ(s)
         * post: name # NULL & ASCIIZ(name)
         *
         * Allocates a new dynamic array in the Oberon heap and
         * assigns 'str' to it.
         */

        /* bootstrap loader does not handle dynamic string lengths */
        assert(strlen(str) + 1 <= static_cast<size_t>(NAME_LEN));

        /* number of elements includes 0X */
        n = heap::new_simple_elem_array(static_cast<int>(strlen(str) + 1),
                                        static_cast<int>(sizeof(str[0])),
                                        heap::host_address(td_info[td_refs].adr));
        name = reinterpret_cast<char *>(n);
        strcpy(name, str);
        return heap::heap_address(reinterpret_cast<md::HADDR>(name));
    }


    static md::uint32
    new_exports(int n_exports, int record_size)
    {
        md::HADDR exp = heap::new_record_elem_array(n_exports,
                                                    record_size,
                                                    heap::host_address(td_info[td_exports].adr));

        return heap::heap_address(exp);
    }


    static md::uint32
    new_privates(int n_privates, int record_size)
    {
        md::HADDR pri = heap::new_record_elem_array(n_privates,
                                                    record_size,
                                                    heap::host_address(td_info[td_privates].adr));
        return heap::heap_address(pri);
    }


    static md::uint32
    new_typedescs(int n_typedesc, int elem_size)
    {
        /* Allocate an array of memory to hold pointers to type
         * descriptors for this module. */
        md::HADDR td = heap::new_simple_elem_array(n_typedesc,
                                                   elem_size,
                                                   heap::host_address(td_info[td_tdescs].adr));
        dialog::diagnostic("%s: %d new TDesc; %d bytes; address %p\n",
                           __func__, n_typedesc, n_typedesc * elem_size, td);
        return heap::heap_address(td);
    }


    static md::uint32
    new_commands(int n_cmd, int record_size)
    {
        md::HADDR cmd = heap::new_record_elem_array(n_cmd,
                                                    record_size,
                                                    heap::host_address(td_info[td_commands].adr));
        assert(sizeof(cmds_array_t) == 8);
        return heap::heap_address(cmd);

    }


    static md::uint32
    new_pointers(int n_pointers, int elem_size)
    {
        md::HADDR ptr = heap::new_simple_elem_array(n_pointers,
                                                    elem_size,
                                                    heap::host_address(td_info[td_pointers].adr));
        return heap::heap_address(ptr);
    }


    static md::uint32
    new_imports(int n_imports, int elem_size)
    {
        md::HADDR imp = heap::new_pointer_elem_array(n_imports,
                                                     elem_size,
                                                     heap::host_address(td_info[td_imports].adr));
        return heap::heap_address(imp);
    }


    static md::uint32
    new_jumps(int n_jumps, int elem_size)
    {
        md::HADDR jmps = heap::new_simple_elem_array(n_jumps,
                                                     elem_size,
                                                     heap::host_address(td_info[td_jumps].adr));

        return heap::heap_address(jmps);
    }


    static md::uint32
    new_data(int n_bytes, int elem_size)
    {
        md::HADDR data = heap::new_simple_elem_array(n_bytes,
                                                     elem_size,
                                                     heap::host_address(td_info[td_data].adr));
        return heap::heap_address(data);
    }


    static md::uint32
    new_tddata(int n_bytes, int elem_size)
    {
        md::HADDR tddata = heap::new_simple_elem_array(n_bytes,
                                                       elem_size,
                                                       heap::host_address(td_info[td_tddata].adr));
        return heap::heap_address(tddata);
    }


    static md::uint32
    new_code(int n_bytes, int elem_size)
    {
        md::HADDR code = heap::new_simple_elem_array(n_bytes,
                                                     elem_size,
                                                     heap::host_address(td_info[td_code].adr));
        return heap::heap_address(code);
    }


    static md::uint32
    new_references(int n_bytes, int elem_size)
    {
        md::HADDR ref = heap::new_simple_elem_array(n_bytes,
                                                    elem_size,
                                                    heap::host_address(td_info[td_refs].adr));
        return heap::heap_address(ref);
    }


    static void
    new_module(module_t *&module, objf_header_t &h)
    {
        md::HADDR adr = heap::new_module(heap::host_address(td_info[td_module].adr),
                                         sizeof(module_t));
        module = reinterpret_cast<module_t *>(adr);

        add_module(module);
        module->name     = new_string(current_module_name);
        module->refcnt   = 0;
        module->finalize = 0;
        module->exports  = new_exports(h.n_exports, sizeof(export_t));
        module->privates = new_privates(h.nofPrv, sizeof(export_t));
        module->tdescs   = new_typedescs(h.nofDesc, sizeof(md::uint32));
        module->commands = new_commands(h.nofCom, sizeof(cmd_t));
        module->pointers = new_pointers(h.nofPtr, sizeof(md::uint32));
        module->imports  = new_imports(h.nofImports, sizeof(md::uint32));
        module->jumps    = new_jumps(h.caseSize, sizeof(md::uint8));
        module->data     = new_data(h.dataSize + h.constSize, sizeof(md::uint8));
        module->tddata   = new_tddata(h.typedescSize, sizeof(md::uint8));
        module->code     = new_code(h.codeSize, sizeof(md::uint8));
        module->refs     = new_references(h.refSize, sizeof(md::uint8));
        module->sb       = h.dataSize; /* offset in module->data where data/const divide occurs */
    }


    md::OADDR
    get_seg_adr(module_t *module, int segment, int offs)
    {
        md::HADDR r = NULL;

        switch (segment)
        {
        case objinfo::segCode: {
            md::OADDR offset = static_cast<md::OADDR>(offs);
            r = heap::host_address(module->code + offset);
            break;
        }

        case objinfo::segConst: {
            md::OADDR offset = static_cast<md::OADDR>(static_cast<int>(module->sb) + offs);
            r = heap::host_address(module->data + offset);
            break;
        }

        case objinfo::segCase: {
            md::OADDR offset = static_cast<md::OADDR>(offs);
            r = heap::host_address(module->jumps + offset);
            break;
        }

        case objinfo::segData: {
            md::OADDR offset = static_cast<md::OADDR>(static_cast<int>(module->sb) + offs);
            r = heap::host_address(module->data + offset);
            break;
        }

        case objinfo::segExport: {
            export_t *exp = get_module_export(module, offs);
            r =  reinterpret_cast<md::HADDR>(&exp->adr);
            break;
        }

        case objinfo::segCommand:
            r = reinterpret_cast<md::HADDR>(&(get_module_command(module, offs)->adr));
            break;

        case objinfo::segTypeDesc: {
            md::OADDR offset = static_cast<md::OADDR>(offs);
            r = heap::host_address(module->tddata + offset);
            break;
        }

        case objinfo::segTDesc: {
            md::OADDR offset = static_cast<md::OADDR>(offs *
                                                      static_cast<int>(sizeof(md::uint32)));
            r = heap::host_address(module->tdescs + offset);
            break;
        }

        default:
            dialog::fatal("bad segment type");
        }

        return heap::heap_address(r);
    }


    static void
    fixup_segment(module_t   *module,
                  int         segment,
                  int         kind,
                  int         offs,
                  md::uint32  target)
    {
        md::uint32  adr;
        md::uint32  target_offset;
        md::uint32 *hostAdr;

        assert(target != 0);
        target_offset = target;

        switch (kind)
        {
        case objinfo::FixAbs:
        case objinfo::FixRel:
            if (kind == objinfo::FixAbs) {
                adr = get_seg_adr(module, segment, offs);
            } else {
                assert(kind == objinfo::FixRel);
                adr = get_seg_adr(module, segment, offs);
                /* Relative offset to fixup-to target. */
                target -= (adr +
                           2 * static_cast<md::uint32>(sizeof(md::uint32)));
            }

            dialog::diagnostic("%s: %s at %8.8x to %8.8x [%8.8x] (%s:%#x)\n",
                               __func__,
                               (kind == objinfo::FixRel) ? "Rel" : "Abs",
                               adr, target, target_offset,
                               objinfo::seg_names[segment], offs);

            hostAdr  = reinterpret_cast<md::uint32 *>(heap::host_address(adr));
            *hostAdr = *hostAdr + target;
            break;

        case objinfo::FixBlk:
            adr = get_seg_adr(module, segment, offs);
            dialog::diagnostic("Blk: %8.8x to %#x bytes (%s)\n", adr, target,
                               objinfo::seg_names[segment]);
            hostAdr  = reinterpret_cast<md::uint32 *>(heap::host_address(adr));
            *hostAdr = target;
            break;

        default: dialog::fatal("bad fixup type");
        }
    }


    static md::OADDR
    get_local_symbol_adr(module_t *module, int sym_seg, int sym_adr)
    {
        return get_seg_adr(module, sym_seg, sym_adr);
    }


    static md::uint32
    get_imported_symbol_adr(module_t *module, int useIndex)
    {
        md::uint32  adr;
        module_t   *m;
        char       *name;

        if (useIndex >= static_cast<int>(sizeof(uses_info) /
                                         sizeof(uses_info[0]))) {
            dialog::fatal("useIndex: %#x; LEN(uses_info): %#x",
                          useIndex, (sizeof(uses_info) /
                                     sizeof(uses_info[0])));
        }

        m    = reinterpret_cast<module_t *>(heap::host_address(uses_info[useIndex].module));
        name = reinterpret_cast<char *>(heap::host_address(uses_info[useIndex].name));
        adr  = get_function_address(m, name);

        if (adr == 0) {
            dialog::fatal("mod: %s, ind: %#x, name: %s", m->name, useIndex, name);
        }
        return adr;
    }


    static void
    read_imports(FILE *fp, module_t *module, int n_imports)
    {
        string_t    mname;
        md::uint32  m;
        md::HADDR   imps    = heap::host_address(module->imports);
        md::uint32 *imports = reinterpret_cast<md::uint32 *>(imps);

        for (int i = 0; i < n_imports; ++i) {
            read_str(fp, mname);
            dialog::diagnostic("module '%s' imports '%s'\n", module->name, mname);

            m = heap::heap_address(reinterpret_cast<md::HADDR>(find_module(mname)));
            assert(m != 0); // desired module not found?
            imports[i] = m;
        }
    }


    static void
    read_symbol_info(FILE *objF, export_t &info)
    {
        char     ch;
        string_t name;
        int      fp;

        info.pvfprint = 0;
        read_ch(objF, ch);
        info.kind = ch;
        read_str(objF, name);
        info.name = new_string(name);
        read_num(objF, fp);
        info.fprint = fp;
        info.adr = 0;

        switch (info.kind) {
        case objinfo::Econst:                                                   break;
        case objinfo::Etype:                                                    break;
        case objinfo::Evar:                                                     break;
        case objinfo::Edarrtd:                                                  break;
        case objinfo::Earrtd:                                                   break;
        case objinfo::Erectd:                                                   break;
        case objinfo::Exproc /* Eiproc */:                                      break;
        case objinfo::Ecproc:                                                   break;
        case objinfo::Estruc:
            read_num(objF, fp);
            info.pvfprint = fp;
            break;

        default:
            dialog::fatal("bad symbol kind");
            break;
        }
    }


    static void
    rec_td(FILE *objF)
    {
        string_t rName, rAncName;
        int rpvfp, rSize, rAncMno, rAncfp;
        int rnofmeth, rnofinhmeth, rnofnewmeth, rnofptr;
        int MethInfoNum,  MethInfoAdr, PtrOffs;

        read_str(objF, rName);

        if (rName[0] == '\0') {
            read_num(objF, rpvfp);
        }

        read_num(objF, rSize);
        read_num(objF, rAncMno);

        if (rAncMno != -1) {
            read_str(objF, rAncName);
            read_num(objF, rAncfp);
        }

        read_num(objF, rnofmeth);
        read_num(objF, rnofinhmeth);
        read_num(objF, rnofnewmeth);
        read_num(objF, rnofptr);
        assert(rnofmeth == 0); /* bootstrap loader does not support methods */

        for (int k = 0; k < rnofnewmeth; ++k) {
            read_num(objF, MethInfoNum);
            read_num(objF, MethInfoAdr);
        }

        for (int k = 0; k < rnofptr; ++k) {
            read_num(objF, PtrOffs);
        }
    }


    static void
    dynarr_td(FILE *objF)
    {
        string_t aName;
        string_t aNameRecTD;
        int aFPrint, aDim, aForm, aMnoRecTD, aFPrintRecTD;
        char aTag;

        read_str(objF, aName);
        read_num(objF, aFPrint);
        read_ch(objF, aTag);

        switch (aTag) {
        case 1: /* open array of type */
            read_num(objF, aDim);
            read_num(objF, aForm); /* tdsize == 4 type form, number of dimensions*/
            break;

        case 2: /* open array of pointer */
            read_num(objF, aDim);
            read_num(objF, aForm); /* tdsize == 4 type form, number of dimensions*/
            break;

        case 3: /* open array of record */
            read_num(objF, aDim);
            read_num(objF, aMnoRecTD);
            read_str(objF, aNameRecTD);
            read_num(objF, aFPrintRecTD);
            /* tdsize == 8,  record TD pointer, number of dimensions*/
            break;

        case 4: /* open array of array */
            dialog::fatal("open array of array unsupported by bootstrap loader");

        default: dialog::fatal("bad dynamic array type");
        }
    }


    static void
    array_td(FILE *objF)
    {
        string_t aName;
        string_t aNameRecTD;
        int aFPrint, aDim, aNofDim, aForm, aMnoRecTD, aFPrintRecTD;
        char aTag;;

        read_str(objF, aName);
        read_num(objF, aFPrint);
        read_ch(objF, aTag);

        switch (aTag) {
        case 1:
            /* array of oridinal */
            read_num(objF, aForm);
            break;

        case 2:
            /* array of pointer */
            read_num(objF, aForm);
            break;

        case 3:
            /* array of record */
            read_num(objF, aMnoRecTD);
            read_str(objF, aNameRecTD);
            read_num(objF, aFPrintRecTD);
            break;

        default:
            dialog::fatal("bad array type");
        }

        read_num(objF, aNofDim);
        while (aNofDim > 0) {
            --aNofDim;
            read_num(objF, aDim);
        }
    }


    static void
    read_typedescriptors(FILE *objF, module_t *module, int n_descriptors)
    {
        char ch;

        for (int i = 0; i < n_descriptors; ++i) {
            read_ch(objF, ch);

            switch (ch) {
            case objinfo::Trec:
                rec_td(objF);
                break;

            case objinfo::Tdarray:
                dynarr_td(objF);
                break;

            case objinfo::Tarray:
                array_td(objF);
                break;

            default:
                dialog::fatal("bad type descriptor");
            }
        }
    }


    static void
    read_exports(FILE *objF, module_t *module, int n_export)
    {
        md::HADDR exports = heap::host_address(module->exports);
        for (int i = 0; i < n_export; ++i) {
            read_symbol_info(objF,
                             reinterpret_cast<export_t *>(exports)[i]);
        }
    }


    static void
    read_privates(FILE *objF, module_t *module, int n_privates)
    {
        for (int i = 0; i < n_privates; ++i) {
            md::HADDR privates = heap::host_address(module->privates);
            read_symbol_info(objF,
                             *reinterpret_cast<export_t *>(privates[i]));
        }
    }


    static void
    read_commands(FILE *objF, module_t *module, int n_commands)
    {
        cmd_t command;
        string_t name;

        for (int i = 0; i < n_commands; ++i) {
            cmd_t *cmds = reinterpret_cast<cmd_t *>(heap::host_address(module->commands));

            read_str(objF, name);
            command.name = new_string(name);
            command.adr = 0; /* Address will actually be created by a fixup. */
            cmds[i]     = command;
        }
    }


    static void
    read_pointers(FILE *objF, module_t *module, int n_pointers)
    {
        md::uint32 *ptrs = reinterpret_cast<md::uint32 *>(heap::host_address(module->pointers));
        for (int i = 0; i < n_pointers; ++i) {
            int offs;
            read_num(objF, offs);
            ptrs[i] = heap::heap_address(data_base(module) + offs);
        }
    }


    static void
    read_constants(FILE *objF, module_t *module, int n_bytes)
    {
        read_bytes(objF, &(heap::host_address(module->data)[module->sb]),
                   n_bytes);
    }


    static void
    read_typedescdata(FILE *objF, module_t *module, int n_bytes)
    {
        read_bytes(objF, heap::host_address(module->tddata), n_bytes);
    }


    static void
    read_code(FILE *objF, module_t *module, int n_bytes)
    {
        read_bytes(objF, heap::host_address(module->code), n_bytes);
    }


    static void
    check_structure_fingerprint(module_t *imported, md::OADDR name, int fp, bool priv)
    {
        int             found;
        int             i;
        md::HADDR       hp     = heap::host_address(imported->exports);
        int             n_elem = heap::record_elem_array_len(hp);
        export_array_t *exps   = reinterpret_cast<export_array_t *>(hp);

        dialog::diagnostic("checking fingerprint of %s.%s %#x\n",
                           heap::host_address(imported->name),
                           heap::host_address(name), fp);

        i = 0;
        while (i < n_elem) {
            md::HADDR   hp      = heap::host_address(exps[i].name);
            const char *expname = reinterpret_cast<const char *>(hp);
            const char *hname   = reinterpret_cast<const char *>(heap::host_address(name));

            if ((strcmp(expname, hname) == 0) &&
                (exps[i].kind & ((1 << objinfo::Upbstruc) |
                                 (1 << objinfo::Upvstruc)))) {
                if (priv) {
                    found = exps[i].pvfprint;
                } else {
                    found = exps[i].fprint;
                }

                if (found != fp) {
                    dialog::fatal("expected fingerprint %#x for %s.%s "
                                  "but found %#x in module <%s>\n",
                                  fp,
                                  heap::host_address(imported->name),
                                  name, found, current_module_name);
                }
            }
            ++i;
        }
    }


    static void
    read_uses(FILE *objF, module_t *module, int n_imports)
    {
        int          i;
        char         tag;
        string_t     n;
        md::uint32   name;
        int          pbfprint;
        uses_list_t *u;
        module_t    *umod;

        i = 0;
        for (int mno = 0; mno < n_imports; ++mno) {
            read_ch(objF, tag);
            while (tag != '\0') {
                md::uint32 *imps;       // Array of 'module_t' in Oberon heap.
                md::uint32  importedO; // module_t in Oberon form.
                module_t   *importedH; // module_t in host form..

                read_str(objF, n);
                name = new_string(n);
                read_num(objF, pbfprint);

                imps = reinterpret_cast<md::uint32 *>(heap::host_address(module->imports));
                importedO = imps[mno];
                importedH = reinterpret_cast<module_t *>(heap::host_address(importedO));
                switch (tag) {
                case objinfo::Uconst: case objinfo::Utype:
                case objinfo::Uvar: case objinfo::Uxproc:
                case objinfo::Ucproc: case objinfo::Urectd:
                case objinfo::Uarrtd: case objinfo::Udarrtd:
                    assert(i <= static_cast<int>(sizeof(uses_info) /
                                                 sizeof(uses_info[0])));
                    uses_info[i].name     = name;
                    uses_info[i].pbfprint = pbfprint;
                    uses_info[i].module   = importedO;
                    u                     = new uses_list_t();
                    u->name               = reinterpret_cast<name_t>(heap::host_address(name));
                    u->next               = uses_list;
                    uses_list             = u;

                    umod = reinterpret_cast<module_t *>(heap::host_address(uses_info[i].module));
                    dialog::diagnostic("use %#x: %s.%s pb: %#x\n",
                                       tag,
                                       umod->name,
                                       heap::host_address(name), pbfprint);

                    ++i;
                    break;

                case objinfo::Upbstruc:
                    check_structure_fingerprint(importedH, name,
                                                pbfprint, false);
                    break;

                case objinfo::Upvstruc: {
                    check_structure_fingerprint(importedH, name,
                                                pbfprint, true);
                    break;
                }

                default: dialog::fatal("bad uses type");
                }
                read_ch(objF, tag);
            }
        }
    }



    static void
    read_helper_fixups(FILE *objF, module_t *module, int n_helpers)
    {
        string_t    name;
        string_t    funcName;
        int         offs;
        module_t   *thatMod;
        md::uint32  funcAdr;

        for (int i = 0; i < n_helpers; ++i) {
            read_str(objF, name);

            /* only Kernel-based helper fixups allowed in bootstrap */
            assert(strcmp(name, "Kernel") == 0);
            read_str(objF, funcName);

            funcAdr = 0;
            if ((config::options & config::opt_ignore_helper_fixups) == 0) {
                thatMod = find_module(name);
                assert(thatMod != NULL); /* load if not found for non-bootstrap */
                funcAdr = get_function_address(thatMod, funcName);
                if (funcAdr != 0) {
                    dialog::diagnostic("Helper: %s.%s address: %xH\n",
                                       module_name(thatMod), funcName,
                                       funcAdr);
                } else {
                    dialog::fatal("%s: Kernel.%s not found", __func__, funcName);
                }
            }

            read_num(objF, offs);
            while (offs != -1) {
                if ((config::options & config::opt_ignore_helper_fixups) == 0) {
                    dialog::diagnostic("Helper: %s.%xH to %s.%s\n",
                                       module_name(module), offs,
                                       name, funcName);
                    fixup_segment(module, objinfo::segCode,
                                  objinfo::FixAbs, offs, funcAdr);
                }
                read_num(objF, offs);
            }
        }
    }


    static void
    read_fixups(FILE *objF, module_t *module, int n_fixups)
    {
        int mode, segment, offs, symMno, symSeg, symAdr, labSeg, labOffs;
        md::OADDR adr;
        char tag;

        dialog::diagnostic("\nregular fixups\n");

        for (int i = 0; i < n_fixups; ++i) {
            read_num(objF, mode);
            read_num(objF, segment);
            read_num(objF, offs);

            switch (mode) {
            case 0:             /* fixAbs */
            case 1:             /* fixRel */
                read_ch(objF, tag);

                if (tag == '\1') {
                    read_num(objF, symSeg);
                    read_num(objF, symMno);
                    read_num(objF, symAdr);

                    if (symMno == 0) {
                        adr = get_local_symbol_adr(module, symSeg, symAdr);
                    } else {
                        /* symAdr == index into Uses block */
                        adr = get_imported_symbol_adr(module, symAdr);
                    }
                } else {
                    /* Fixing up a jump destination label generated by the compiler. */
                    assert(tag == 0x2);
                    read_num(objF, labSeg);
                    read_num(objF, labOffs);
                    adr = get_seg_adr(module, labSeg, labOffs);
                }

                fixup_segment(module, segment, mode, offs, adr);
                break;

            case 2: {
                /* FixBlk (record type descriptor size) */
                md::int32 sz;
                md::uint32 aligned_size;

                read_num(objF, sz); // Read size.
                aligned_size = static_cast<md::uint32>(heap::align_block_size(sz));
                fixup_segment(module, segment, mode, offs, aligned_size);
                break;
            }

            default:
                assert(false);
            }
        }
    }


    static void
    read_reference(FILE *objF, module_t *module, int n_bytes)
    {
        read_bytes(objF, heap::host_address(module->refs), n_bytes);
    }


    static void
    read_magic_block(FILE *fp)
    {
        const md::int32 OFtag    = static_cast<md::int32>(0x0f8320000);
        const md::int32 OFtarget = 0x011161967;

        md::int32 version, targ;

        read_lint(fp, version);
        read_lint(fp, targ);

        if (version != OFtag || targ != OFtarget) {
            dialog::fatal("bad magic block: %s\n", current_module_name);
        }
    }


    static void
    read_header(FILE *fp, objf_header_t &h)
    {
        read_tag(fp, '\x80');
        read_lint(fp, h.refSize); read_lint(fp, h.n_exports); read_lint(fp, h.nofPrv);
        read_lint(fp, h.nofDesc); read_lint(fp, h.nofCom); read_lint(fp, h.nofPtr);
        read_lint(fp, h.nofHelpers); read_lint(fp, h.n_fixups);
        read_lint(fp, h.codeSize); read_lint(fp, h.dataSize);
        read_lint(fp, h.constSize); read_lint(fp, h.typedescSize);
        read_lint(fp, h.caseSize); read_lint(fp, h.exportSize);
        read_lint(fp, h.nofImports);
        read_str(fp, h.name);
        current_module_name = strdup(h.name);
    }


    static FILE *
    open_object(const char *module_name)
    {
        static const char suffix[] = ".Obj";
        char *fname;
        FILE *fp;

        /* This could be improved to have some type of configuration
         * which searches for object files but it is not worth the
         * trouble for a bootstrapping process
         */
        fname = new char[strlen(module_name) + sizeof(suffix) / sizeof(suffix[0])];
        strcpy(fname, module_name);
        strcat(fname, suffix);
        fp = fileutils::find_file_and_open(fname);
        assert(fp != NULL);
        delete [] fname;
        return fp;
    }


    module_t *
    load(const char *name)
    {
        module_t *module;
        FILE *objF;
        objf_header_t header;

        current_module_strings = NULL;

        module = reinterpret_cast<module_t *>(heap::host_address(module_list));
        while (module != NULL) {
            const char *hn = reinterpret_cast<const char *>(heap::host_address(module->name));
            if (strcmp(hn, name) == 0) {
                break;
            }
            module = reinterpret_cast<module_t *>(heap::host_address(module->next));
        }

        if (module == NULL) {
            /* module not found on list; load */
            dialog::progress("Loading %s\n", name);
            objF = open_object(name);
            if (objF != NULL) {
                read_magic_block(objF);

                /* Header */
                read_header(objF, header);
                new_module(module, header);

                /* imports */
                read_tag(objF, '\x81');
                read_imports(objF, module, header.nofImports);

                /* exports */
                read_tag(objF, '\x82');
                read_exports(objF, module, header.n_exports);

                /* private */
                read_tag(objF, '\x83');
                read_privates(objF, module, header.nofPrv);

                /* type desc */
                read_tag(objF, '\x84');
                read_typedescriptors(objF, module, header.nofDesc);

                /* commands */
                read_tag(objF, '\x85');
                read_commands(objF, module, header.nofCom);

                /* pointers */
                read_tag(objF, '\x86');
                read_pointers(objF, module, header.nofPtr);

                /* constants */
                read_tag(objF, '\x87');
                read_constants(objF, module, header.constSize);

                /* type descriptor data */
                read_tag(objF, '\x88');
                read_typedescdata(objF, module, header.typedescSize);

                /* code */
                read_tag(objF, '\x89');
                read_code(objF, module, header.codeSize);

                /* uses */
                read_tag(objF, '\x8A');
                read_uses(objF, module, header.nofImports);

                /* helper fixups */
                read_tag(objF, '\x8B');
                read_helper_fixups(objF, module, header.nofHelpers);

                /* fixups */
                read_tag(objF, '\x8C');
                read_fixups(objF, module, header.n_fixups);

                /* reference block */
                read_tag(objF, '\x8D');
                read_reference(objF, module, header.refSize);
                fclose(objF);

                while (current_module_strings != NULL) {
                    object_module_str_t *t0 = current_module_strings->next;
                    delete current_module_strings;
                    current_module_strings = t0;
                }
                current_module_strings = NULL;
                free(current_module_name);
            } else {
                module = NULL;
            }
        }
        ++n_loaded;
        return module;
    }


    /* find_module_and_offset:
     *
     *   Given an Oberon heap address, synthesize the module and the
     *   offset in the module's code block.
     *
     *   Only valid for code.
     */
    static void
    find_module_and_offset(md::OADDR address, module_t *&module, int &offs)
    {
        module_t *m = reinterpret_cast<module_t *>(heap::host_address(module_list));
        int       code_bytes;

        module = NULL;
        while (m != NULL) {
            if (m->code == 0) {
                dialog::print("module: '%s' no code  %p\n", m->name, &m->code);
            }
            code_bytes = heap::simple_elem_array_len(heap::host_address(m->code));
            if (address >= m->code &&
                address < m->code + static_cast<md::OADDR>(code_bytes)) {
                module = m;
                offs   = static_cast<int>(address - m->code);
                break;
            }
            m = reinterpret_cast<module_t *>(heap::host_address(m->next));
        }
    }


    /* Looks up Kernel module commands that are used by Virtual Machine engine */
    md::OADDR
    lookup_command(module_t *m, const char *helper)
    {
        int i   = 0;
        int len = heap::record_elem_array_len(heap::host_address(m->commands));

        while (i < len) {
            const cmd_t *cmd  = get_module_command(m, i);
            const char  *name = reinterpret_cast<const char *>(heap::host_address(cmd->name));
            if (strcmp(helper, name) == 0) {
                return cmd->adr;
            }
            ++i;
        }
        dialog::fatal("Unable to find 'Kernel.%s'\n", helper);
        return 0;
    }


    const char *
    module_name(module_t *m)
    {
        const char *name = reinterpret_cast<const char *>(heap::host_address(m->name));
        return name;
    }


    void
    verify_module_name(module_t *m, const char *mname)
    {
        UNUSED const char *name = module_name(m);
        assert(strcmp(name, mname) == 0);
    }


    void
    lookup_kernel_bootstrap_symbols(module_t *m)
    {
        md::OADDR adr;
        int       i = 0;

        /* The virtual machine has two special symbols in the Kernel
         * module that work to allow bootstrapping, and termination of
         * the whole system.  Here, those two symbols are looked up so
         * that they can be used.
         */
        verify_module_name(m, "Kernel");

        while (i < static_cast<int>(sizeof(bootstrap_symbol) /
                                    sizeof(bootstrap_symbol[0]))) {
            adr = lookup_command(m, bootstrap_symbol[i].name);
            bootstrap_symbol[i].adr = adr;
            ++i;
        }
    }


    void
    decode_pc__(md::OADDR pc, decode_pc_t &decode)
    {
        module_t   *module;
        const char *name;
        int         offs;

        find_module_and_offset(pc, module, offs);
        if (module != NULL) {
            name = reinterpret_cast<const char *>(heap::host_address(module->name));
            snprintf(decode, sizeof(decode) / sizeof(decode[0]) - 1,
                     "%s.%4.4xH", name, offs);
        } else {
            snprintf(decode, sizeof(decode) / sizeof(decode[0]) - 1,
                     "%xH", pc);
        }
    }


    void
    dump_module_list(void)
    {
        module_t *m = reinterpret_cast<module_t *>(module_list);
        while (m != NULL) {
            dump_module(m);
            m = reinterpret_cast<module_t *>(heap::host_address(m->next));
        }
    }
}
