# Copyright (c) 2022 Logic Magicians Software

$(if $(SKL_DIR),,$(error 'SKL_DIR' is not defined.))
$(if $(filter $(SKL_ARCHITECTURE),Intel-x86-64  Arm64),,	\
   $(error 'SKL_ARCHITECTURE' is not Intel-x86-64 or Arm64.))

include $(SKL_DIR)/make/config.mk

.DEFAULT_GOAL	:= all


.PHONY:	all disasm loader clean doc show-preprocessor-symbols
all:	loader disasm doc
	$(PROLOG);					\
	echo "All targets built.";

disasm loader doc:	build-directories
	$(PROLOG);					\
	$(MAKE)						\
	    -C $(_BUILD_DIR)/$@				\
	    -f $(SKL_DIR)/$@/Makefile			\
	    --no-print-directory			\
	    VPATH=$(SKL_DIR)/$@				\
	    _BUILD_DIR=$(_BUILD_DIR)/$@			\
	    $@__;

clean:
	$(PROLOG);	\
	rm -rf $(_BUILD_DIR);

$(addprefix $(_BUILD_DIR)/,disasm loader doc):
	$(PROLOG);	\
	mkdir -p $@;

build-directories:				\
	| $(_BUILD_DIR)/disasm			\
	  $(_BUILD_DIR)/loader			\
	  $(_BUILD_DIR)/doc


# Show predefined preprocessor symbols for this compiler.  This is
# useful when looking for symbols that are defined by a particular
# compiler.  For example: determining if the compiler is big- or
# little-endian.
#
show-preprocessor-symbols:
	$(CC) -dM -E - </dev/null
