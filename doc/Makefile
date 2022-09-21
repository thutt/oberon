# Copyright (c) 2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

doc__:	skl module
	$(PROLOG);					\
	echo "Docs: All targets built.";


module skl:	build-directories
	$(PROLOG);					\
	$(MAKE)						\
	    -C $(_BUILD_DIR)/$@				\
	    -f $(SKL_DIR)/doc/$@/Makefile		\
	    --no-print-directory			\
	    VPATH=$(SKL_DIR)/doc/$@			\
	    _BUILD_DIR=$(_BUILD_DIR)/$@			\
	    $@__;


clean:
	$(PROLOG);	\
	rm -rf $(_BUILD_DIR);

$(addprefix $(_BUILD_DIR)/,module skl):
	$(PROLOG);	\
	mkdir -p $@;

build-directories: |				\
	$(_BUILD_DIR)/module			\
	$(_BUILD_DIR)/skl
