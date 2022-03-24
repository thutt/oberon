# Copyright (c) 2000, 2021-2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

TEX	=	module.tex			\
		macros.tex			\
		intro.tex			\
		environment.tex

PKG_DIR		:= $(SKL_DIR)/doc/packages
PKG_MACRO	:=
STYLE_MACRO	:= $(SKL_DIR)/doc/style-macros
DOC_DIR		:= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PACKAGES	:= $(PKG_MACRO):$(STYLE_MACRO):$(DOC_DIR):$(TEXINPUTS)
TEX_OPTS	:= \
	--halt-on-error

module__:		module.pdf
	$(PROLOG);				\
	echo "All targets built.";


module.pdf:	$(TEX) \
		$(SKL_DIR)/doc/style-macros/lms-style-macros.tex
	$(PROLOG);				\
	export TEXINPUTS=$(PACKAGES);		\
	pdflatex $(TEX_OPTS) $<;		\
	makeindex $(@:.dvi=.idx);		\
	pdflatex $<;
