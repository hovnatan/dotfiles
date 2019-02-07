#!/bin/bash

libtoolize
aclocal
autoheader
autoconf
sudo automake --add-missing
