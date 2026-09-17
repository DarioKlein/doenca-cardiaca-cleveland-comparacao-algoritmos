#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))
source(file.path("src", "nested", "data.r"))
source(file.path("src", "nested", "models.r"))
source(file.path("src", "nested", "evaluation.r"))

cat("\nRANDOM FOREST - CLEVELAND - VALIDACAO ANINHADA\n\n")
executar_cv_aninhada("random_forest")
