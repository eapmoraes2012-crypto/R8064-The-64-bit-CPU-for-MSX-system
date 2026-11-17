#!/bin/bash
# Teste diferencial Z80: modelo em Python x RTL do nucleo (iverilog). Uso: ./rodar_z80.sh [semente_inicial] [semente_final]
source $HOME/oss/oss-cad-suite/environment
cd "$(dirname "$0")"
python3 z80rand.py ${1:-1} ${2:-300}
