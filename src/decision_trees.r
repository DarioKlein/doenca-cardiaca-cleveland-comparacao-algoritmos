#!/usr/bin/env Rscript

SEMENTE <- 20260804L
REPETICOES <- 3L
NUMERO_FOLDS <- 5L
LIMIAR <- 0.5

source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))

ajustar_arvore <- function(dados_treino, configuracao, semente) {
  set.seed(semente)
  rpart::rpart(
    formula = stats::reformulate(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO),
    data = dados_treino[, c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO)],
    method = "class",
    parms = list(split = "gini"),
    control = rpart::rpart.control(
      cp = configuracao$cp,
      minsplit = 20L,
      maxdepth = as.integer(configuracao$profundidade_maxima),
      xval = 0L
    )
  )
}

prever_arvore <- function(modelo, novos_dados) {
  probabilidades <- predict(
    modelo,
    newdata = novos_dados[, VARIAVEIS_PREDITORAS, drop = FALSE],
    type = "prob"
  )
  as.numeric(probabilidades[, CLASSE_POSITIVA])
}

executar_analise <- function() {
  inicio <- Sys.time()
  cat("\nARVORE DE DECISAO - HEART DISEASE UCI\n\n")

  dados <- carregar_dados_coracao()
  configuracoes <- expand.grid(
    cp = c(0.005, 0.01, 0.02),
    profundidade_maxima = c(3L, 5L),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  configuracoes$id <- sprintf(
    "arvore_cp_%s_profundidade_%d",
    configuracoes$cp,
    configuracoes$profundidade_maxima
  )
  configuracoes <- configuracoes[, c("id", "cp", "profundidade_maxima")]

  avaliacao <- executar_cv_repetida(
    dados, configuracoes, ajustar_arvore, prever_arvore,
    SEMENTE, NUMERO_FOLDS, REPETICOES, LIMIAR
  )

  cat(sprintf("\nAjustes de CV: %d.\n", avaliacao$quantidade_ajustes))
  cat("\nRanking medio das configuracoes:\n")
  print(avaliacao$ranking_configuracoes, row.names = FALSE)
  cat("\nResumo do modelo selecionado:\n")
  mostrar_resumo(avaliacao$resumo_modelo)
  salvar_resultados("decision_trees", avaliacao)

  tempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))
  cat(sprintf("\nTempo total: %.2f segundos.\n", tempo))
}

executar_analise()
