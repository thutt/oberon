# Copyright (c) 2000, 2021-2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

TEX	=	skl.tex				\
		macros.tex			\
		intro.tex			\
		environment.tex			\
		encodings.tex			\
		instruction.tex			\
		architecture.tex		\
		memory-access.tex		\
		exceptions.tex			\
		vmsvc.tex

PKG_DIR		:= $(SKL_DIR)/doc/packages
PKG_MACRO	:=
STYLE_MACRO	:= $(SKL_DIR)/doc/style-macros
DOC_DIR		:= $(SKL_DIR)/doc/skl
PACKAGES	:= $(PKG_MACRO):$(STYLE_MACRO):$(DOC_DIR):$(TEXINPUTS)
TEX_OPTS	:= \
	--halt-on-error

skl__:		skl.pdf
	$(PROLOG);				\
	echo "All targets built.";


skl.pdf:	$(TEX) \
		$(SKL_DIR)/doc/style-macros/lms-style-macros.tex
	$(PROLOG);				\
	export TEXINPUTS=$(PACKAGES);		\
	pdflatex $(TEX_OPTS) $<;		\
	makeindex $(@:.dvi=.idx);		\
	pdflatex $<;
