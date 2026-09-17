aprender_modas <- function(dados_treino, variaveis) {
  vapply(variaveis, function(variavel) {
    contagens <- table(dados_treino[[variavel]], useNA = "no")
    if (length(contagens) == 0L) {
      stop("Nao foi possivel aprender a moda de ", variavel, call. = FALSE)
    }
    names(contagens)[which.max(contagens)]
  }, character(1))
}

aplicar_modas <- function(dados, modas) {
  dados_tratados <- dados
  for (variavel in names(modas)) {
    valores <- dados_tratados[[variavel]]
    valores[is.na(valores)] <- modas[[variavel]]
    dados_tratados[[variavel]] <- valores
  }
  dados_tratados
}

configuracoes_naive_bayes <- function() {
  data.frame(
    id = c("gaussiano", "kde"),
    laplace = c(1, 1),
    usar_kernel = c(FALSE, TRUE),
    ajuste = c(NA_real_, 1),
    stringsAsFactors = FALSE
  )
}

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

configuracoes_arvore <- function() {
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
  configuracoes[, c("id", "cp", "profundidade_maxima")]
}

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

configuracoes_random_forest <- function() {
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
  configuracoes[, c("id", "numero_arvores", "variaveis_por_divisao")]
}

ajustar_random_forest <- function(dados_treino, configuracao, semente) {
  modas <- aprender_modas(dados_treino, c("vasos_principais", "thal"))
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
    num.threads = 1L,
    seed = semente
  )
  list(modelo = modelo, modas = modas)
}

prever_random_forest <- function(ajuste, novos_dados) {
  dados_tratados <- aplicar_modas(novos_dados, ajuste$modas)
  probabilidades <- predict(
    ajuste$modelo,
    data = dados_tratados[, VARIAVEIS_PREDITORAS, drop = FALSE],
    num.threads = 1L
  )$predictions
  as.numeric(probabilidades[, CLASSE_POSITIVA])
}

configuracoes_svm <- function() {
  data.frame(
    id = c("svm_custo_0.1", "svm_custo_1", "svm_custo_10"),
    custo = c(0.1, 1, 10),
    stringsAsFactors = FALSE
  )
}

aprender_pre_processamento_svm <- function(dados_treino) {
  modas <- aprender_modas(dados_treino, c("vasos_principais", "thal"))
  dados_tratados <- aplicar_modas(dados_treino, modas)
  medias <- vapply(dados_tratados[VARIAVEIS_NUMERICAS], mean, numeric(1))
  desvios <- vapply(
    dados_tratados[VARIAVEIS_NUMERICAS], stats::sd, numeric(1)
  )
  desvios[!is.finite(desvios) | desvios == 0] <- 1
  list(modas = modas, medias = medias, desvios = desvios)
}

aplicar_pre_processamento_svm <- function(dados, pre_processamento) {
  dados_tratados <- aplicar_modas(dados, pre_processamento$modas)
  for (variavel in VARIAVEIS_NUMERICAS) {
    dados_tratados[[variavel]] <- (
      dados_tratados[[variavel]] - pre_processamento$medias[[variavel]]
    ) / pre_processamento$desvios[[variavel]]
  }
  dados_tratados
}

ajustar_svm <- function(dados_treino, configuracao, semente) {
  pre_processamento <- aprender_pre_processamento_svm(dados_treino)
  dados_tratados <- aplicar_pre_processamento_svm(
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
  dados_tratados <- aplicar_pre_processamento_svm(
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

obter_especificacao_modelo <- function(algoritmo) {
  especificacoes <- list(
    naive_bayes = list(
      configuracoes = configuracoes_naive_bayes(),
      ajustar = ajustar_naive_bayes,
      prever = prever_naive_bayes
    ),
    decision_trees = list(
      configuracoes = configuracoes_arvore(),
      ajustar = ajustar_arvore,
      prever = prever_arvore
    ),
    random_forest = list(
      configuracoes = configuracoes_random_forest(),
      ajustar = ajustar_random_forest,
      prever = prever_random_forest
    ),
    svm = list(
      configuracoes = configuracoes_svm(),
      ajustar = ajustar_svm,
      prever = prever_svm
    )
  )
  if (!algoritmo %in% names(especificacoes)) {
    stop("Algoritmo desconhecido: ", algoritmo, call. = FALSE)
  }
  especificacoes[[algoritmo]]
}
