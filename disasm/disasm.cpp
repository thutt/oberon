/* Copyright (c) 2000, 2021-2023 Logic Magicians Software */
#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>

#include "global.h"
#include "objio.h"
#include "dump.h"

bool show_dashes = false;

int main(int argc, char *argv[])
{
    static struct option opt[] = {
	{ "help",        no_argument,       NULL,   'h' },
        { "show-dashes", no_argument,       NULL,   256 },
    };
    int c;
    objio::file_mode_t mode;
    
    while (1) {
	c = getopt_long(argc, argv, "h", opt, NULL);
	if (c == EOF)
	    break;

	switch (c)
	{
	case 'h':
	    printf("Logic Magicians Oberon-3 Disassembler\n");
	    exit(0);
	    break;
	    
        case 256:
            ::show_dashes = true;
            break;

        case '?':
	default:
            break;
	}
    }
    mode = objio::open(argv[optind]);
    objio::read();
    objio::close();
    dump::file(mode);
    exit(0);
}
