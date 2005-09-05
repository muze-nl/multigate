#!/bin/bash
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

# Find all modules used in this tree, quick and dirty and stupid
# Isn't there an existing perl solution???

echo "Commands"
echo "--------"
grep -r ^use\ .*\; ./commands/*/*.pl | cut -f2- -d":" | cut -d" " -f2- | grep -v ^lib\ | grep -v ^vars\ | grep -v ^constant\ | cut -f1 -d" "| cut -f1 -d";"|sort |uniq

echo
echo "Libs"
echo "--------"
grep -r ^use\ .*\; ./lib/* | cut -f2- -d":" | cut -d" " -f2- | grep -v ^lib\ | grep -v ^vars\ | grep -v ^constant\ | cut -f1 -d" "| cut -f1 -d";"|sort |uniq

echo
echo "Wrappers"
echo "---------"
grep -r ^use\ .*\; ./wrappers/*/*.pl | cut -f2- -d":" | cut -d" " -f2- | grep -v ^lib\ | grep -v ^vars\ | grep -v ^constant\ | cut -f1 -d" "| cut -f1 -d";"|sort |uniq
