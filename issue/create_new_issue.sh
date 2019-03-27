#!/bin/bash

./console.sh > issue.new
cat /etc/issue >> issue.new
sudo install --mode 644 issue.new /etc/issue
rm issue.new
