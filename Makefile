# Makefile to build and run the examples using KLEE.
#
# Copyright 2015, 2016 National University of Singapore

# In the following, please select where klee and its various tools are
# located in your system
KLEE=klee
KLEE_STATS=klee-stats
KLEE_REPLAY=klee-replay
KTEST_TOOL=ktest-tool
#KLEE=${HOME}/git/memdepend/klee/Release+Asserts/bin/klee
#KLEE_STATS=${HOME}/git/memdepend/klee/Release+Asserts/bin/klee-stats
#KLEE_REPLAY=${HOME}/git/memdepend/klee/Release+Asserts/bin/klee-replay
#KTEST_TOOL=${HOME}/git/memdepend/klee/Release+Asserts/bin/ktest-tool

# In the following, please select suitable include directory
CFLAGS=-g -I/usr/local/lib/tracerx/include
#CFLAGS=-g -I${HOME}/nus/kleetest
#CFLAGS=-g -I${HOME}/software/klee/include

LDFLAGS=-L${HOME}/software/klee/Release+Asserts/lib -lkleeBasic -lkleeModule -lkleeRuntest -lkleeCore -lkleeSupport
KLEE_RUNTIME_DIR=${HOME}/software/klee/Release+Asserts/lib

# We enable execution tree (tree.dot) output as the examples
# in this directory are small.
EXTRA_OPTIONS=-output-tree -interpolation-stat -write-pcs -use-query-log=all:pc,all:smt2

CC=clang
AS=${CC} -S
KLEE_FLAGS=${EXTRA_OPTIONS} -search=dfs

TARGETS=$(patsubst %.c,%.klee,$(wildcard *c))
INPUT_TARGETS=$(subst .klee,.inputs,${TARGETS})
IR_TARGETS=$(subst .klee,.ll,${TARGETS})
STPKLEE_TARGETS=$(subst .klee,.stpklee,${TARGETS})
EXECUTABLE_TARGETS=$(subst .klee,,${TARGETS})
COV_TARGETS=$(subst .klee,.cov,${TARGETS})

all: all-ir ${INPUT_TARGETS}

all-ir: ${IR_TARGETS}

all-replay: ${COV_TARGETS}

clean:
	rm -f klee-last *.bc *.ll *~ *.inputs *.gcno *.gcda *.cov *.stpcov core ${EXECUTABLE_TARGETS} 
	rm -rf klee-out-* ${TARGETS} ${STPKLEE_TARGETS} ${EXTRA_REMOVAL} 

# To prevent the removal of *.klee subdirectories
.PRECIOUS: %.klee %.stpklee

.SUFFIXES: .klee .stpklee .inputs .bc .ll .cov .stpcov

# For running KLEE with Z3 and interpolation
.bc.klee:
	time ${KLEE} ${KLEE_FLAGS} -output-dir=$@ $<
	opt -analyze -dot-cfg $<
	mv *.dot $@
	# Create SVGs from *.dot files
	for DOTFILE in $@/*.dot ; do \
		SVGFILE=`echo -n $$DOTFILE | sed -e s/\.dot/\.svg/ -` ; \
		dot -Tsvg $$DOTFILE -o $$SVGFILE ; \
	done

# For running KLEE with STP without interpolation
.bc.stpklee:
	time ${KLEE} ${KLEE_FLAGS} -select-solver=stp -output-dir=$@ $<
	opt -analyze -dot-cfg $<
	mv *.dot $@
	# Create SVGs from .dot files
	for DOTFILE in $@/*.dot ; do \
		SVGFILE=`echo -n $$DOTFILE | sed -e s/\.dot/\.svg/ -` ; \
		dot -Tsvg $$DOTFILE -o $$SVGFILE ; \
	done

# For replaying the tests and getting coverage information for the tests run
.klee.cov:
	####################################################################
	# KLEE-STATS Statistics                                            #
	#                                                                  #
	# KLEE displays a low coverage using klee-stats on small examples, #
	# due to additional code added.  The additional code is displayed  #
	# in <klee_output_dir>/assembly.ll.                                #
	####################################################################
	${KLEE_STATS} $<
	####################################################################
	# llvm-cov Statistics for line coverage                            #
	#                                                                  #
	# See the generated .cov file for the detailed execution count of  #
	# each line.                                                       #
	####################################################################
	${CC} ${CFLAGS} -fprofile-arcs -ftest-coverage ${LDFLAGS} $(subst .klee,.c,$<) -o $(subst .klee,,$<)
	for KTEST in $</*.ktest ; do \
		( LD_LIBRARY_PATH=${KLEE_RUNTIME_DIR} KTEST_FILE=$$KTEST ${KLEE_REPLAY} $(subst .klee,,$<) $$KTEST ) ; \
	done	
	llvm-cov -gcno=$(subst .klee,.gcno,$<) -gcda=$(subst .klee,.gcda,$<) > $@
	echo Line coverage = `grep '^[[:space:]]*[[:digit:]]\+' $@ |wc -l` of `sloccount $(subst .klee,.c,$<) |grep "Total Physical" | sed s/^[[:alpha:],[:space:],\(,\),\=]*//`

.stpklee.stpcov:
	####################################################################
	# KLEE-STATS Statistics                                            #
	#                                                                  #
	# KLEE displays a low coverage using klee-stats on small examples, #
	# due to additional code added.  The additional code is displayed  #
	# in <klee_output_dir>/assembly.ll.                                #
	####################################################################
	${KLEE_STATS} $<
	####################################################################
	# llvm-cov Statistics for line coverage                            #
	#                                                                  #
	# See the generated .stpcov file for the detailed execution count  #
	# of each line.                                                    #
	####################################################################
	${CC} ${CFLAGS} -fprofile-arcs -ftest-coverage ${LDFLAGS} $(subst .stpklee,.c,$<) -o $(subst .stpklee,,$<)
	for KTEST in $</*.ktest ; do \
		( LD_LIBRARY_PATH=${KLEE_RUNTIME_DIR} KTEST_FILE=$$KTEST ${KLEE_REPLAY} $(subst .stpklee,,$<) $$KTEST ) ; \
	done	
	llvm-cov -gcno=$(subst .stpklee,.gcno,$<) -gcda=$(subst .stpklee,.gcda,$<) > $@
	echo Line coverage = `grep '^[[:space:]]*[[:digit:]]\+' $@ |wc -l` of `sloccount $(subst .stpklee,.c,$<) |grep "Total Physical" | sed s/^[[:alpha:],[:space:],\(,\),\=]*//`

.klee.inputs:
	for KTEST in $</*.ktest ; do \
		( ( ${KTEST_TOOL} --write-ints $$KTEST ) >> $@ ) ; \
	done

%: %.c
	${CC} ${CFLAGS} -fprofile-arcs -ftest-coverage ${LDFLAGS} $< -o $@

.c.ll:
	${AS} -emit-llvm ${CFLAGS} $<

.c.bc:
	${CC} -emit-llvm ${CFLAGS} -c $<

