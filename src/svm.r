#!/usr/bin/env Rscript

SEMENTE <- 20260804L
REPETICOES <- 3L
NUMERO_FOLDS <- 5L
LIMIAR <- 0.5
VARIAVEIS_IMPUTADAS <- c("vasos_principais", "talassemia")

source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))

aprender_pre_processamento <- function(dados_treino) {
  modas <- aprender_modas(dados_treino, VARIAVEIS_IMPUTADAS)
  dados_tratados <- aplicar_modas(dados_treino, modas)

  medias <- vapply(
    dados_tratados[VARIAVEIS_NUMERICAS], mean, numeric(1),
    na.rm = TRUE
  )
  desvios <- vapply(
    dados_tratados[VARIAVEIS_NUMERICAS], stats::sd, numeric(1),
    na.rm = TRUE
  )
  desvios[!is.finite(desvios) | desvios == 0] <- 1

  list(modas = modas, medias = medias, desvios = desvios)
}

aplicar_pre_processamento <- function(dados, pre_processamento) {
  dados_tratados <- aplicar_modas(dados, pre_processamento$modas)

  for (variavel in VARIAVEIS_NUMERICAS) {
    dados_tratados[[variavel]] <- (
      dados_tratados[[variavel]] - pre_processamento$medias[[variavel]]
    ) / pre_processamento$desvios[[variavel]]
  }

  dados_tratados
}

ajustar_svm <- function(dados_treino, configuracao, semente) {
  pre_processamento <- aprender_pre_processamento(dados_treino)
  dados_tratados <- aplicar_pre_processamento(
    dados_treino, pre_processamento
  )

  set.seed(semente)
  modelo <- e1071::svm(
    stats::reformulate(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO),
    data = dados_tratados[, c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO)],
    type = "C-classification",
    kernel = "linear",
    cost = configuracao$custo,
    scale = FALSE,
    probability = TRUE,
    fitted = FALSE
  )

  list(modelo = modelo, pre_processamento = pre_processamento)
}

prever_svm <- function(ajuste, novos_dados) {
  dados_tratados <- aplicar_pre_processamento(
    novos_dados, ajuste$pre_processamento
  )
  predicao <- predict(
    ajuste$modelo,
    newdata = dados_tratados[, VARIAVEIS_PREDITORAS, drop = FALSE],
    probability = TRUE
  )

  probabilidades <- attr(predicao, "probabilities")
  as.numeric(probabilidades[, CLASSE_POSITIVA])
}

executar_analise <- function() {
  inicio <- Sys.time()
  cat("\nSVM LINEAR - HEART DISEASE UCI\n\n")

  dados <- carregar_dados_coracao()
  configuracoes <- data.frame(
    id = c("svm_custo_0.1", "svm_custo_1", "svm_custo_10"),
    custo = c(0.1, 1, 10),
    stringsAsFactors = FALSE
  )

  avaliacao <- executar_cv_repetida(
    dados, configuracoes, ajustar_svm, prever_svm,
    SEMENTE, NUMERO_FOLDS, REPETICOES, LIMIAR
  )

  cat(sprintf("\nAjustes de CV: %d.\n", avaliacao$quantidade_ajustes))
  cat("\nRanking medio das configuracoes:\n")
  print(avaliacao$ranking_configuracoes, row.names = FALSE)
  cat("\nResumo do modelo selecionado:\n")
  mostrar_resumo(avaliacao$resumo_modelo)
  salvar_resultados("svm", avaliacao)

  tempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))
  cat(sprintf("\nTempo total: %.2f segundos.\n", tempo))
}

executar_analise()
