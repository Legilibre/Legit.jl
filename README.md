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

### Conversion of all the legal codes

Generate the commits, sorted by code:

    julia src/Legit.jl -d -e -l 2020-12-31 -m codes ../legi ../codes-juridiques-francais.git

Reorder the commits by dates et by messages:

    julia src/LegitReorderCommits.jl ../codes-juridiques-francais.git

The above script generates a new orphan branch named "reordered".

To delete this "reordered" branch (to launch the script once again after a failure, for example):

    git branch -d reordered

Push this branch to its Git repositories (as master):

    git remote add framasoft git@git.framasoft.org:etalab/codes-juridiques-francais.git
    git push -u framasoft +reordered:master

    git remote add github git@github.com:etalab/codes-juridiques-francais.git
    git push -u github +reordered:master

To see the generated Git repository: https://git.framasoft.org/etalab/codes-juridiques-francais/tree/master.

To remove the remote "origin/master"  branch:

    git branch -rd origin/master

### Conversion of all the legislation that doesn't belong to legal codes

Generate the commits, sorted by legal document:

    julia src/Legit.jl -d -e -l 2020-12-31 -m non-codes ../legi ../lois-non-codifiees-et-reglements-francais.git

Reorder the commits by dates et by messages:

    julia src/LegitReorderCommits.jl ../lois-non-codifiees-et-reglements-francais.git/

Push this branch to its Git repositories (as master):

    git remote add framasoft git@git.framasoft.org:etalab/lois-non-codifiees-et-reglements-francais.git
    git push -u framasoft +reordered:master

    git remote add github git@github.com:etalab/lois-non-codifiees-et-reglements-francais.git
    git push -u github +reordered:master

To see the generated Git repository: https://git.framasoft.org/etalab/lois-non-codifiees-et-reglements-francais/tree/master.


<!--
To convert the law "Loi n° 78-753 du 17 juillet 1978 portant diverses mesures d'amélioration des relations entre
l'administration et le public et diverses dispositions d'ordre administratif, social et fiscal" ("loi cada", LEGI ID
`JORFTEXT000000339241`):

    julia src/Legit.jl ../legi/global/code_et_TNC_en_vigueur/TNC_en_vigueur/JORF/TEXT/00/00/00/33/92/JORFTEXT000000339241 ../loi-cada.git

To see the generated Git repository: https://git.framasoft.org/etalab/loi-cada/tree/master.
-->
