#!/bin/bash 
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

# Eerst backup files met een ~ verwijderen:
find . -name '*~' | xargs --no-run-if-empty /bin/rm

# Alle .pl en .pm files perltidy-en; als er een ERR ontstaat x.pl.tdy niet moven naar x.pl
find . -type d -name .svn -prune -o -name '*.pl' -exec perltidy '{}' ';' -and -exec /usr/bin/test ! -f '{}.ERR' ';' -and -exec /bin/mv -f '{}.tdy' '{}' ';'
find . -type d -name .svn -prune -o -name '*.pm' -exec perltidy '{}' ';' -and -exec /usr/bin/test ! -f '{}.ERR' ';' -and -exec /bin/mv -f '{}.tdy' '{}' ';'

# Overgebleven .ERR en tdy weghalen
find . -type d -name .svn -prune -o -name '*.ERR' -print | xargs --no-run-if-empty /bin/rm
find . -type d -name .svn -prune -o -name '*.tdy' -print | xargs --no-run-if-empty /bin/rm
