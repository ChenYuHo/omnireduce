#!/bin/bash
set -e
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
git submodule init
git submodule update --init "$@" --recursive
cd $SCRIPTPATH/pytorch && git apply $SCRIPTPATH/pytorch.patch
cd $SCRIPTPATH/gloo && git apply $SCRIPTPATH/gloo.patch
