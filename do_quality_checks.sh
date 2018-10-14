#!/bin/sh
#
# this script tries to do some quality checks
# automatically. It counts compiler warnings,
# builds in both debug/release mode, test multiple
# compilers etc.


set -e

export LANG=

rootdir=$(dirname $0)

###############################################################################

start_from_scratch() {
cd $rootdir
if [ -e Makefile ] ; then
   make distclean >/dev/null 2>&1
fi

}
###############################################################################
#argument 1 is the compiler
#argument 2 is the c++ standard
compile_and_test_standard() {
start_from_scratch
echo using $(basename $1) with standard $2
if ! ./bootstrap.sh >bootstrap.log 2>&1; then
  echo failed bootstrap - see bootstrap.log
  exit 1
fi
if ! ./configure --enable-warnings CXX=$1 CXXFLAGS="-std=$2" >configure.log 2>&1 ; then
  echo failed configure - see configure.log
  exit 1
fi
#make sure it compiles
if ! make >make.log 2>&1; then
echo failed make
exit 1
fi
#check for warnings
if grep -q "warning" make.log; then
 echo found warning - see make.log
 exit 1
fi
#run the tests
if ! make check >makecheck.log 2>&1 ; then
   echo failed make check - see makecheck.log
   exit 1
fi
}
###############################################################################
#argument 1 is the compiler
compile_and_test() {
#this is the test program to compile, so we know the compiler and standard lib
#works. clang 4 with c++2a does not.
/bin/echo -e "#include <iostream>">x.cpp
#does the compiler understand c++11? That is mandatory.
if ! $1 -c x.cpp -std=c++11 >/dev/null 2>&1 ; then
  echo this compiler does not understand c++11
  exit 1
fi
compile_and_test_standard $1 c++11

#loop over all standard flags>11 and try those which work.
#use the code words.
for std in 1y 1z 2a ; do
if ! $1 -c x.cpp -std=c++$std >/dev/null 2>&1 ; then
  echo compiler does not understand c++$std, skipping this combination.
else
    compile_and_test_standard $1 c++$std
fi
done
}
###############################################################################

run_with_sanitizer() {
echo "running with sanitizer (options $2)"
#find the latest clang compiler
latestclang=$(ls $(which clang++)* |sort -g |tail -n1)
if [ ! -x $latestclang ] ; then
  echo could not find latest clang $latestclang
  exit 1
fi

start_from_scratch
./bootstrap.sh >bootstrap.log
./configure CXX=$latestclang CXXFLAGS="-std=c++1y $1"   >configure.log
make > make.log 2>&1
export UBSAN_OPTIONS="halt_on_error=true exitcode=1"
export ASAN_OPTIONS="halt_on_error=true exitcode=1"
make check >make-check.log 2>&1
}
###############################################################################

#keep track of which compilers have already been tested
echo "">inodes_for_tested_compilers.txt

#try all variants of g++
if which g++ >/dev/null ; then
  for COMPILER in $(which g++)* ; do
    inode=$(stat --dereference --format=%i $COMPILER)
    if grep -q "^$inode\$" inodes_for_tested_compilers.txt ; then
       echo skipping this compiler $COMPILER - already tested
    else
      #echo trying gcc $GCC:$($GCC --version|head -n1)
       echo $inode >>inodes_for_tested_compilers.txt
       compile_and_test $COMPILER c++11
    fi
  done
fi

#try all variants of clang
if which clang++ >/dev/null ; then
  for COMPILER in $(which clang++)* ; do
    inode=$(stat --dereference --format=%i $COMPILER)
    if grep -q "^$inode\$" inodes_for_tested_compilers.txt ; then
       echo skipping this compiler $COMPILER - already tested
    else
      #echo trying gcc $GCC:$($GCC --version|head -n1)
       echo $inode >>inodes_for_tested_compilers.txt
       compile_and_test $COMPILER c++11
    fi
  done
fi

#run unit tests with sanitizers enabled
run_with_sanitizer "-fsanitize=undefined -O3"
run_with_sanitizer "-fsanitize=address -O0"

