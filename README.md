# Legit

Convert French law in LEGI database ("Codes, lois et règlements consolidés") to Git & Markdown.

This script is highly experimental.

<!-- [![Build Status](https://travis-ci.org/etalab/Legit.jl.svg?branch=master)](https://travis-ci.org/etalab/Legit.jl) -->

LEGI Files:
- https://www.data.gouv.fr/fr/datasets/legi-codes-lois-et-reglements-consolides/
- ftp://legi:open1234@ftp2.journal-officiel.gouv.fr/

## Requirements

- [Julia language](http://julialang.org/)

## Example

To convert the law "Loi n° 78-753 du 17 juillet 1978 portant diverses mesures d'amélioration des relations entre
l'administration et le public et diverses dispositions d'ordre administratif, social et fiscal" ("loi cada", LEGI ID
`JORFTEXT000000339241`):

    julia src/Legit.jl ../legi/global/code_et_TNC_en_vigueur/TNC_en_vigueur/JORF/TEXT/00/00/00/33/92/JORFTEXT000000339241 ../loi-cada.git

To see the generated Git repository: https://git.framasoft.org/etalab/loi-cada/tree/master.
