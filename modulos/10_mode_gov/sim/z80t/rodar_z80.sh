#!/bin/bash
# Z80 differential test: Python model x core RTL (iverilog). Usage: ./rodar_z80.sh [first_seed] [last_seed]
source $HOME/oss/oss-cad-suite/environment
cd "$(dirname "$0")"
python3 z80rand.py ${1:-1} ${2:-300}
