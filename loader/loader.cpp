/* Copyright (c) 2000, 2020, 2021, 2022 Logic Magicians Software */
/* $Id: loader.cpp,v 1.15 2002/02/05 04:40:22 thutt Exp $ */
#include <assert.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/resource.h>
#include <setjmp.h>
#include <unistd.h>

#include "bootstrap.h"
#include "config.h"
#include "dialog.h"
#include "heap.h"
#include "kernintf.h"
#include "skl.h"

static struct option long_options[] = {
    { "help",              no_argument,       NULL, 'h' },
    { "version",           no_argument,       NULL, 'v' },
    { "verbose",           no_argument,       NULL, 256 },
    { "instruction-count", no_argument,       NULL, 257 },
    { "dump-heap",         no_argument,       NULL, 258 },
    // 259 unused.
    { "diagnostic",        no_argument,       NULL, 260 },
    // 261 unused.
    { "trace",             no_argument,       NULL, 262 },
    { NULL, 0, 0, 0 }
};

static jmp_buf signal_buf;


static void
help(const char *program_name)
{
    dialog::print("%s\n"
                  "[--help | "
                  "--version | "
                  " --verbose | "
                  "--dump-heap | "
                  "--diagnostic | "
                  "instruction-count |\n"
                  " --stack <stack-size-in-megabytes> | "
                  "--trace]..."
                  "\n", program_name);
}


static void
version(void)
{
    dialog::print("SKL Oberon-2 Loader $Revision: 1.15 $\n"
                  "Copyright (c) 2021 Logic Magicians\n"
                  "For non-commerical distribution only\n");
    dialog::print("Heap: %d bytes\n", heap::default_heap_size_in_bytes);
}


static void
segv_signal_handler(int signum, void *siginfo, void *uc)
{
    longjmp(signal_buf, 1);
}


static bool
create_heap(md::uint32 heap_mb, md::uint32 stack_mb)
{
    if (heap::make_heap(heap_mb, stack_mb)) {
        skl::initialize_memory(heap::host_to_heap(heap::oberon_heap),
                               heap::total_heap_size_in_bytes);
        return true;
    }
    return false;
}

/* Returns stack size in megabytes */
static int
compute_stack_size(void)
{
    const char *stack = getenv("LMS_OBERON_STACK_SIZE");

    if (stack != NULL) {
        int      size = atoi(stack);
        unsigned uval = static_cast<unsigned>(size);

        if (size <= 0 || uval > heap::max_stack_size_in_megabytes) {
            dialog::fatal("Stack size '%d' invalid; range 0..%d",
                          size, heap::max_stack_size_in_megabytes);
        }
        return size;
    } else {
        return heap::default_stack_size_in_bytes / (1024 * 1024);
    }
}


/* Returns heap size in megabytes */
static int
compute_heap_size(void)
{
    const char *heap  = getenv("LMS_OBERON_HEAP_SIZE");

    if (heap != NULL) {
        int      size = atoi(heap);
        unsigned uval = static_cast<unsigned>(size);

        if (size <= 0 || uval > heap::max_heap_size_in_megabytes) {
            dialog::fatal("Heap size '%d' invalid; range 0..%d",
                          size, heap::max_heap_size_in_megabytes);
        }
        return size;
    } else {
        return heap::default_heap_size_in_bytes / (1024 * 1024);
    }
}


int
main(int argc, char *argv[])
{
    int return_value = 0;
    int heap_size_in_megabytes = compute_heap_size();
    int stack_size_in_megabytes = compute_stack_size();

    signal(SIGSEGV, reinterpret_cast<void (*)(int)>(segv_signal_handler));

    while (1) {
        int c;
        int option_index = 0;

        c = getopt_long(argc, argv, "hv", long_options, &option_index);

        if (c == EOF)
            break;

        switch (c) {
        case 'h':
            help(argv[0]);
            exit(0);

        case 'v':
            version();
            exit(0);

        case 256:
            config::option_set(config::opt_progress);
            break;

        case 257:
            config::option_set(config::opt_instruction_count);

        case 258:
            config::option_set(config::opt_dump_heap);
            break;

        case 259:
            break;

        case 260:
            config::option_set(config::opt_diagnostic);
            break;

        case 262:
            config::option_set(config::opt_trace_cpu);
            break;

        default:
            dialog::warning("option ignored '%s'\n", argv[optind-1]);
        }
    }

    /* The memory blcok allocated for the Oberon heap includes the
     * requested stack size and the requested heap size.
     */
    if (create_heap(heap_size_in_megabytes,
                    stack_size_in_megabytes)) {
        char *cmdline = NULL;
        int  len;

        /* Allocate stack as a system block at the beginning of the
         * memory allocated from the host OS. */
        heap::system_new(heap::oberon_stack,
                         stack_size_in_megabytes * (1024 * 1024));

        /* Concatenate the commandline parameters that are not
         * processed by the bootstrap loader into a single command
         * line for passing to the Oberon system.
         */
        len = strlen(argv[0]);
        for (int i = optind; i < argc; ++i) {
            len += strlen(argv[i]) + 1; /* argument + ' ' */
        }

        cmdline = new char[len + 1]; /* total length + '\0' */

        strcpy(cmdline, argv[0]);
        for (int i = optind; i < argc; ++i) {
            strcat(cmdline, " ");
            strcat(cmdline, argv[i]);
        }

        if (setjmp(config::exit_data.jmpbuf) == 0) {
            if (setjmp(signal_buf) == 0) {
                return_value = bootstrap::bootstrap(cmdline);
                config::quit(return_value);
            } else {
                fsync(1);
                return_value = -1;
            }
        } else {
            /* All exit paths should come through here. */
            heap::release_heap(heap_size_in_megabytes, stack_size_in_megabytes);
            delete [] cmdline;
            if (config::options & config::opt_instruction_count) {
                dialog::print("Instruction Count: %u\n", skl::cpu._instruction_count);
            }
            return_value = config::exit_data.rc;
        }
    } else {
        dialog::fatal("%s: failure making %d Mb heap\n", argv[0], heap_size_in_megabytes);
    }

    return return_value;
}
