#!/bin/bash

if [ -z "$1" ]; then
	echo "Usage: $0 <target>"
	exit 1
fi
# Target
target=$1
output="resultat-scanner.txt"

fonction print_tool() {
	echo "#######################"
	echo "#######  $1  ##########"
	echo "#######################"

echo "mon outil de scan v1.0" | tee -a $output
echo "Scan pour : $target" | -a $output

print_tool "sslscan"
sslscan $target | tee -a $output

print_tool "whatweb"
whatweb $target | tee -a $output

print_tool "amass"
amass enum -d $target -max-deph 2 -timeout 1 | tee -a $output
