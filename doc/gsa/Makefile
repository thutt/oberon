# Copyright (c) 2022 Logic Magicians Software
include $(SKL_DIR)/make/config.mk

%.1: %.mp
	$(PROLOG);				\
	mpost $<;


SENTINEL	=				\
	gen-gsa-instruction.sentinel

INST_INCLUDE	=				\
	gsa-instruction.d

TEX	=					\
	gsa.tex					\
	gsa-acronyms.tex			\
	gsa-alias-analysis.tex			\
	gsa-const-propagation.tex		\
	gsa-copy-propagation.tex		\
	gsa-hierarchy.tex			\
	gsa-macros.tex				\
	gsa-notes.tex				\
	gsa-structure.tex			\
	gsa-value-numbering.tex			\
	gsa-variables.tex


# MP_SOURCES
#
# Metapost appears to have a defect that manifests under these
# conditions:
#
#  o Change to build directory (based on $(SKL_BUILD_DIR))
#
#  o Invoke 'mpost' with the full pathname of the MetaPost
#    source file:
#
#    mpost ${SKL_DIR}/doc/gsa/gsa-hierarchy.mp;
#
#     Preloading the plain mem file, version 1.005) )
#     (${SKL_DIR}/doc/gsa/gsa-hierarchy.mp
#     (/usr/share/texlive/texmf-dist/metapost/base/boxes.mp)
#     >> ${SKL_DIR}/doc/gsa/gsa-hierarchy.mp
#     >> ${SKL_DIR}/doc/gsa/gsa-hierarchy.mpx
#     ! ! Unable to read mpx file.
#
#  It is not understood why this fails.  If the CWD is the same as the
#  MetaPost source file, the same invocation succeeds.
#
#  To work around this problem, the sources are copied to the build
#  directory.
#
MP_SOURCES	=				\
	gsa-hierarchy.mp			\
	gsa-instruction-simple.mp


include $(INST_INCLUDE)

# GSAINSTMP is set by '$(INST_INCLUDE)'
#
GSAMP	=					\
	$(MP_SOURCES)				\
	$(GSAINSTMP)

STYLE_MACRO	:= $(SKL_DIR)/doc/style-macros
DOC_DIR		:= $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PACKAGES	:= $(STYLE_MACRO):$(DOC_DIR):$(TEXINPUTS)
TEX_OPTS	:= \
	--halt-on-error

gsa__:		gsa-mp gsa.ps $(INST_INCLUDE)
	$(PROLOG);				\
	echo "GSA Docs: All targets built.";


gsa.ps:		gsa.dvi gsa-mp
	$(PROLOG);				\
	dvips -o$@ $<;


gsa.dvi:	$(TEX)							\
		$(GSAMP)						\
		$(SKL_DIR)/doc/style-macros/lms-style-macros.tex	\
		gsa-mp
	$(PROLOG);				\
	export TEXINPUTS=$(PACKAGES);		\
	latex $(TEX_OPTS) $<;			\
	makeindex $(@:.dvi=.idx);		\
	latex $(TEX_OPTS) $<;


gsa-mp:		$(GSAMP:.mp=.1)
	$(PROLOG);				\
	touch $@;

$(GSAMP:.mp=.1):	$(SENTINEL)

$(INST_INCLUDE):	$(SENTINEL) gsa-instruction.template
	echo "$@ has been built";

$(SENTINEL):					\
		gsa-instruction.template	\
		gsa-instruction-prologue.mp	\
		gsa-instruction-epilogue.mp
	$(PROLOG);							\
	$(SKL_DIR)/doc/gsa/gsa-instruction.py				\
		--template $(SKL_DIR)/doc/gsa/gsa-instruction.template	\
		--makefile-include $(INST_INCLUDE)			\
		$(if $(VERBOSE),--verbose);				\
	touch $@;


gsa-hierarchy.mp:	$(SKL_DIR)/doc/gsa/gsa-hierarchy-orig.mp
	cp $< $@;


gsa-instruction-prologue.mp:	$(SKL_DIR)/doc/gsa/gsa-instruction-prologue-orig.mp
	cp $< $@;


gsa-instruction-epilogue.mp:	$(SKL_DIR)/doc/gsa/gsa-instruction-epilogue-orig.mp
	cp $< $@;


gsa-instruction-simple.mp:	$(SKL_DIR)/doc/gsa/gsa-instruction-simple-orig.mp
	cp $< $@;

