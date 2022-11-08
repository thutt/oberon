# Copyright (c) 2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

TEX	=					\
	memory.tex				\
	introduction.tex			\
	blockdesc.tex				\
	typedesc.tex				\
	gc.tex					\
	macros.tex


STYLE_MACRO	:= $(SKL_DIR)/doc/style-macros
DOC_DIR		:= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PACKAGES	:= $(STYLE_MACRO):$(DOC_DIR):$(TEXINPUTS)
TEX_OPTS	:= \
	--halt-on-error

memory__:		memory.ps
	$(PROLOG);				\
	echo "memory: All targets built.";


memory.ps:		memory.dvi
	$(PROLOG);				\
	dvips -o$@ $<;


memory.dvi:	$(TEX)							\
		$(SKL_DIR)/doc/style-macros/lms-style-macros.tex
	$(PROLOG);				\
	export TEXINPUTS=$(PACKAGES);		\
	latex $(TEX_OPTS) $<;			\
	latex $(TEX_OPTS) $<;
