#!/bin/bash

# Convert line endings in shell scripts from CRLF to LF
# This script should be run on the host machine before building Docker images

echo "Converting line endings in shell scripts..."

# Find all shell scripts and convert their line endings
find . -name "*.sh" -type f -exec sed -i 's/\r$//' {} \;

echo "Checking modified files:"
find . -name "*.sh" -type f -exec file {} \;

echo "Line endings conversion complete."
