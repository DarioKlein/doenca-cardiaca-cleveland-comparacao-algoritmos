#!/usr/bin/env Rscript

SEMENTE <- 20260804L
REPETICOES <- 3L
NUMERO_FOLDS <- 5L
LIMIAR <- 0.5
NUMERO_THREADS <- 2L
VARIAVEIS_IMPUTADAS <- c("vasos_principais", "talassemia")

source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))

ajustar_random_forest <- function(dados_treino, configuracao, semente) {
  modas <- aprender_modas(dados_treino, VARIAVEIS_IMPUTADAS)
  dados_tratados <- aplicar_modas(dados_treino, modas)

  modelo <- ranger::ranger(
    dependent.variable.name = VARIAVEL_ALVO,
    data = dados_tratados[, c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO)],
    probability = TRUE,
    num.trees = as.integer(configuracao$numero_arvores),
    mtry = as.integer(configuracao$variaveis_por_divisao),
    min.node.size = 5L,
    splitrule = "gini",
    respect.unordered.factors = "order",
    importance = "none",
    num.threads = NUMERO_THREADS,
    seed = semente
  )

  list(modelo = modelo, modas = modas)
}

prever_random_forest <- function(ajuste, novos_dados) {
  dados_tratados <- aplicar_modas(novos_dados, ajuste$modas)
  probabilidades <- predict(
    ajuste$modelo,
    data = dados_tratados[, VARIAVEIS_PREDITORAS, drop = FALSE],
    num.threads = NUMERO_THREADS
  )$predictions

  as.numeric(probabilidades[, CLASSE_POSITIVA])
}

executar_analise <- function() {
  inicio <- Sys.time()
  cat("\nRANDOM FOREST - HEART DISEASE UCI\n\n")

  dados <- carregar_dados_coracao()
  configuracoes <- expand.grid(
    numero_arvores = c(300L, 500L),
    variaveis_por_divisao = c(3L, 4L),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  configuracoes$id <- sprintf(
    "rf_%d_arvores_mtry_%d",
    configuracoes$numero_arvores,
    configuracoes$variaveis_por_divisao
  )
  configuracoes <- configuracoes[
    , c("id", "numero_arvores", "variaveis_por_divisao")
  ]

  avaliacao <- executar_cv_repetida(
    dados, configuracoes, ajustar_random_forest, prever_random_forest,
    SEMENTE, NUMERO_FOLDS, REPETICOES, LIMIAR
  )

  cat(sprintf("\nAjustes de CV: %d.\n", avaliacao$quantidade_ajustes))
  cat("\nRanking medio das configuracoes:\n")
  print(avaliacao$ranking_configuracoes, row.names = FALSE)
  cat("\nResumo do modelo selecionado:\n")
  mostrar_resumo(avaliacao$resumo_modelo)
  salvar_resultados("random_forest", avaliacao)

  tempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))
  cat(sprintf("\nTempo total: %.2f segundos.\n", tempo))
}

executar_analise()
