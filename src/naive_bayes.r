#!/usr/bin/env Rscript

SEMENTE <- 20260804L
REPETICOES <- 3L
NUMERO_FOLDS <- 5L
LIMIAR <- 0.5

source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))

ajustar_naive_bayes <- function(dados_treino, configuracao, semente) {
  set.seed(semente)
  argumentos <- list(
    x = dados_treino[, VARIAVEIS_PREDITORAS, drop = FALSE],
    y = dados_treino[[VARIAVEL_ALVO]],
    laplace = configuracao$laplace,
    usekernel = configuracao$usar_kernel
  )

  if (configuracao$usar_kernel) {
    argumentos$adjust <- configuracao$ajuste
  }

  do.call(naivebayes::naive_bayes, argumentos)
}

prever_naive_bayes <- function(modelo, novos_dados) {
  probabilidades <- predict(
    modelo,
    newdata = novos_dados[, VARIAVEIS_PREDITORAS, drop = FALSE],
    type = "prob"
  )
  as.numeric(probabilidades[, CLASSE_POSITIVA])
}

executar_analise <- function() {
  inicio <- Sys.time()
  cat("\nNAIVE BAYES - HEART DISEASE UCI\n\n")

  dados <- carregar_dados_coracao()
  configuracoes <- data.frame(
    id = c("gaussiano", "kde"),
    laplace = c(1, 1),
    usar_kernel = c(FALSE, TRUE),
    ajuste = c(NA_real_, 1),
    stringsAsFactors = FALSE
  )

  avaliacao <- executar_cv_repetida(
    dados, configuracoes, ajustar_naive_bayes, prever_naive_bayes,
    SEMENTE, NUMERO_FOLDS, REPETICOES, LIMIAR
  )

  cat(sprintf("\nAjustes de CV: %d.\n", avaliacao$quantidade_ajustes))
  cat("\nRanking medio das configuracoes:\n")
  print(avaliacao$ranking_configuracoes, row.names = FALSE)
  cat("\nResumo do modelo selecionado:\n")
  mostrar_resumo(avaliacao$resumo_modelo)
  salvar_resultados("naive_bayes", avaliacao)

  tempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))
  cat(sprintf("\nTempo total: %.2f segundos.\n", tempo))
}

executar_analise()
