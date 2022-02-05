/* Copyright (c) 2000, 2021, 2022 Logic Magicians Software */

#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#include "config.h"
#include "dialog.h"
#include "kernintf.h"
#include "heap.h"
#include "o3.h"
#include "skl.h"
#include "bootstrap.h"

namespace bootstrap
{
    /* The following functions which provide access to the host OS
     * dynamic loading facilty could be improved to do more caching
     * and provide a uniform method of handling errors, but since only
     * one target platform and CPU have been identified, this
     * mechanism will suffice for now.
     */
    static void
    load(const char *module)
    {
        O3::module_t *m;
        m = O3::load(module);
        if (m == NULL) {
            dialog::fatal("unable to load module '%s'\n", module);
        }
        O3::dump_module(m);
    }


    static void
    initialize_kernel(O3::module_t *m, const char *command_line)
    {
        md::uint32 cmdline   = heap::copy_command_line(command_line);

        fflush(stdout);

        skl::initialize_stack();
        lookup_kernel_bootstrap_symbols(m);

        skl::write_integer_register(skl::cpu, 1,
                                    heap::heap_address(heap::oberon_heap));
        skl::write_integer_register(skl::cpu, 2,
                                    heap::oberon_heap_size_in_bytes +
                                    heap::oberon_stack_size_in_bytes);
        skl::write_integer_register(skl::cpu, 3,
                                    heap::heap_address(heap::oberon_stack));
        skl::write_integer_register(skl::cpu, 4,
                                    heap::oberon_stack_size_in_bytes);
        skl::write_integer_register(skl::cpu, 5,
                                  O3::module_list);
        skl::write_integer_register(skl::cpu, 6,
                                    cmdline);

        kernintf::init_module(m);
    }

    static void
    initialize_modules(O3::module_t *m)
    {
        /* The Modules module requires the head of the module list to
         * be in the R1 so that the module list can be maintained.
         */
        skl::write_integer_register(skl::cpu, 1, O3::module_list);
        kernintf::init_module(m);
    }


    static O3::module_t *
    next_module(O3::module_t *m)
    {
        return reinterpret_cast<O3::module_t *>(heap::host_address(m->next));
    }


    int
    bootstrap(const char *command_line)
    {
        O3::module_t *kernel;
        O3::module_t *loaded_module;

        config::option_set(config::opt_ignore_helper_fixups);
        load("Kernel");
        config::option_clear(config::opt_ignore_helper_fixups);

        kernel = reinterpret_cast<O3::module_t *>(heap::host_address(O3::module_list));
        O3::get_kernel_td_info(kernel);
        O3::fixup_type_descriptors();

        load("HostOS");
        load("Reals");
        load("Console");
        load("Environment");
        load("FileDir");
        load("Files");
        load("DebugIO");
        load("ModuleInspector");
        load("Trap");
        load("CommandLine");
        load("Modules");

        /* 'uses' records are read but not stored, however since they
         * are dynamic arrays they require type descriptors.
         */
        O3::fixup_uses_type_descriptors();
        /* we must delay initialization of loaded modules until after
         * they are all loaded so that we do not have two pieces of
         * software managing the same memory (loader & Oberon heap
         * manager); this is a problem because the modules being
         * loaded expect dynamic memory allocation to be availble.
         *
         * InterfaceLinux is special because it needs some information
         * so that communcation with the OS can be done
         */
        loaded_module = reinterpret_cast<O3::module_t *>(heap::host_address(O3::module_list));
        /* Delay initialization of loaded modules until after they are
         * all loaded so that there are two pieces of software
         * managing the same heap (loader & Oberon heap manager); this
         * is a problem because modules being loaded expect dynamic
         * memory allocation to be availble -- and there can be only
         * one 'master of the heap' at a time.
         */

        verify_module_name(loaded_module, "Kernel");
        initialize_kernel(loaded_module, command_line);

        loaded_module = reinterpret_cast<O3::module_t *>(heap::host_address(O3::module_list));
        loaded_module = next_module(loaded_module);

        while ((loaded_module != NULL) &&
               (strcmp(O3::module_name(loaded_module), "Modules") != 0) &&
               (O3::n_inited < O3::n_loaded)) {
            dialog::progress("Initializing '%s'...",
                             O3::module_name(loaded_module));
            kernintf::init_module(loaded_module);

            dialog::progress("done\n");
            loaded_module = next_module(loaded_module);
        }

        assert(O3::n_inited == O3::n_loaded - 1);
        assert(strcmp(O3::module_name(loaded_module), "Modules") == 0);
        initialize_modules(loaded_module);

        return 0;
    }
}
