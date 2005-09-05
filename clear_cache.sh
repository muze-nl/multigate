#!/bin/bash
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

# Delete all regular files which data was last modified more than 0 minutes ago
#find ./cache/ -mmin +0 -type f -exec echo '{}' ';'
find ./cache/ -type d -name .svn -prune -o -mmin +0 -type f -exec rm '{}' ';' -and -exec echo 'deleted {}' ';'
