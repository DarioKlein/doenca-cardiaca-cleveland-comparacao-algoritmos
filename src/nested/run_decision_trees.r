#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))
source(file.path("src", "nested", "data.r"))
source(file.path("src", "nested", "models.r"))
source(file.path("src", "nested", "evaluation.r"))

cat("\nARVORE DE DECISAO - CLEVELAND - VALIDACAO ANINHADA\n\n")
executar_cv_aninhada("decision_trees")
