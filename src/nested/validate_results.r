#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))
source(file.path("src", "nested", "data.r"))
source(file.path("src", "nested", "models.r"))
source(file.path("src", "nested", "evaluation.r"))

ler_resultado <- function(algoritmo, sufixo) {
  caminho <- file.path(
    DIRETORIO_CSV, paste0(algoritmo, "_", sufixo, ".csv")
  )
  if (!file.exists(caminho)) {
    stop("Resultado ausente: ", caminho, call. = FALSE)
  }
  utils::read.csv(caminho, stringsAsFactors = FALSE)
}

validar_identificacao <- function(tabela, algoritmo, nome) {
  campos <- c("Protocolo", "Execucao", "Base", "Algoritmo")
  if (!all(campos %in% names(tabela)) ||
      !identical(unique(tabela$Protocolo), PROTOCOLO) ||
      !identical(unique(tabela$Execucao), EXECUCAO) ||
      !identical(unique(tabela$Base), BASE_ESTUDO) ||
      !identical(unique(tabela$Algoritmo), algoritmo)) {
    stop("Identificacao invalida em ", nome, call. = FALSE)
  }
}

validar_algoritmo <- function(algoritmo, dados, plano) {
  configuracoes <- obter_especificacao_modelo(algoritmo)$configuracoes
  quantidade_configuracoes <- nrow(configuracoes)
  tabelas <- list(
    internas = ler_resultado(algoritmo, "ncv_metricas_internas"),
    ranking = ler_resultado(algoritmo, "ncv_ranking_interno"),
    folds = ler_resultado(algoritmo, "ncv_resultados_folds"),
    selecoes = ler_resultado(
      algoritmo, "ncv_configuracoes_selecionadas"
    ),
    frequencias = ler_resultado(
      algoritmo, "ncv_frequencia_configuracoes"
    ),
    predicoes = ler_resultado(algoritmo, "ncv_predicoes_oof"),
    resumo = ler_resultado(algoritmo, "ncv_resumo_modelo"),
    oof = ler_resultado(algoritmo, "ncv_resultados_repeticoes_oof")
  )
  for (nome in names(tabelas)) {
    validar_identificacao(tabelas[[nome]], algoritmo, nome)
  }

  esperados <- c(
    internas = 15L * 3L * quantidade_configuracoes,
    ranking = 15L * quantidade_configuracoes,
    folds = 15L,
    selecoes = 15L,
    predicoes = 909L,
    resumo = length(c(NOMES_METRICAS, NOMES_TEMPOS)),
    oof = 3L
  )
  observados <- vapply(
    names(esperados), function(nome) nrow(tabelas[[nome]]), integer(1)
  )
  if (!all(observados == esperados)) {
    stop("Contagem invalida nos resultados de ", algoritmo, call. = FALSE)
  }
  if (sum(tabelas$frequencias$Frequencia) != 15L) {
    stop("Frequencias de configuracao invalidas em ", algoritmo, call. = FALSE)
  }
  if (anyDuplicated(tabelas$folds[c("Repeticao", "Fold_Externo")]) ||
      any(tabelas$folds$Status != "completo")) {
    stop("Folds externos incompletos em ", algoritmo, call. = FALSE)
  }
  if (any(!tabelas$folds$Configuracao_Selecionada %in% configuracoes$id) ||
      any(!tabelas$selecoes$Configuracao_Selecionada %in% configuracoes$id)) {
    stop("Configuracao selecionada invalida em ", algoritmo, call. = FALSE)
  }

  predicoes <- tabelas$predicoes
  validar_probabilidades(predicoes$probabilidade_doenca, 909L)
  if (anyDuplicated(predicoes[c("Repeticao", "id_registro")])) {
    stop("Predicoes OOF duplicadas em ", algoritmo, call. = FALSE)
  }
  for (repeticao in seq_along(SEMENTES_EXTERNAS)) {
    parte <- predicoes[predicoes$Repeticao == repeticao, ]
    if (nrow(parte) != nrow(dados) ||
        !setequal(parte$id_registro, dados$id_registro)) {
      stop("Cobertura OOF invalida em ", algoritmo, call. = FALSE)
    }
    esperado <- plano$externos[plano$externos$Repeticao == repeticao, ]
    esperado <- esperado[match(parte$id_registro, esperado$id_registro), ]
    if (!identical(parte$Fold_Externo, esperado$Fold_Externo)) {
      stop("Predicoes nao correspondem aos folds preparados.", call. = FALSE)
    }
  }
  if (any(!is.finite(as.matrix(tabelas$folds[NOMES_METRICAS])))) {
    stop("Metricas externas invalidas em ", algoritmo, call. = FALSE)
  }
  tabelas
}

validar_todos_resultados <- function() {
  verificar_diretorio_projeto()
  dados <- carregar_dados_preparados()
  plano <- carregar_plano_experimental(dados)
  resultados <- lapply(ALGORITMOS, validar_algoritmo, dados = dados, plano = plano)
  names(resultados) <- ALGORITMOS

  chave_referencia <- resultados[[1L]]$folds[c("Repeticao", "Fold_Externo")]
  for (algoritmo in ALGORITMOS[-1L]) {
    chave <- resultados[[algoritmo]]$folds[c("Repeticao", "Fold_Externo")]
    if (!identical(chave, chave_referencia)) {
      stop("Os algoritmos nao possuem o mesmo pareamento externo.", call. = FALSE)
    }
  }

  relatorio <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Algoritmo = ALGORITMOS,
    Folds_Externos = vapply(
      resultados, function(x) nrow(x$folds), integer(1)
    ),
    Predicoes_OOF = vapply(
      resultados, function(x) nrow(x$predicoes), integer(1)
    ),
    Status = "valido",
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    relatorio,
    file.path(DIRETORIO_MANIFESTO, "validacao_resultados.csv"),
    row.names = FALSE
  )
  cat("Resultados completos, integros e pareados.\n")
  print(relatorio, row.names = FALSE)
  invisible(resultados)
}

validar_todos_resultados()
