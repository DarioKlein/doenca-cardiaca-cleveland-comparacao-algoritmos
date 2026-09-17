#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))
source(file.path("src", "nested", "data.r"))
source(file.path("src", "nested", "models.r"))
source(file.path("src", "nested", "evaluation.r"))

verificar_classes_nos_folds <- function(dados, tabela_folds, coluna_fold) {
  for (fold in sort(unique(tabela_folds[[coluna_fold]]))) {
    ids <- tabela_folds$id_registro[tabela_folds[[coluna_fold]] == fold]
    classes <- dados[[VARIAVEL_ALVO]][match(ids, dados$id_registro)]
    if (length(unique(classes)) != 2L) {
      stop("Um fold foi criado sem as duas classes.", call. = FALSE)
    }
  }
}

gerar_particoes <- function(dados) {
  externos <- list()
  internos <- list()
  posicao_externa <- 1L
  posicao_interna <- 1L

  for (repeticao in seq_along(SEMENTES_EXTERNAS)) {
    folds_externos <- criar_folds_estratificados(
      dados[[VARIAVEL_ALVO]],
      NUMERO_FOLDS_EXTERNOS,
      SEMENTES_EXTERNAS[repeticao]
    )
    tabela_externa <- data.frame(
      Base = BASE_ESTUDO,
      Repeticao = repeticao,
      Semente_Externa = SEMENTES_EXTERNAS[repeticao],
      id_registro = dados$id_registro,
      Fold_Externo = folds_externos
    )
    verificar_classes_nos_folds(dados, tabela_externa, "Fold_Externo")
    externos[[posicao_externa]] <- tabela_externa
    posicao_externa <- posicao_externa + 1L

    for (fold_externo in seq_len(NUMERO_FOLDS_EXTERNOS)) {
      treino <- dados[folds_externos != fold_externo, , drop = FALSE]
      semente_interna <- 310000L + repeticao * 100L + fold_externo
      folds_internos <- criar_folds_estratificados(
        treino[[VARIAVEL_ALVO]], NUMERO_FOLDS_INTERNOS, semente_interna
      )
      tabela_interna <- data.frame(
        Base = BASE_ESTUDO,
        Repeticao = repeticao,
        Fold_Externo = fold_externo,
        Semente_Interna = semente_interna,
        id_registro = treino$id_registro,
        Fold_Interno = folds_internos
      )
      verificar_classes_nos_folds(treino, tabela_interna, "Fold_Interno")
      internos[[posicao_interna]] <- tabela_interna
      posicao_interna <- posicao_interna + 1L
    }
  }
  list(
    externos = do.call(rbind, externos),
    internos = do.call(rbind, internos)
  )
}

gerar_sementes_ajustes <- function() {
  linhas <- list()
  posicao <- 1L
  for (indice_algoritmo in seq_along(ALGORITMOS)) {
    algoritmo <- ALGORITMOS[indice_algoritmo]
    configuracoes <- obter_especificacao_modelo(algoritmo)$configuracoes
    for (repeticao in seq_along(SEMENTES_EXTERNAS)) {
      for (fold_externo in seq_len(NUMERO_FOLDS_EXTERNOS)) {
        for (indice_configuracao in seq_len(nrow(configuracoes))) {
          id <- configuracoes$id[indice_configuracao]
          base_semente <- 10000000L + indice_algoritmo * 1000000L +
            repeticao * 100000L + fold_externo * 10000L +
            indice_configuracao * 100L
          for (fold_interno in seq_len(NUMERO_FOLDS_INTERNOS)) {
            linhas[[posicao]] <- data.frame(
              Algoritmo = algoritmo,
              Repeticao = repeticao,
              Fold_Externo = fold_externo,
              Configuracao = id,
              Fold_Interno = fold_interno,
              Tipo = "interno",
              Semente = base_semente + fold_interno,
              stringsAsFactors = FALSE
            )
            posicao <- posicao + 1L
          }
          linhas[[posicao]] <- data.frame(
            Algoritmo = algoritmo,
            Repeticao = repeticao,
            Fold_Externo = fold_externo,
            Configuracao = id,
            Fold_Interno = 0L,
            Tipo = "reajuste",
            Semente = base_semente + 99L,
            stringsAsFactors = FALSE
          )
          posicao <- posicao + 1L
        }
      }
    }
  }
  do.call(rbind, linhas)
}

preparar_experimento <- function() {
  verificar_diretorio_projeto()
  criar_diretorios_experimento()
  checkpoints <- list.files(DIRETORIO_CHECKPOINTS, pattern = "[.]rds$")
  if (length(checkpoints) > 0L) {
    stop(
      "Existem checkpoints. Nao refaca as particoes durante uma execucao.",
      call. = FALSE
    )
  }

  if (file.exists(ARQUIVO_DADOS_ORIGINAIS)) {
    dados_originais <- readRDS(ARQUIVO_DADOS_ORIGINAIS)
    cat("Copia original existente reutilizada.\n")
  } else {
    if (!requireNamespace("ucimlrepo", quietly = TRUE)) {
      stop("O pacote ucimlrepo nao esta disponivel.", call. = FALSE)
    }
    base_uci <- ucimlrepo::fetch_ucirepo(id = 45L)
    dados_originais <- cbind(
      base_uci$data$features,
      base_uci$data$targets
    )
    validar_dados_originais(dados_originais)
    saveRDS(dados_originais, ARQUIVO_DADOS_ORIGINAIS)
    cat("Base Cleveland obtida da UCI e preservada localmente.\n")
  }

  dados <- preparar_dados_cleveland(dados_originais)
  saveRDS(dados, ARQUIVO_DADOS_PREPARADOS)
  particoes <- gerar_particoes(dados)
  sementes <- gerar_sementes_ajustes()
  plano <- list(
    externos = particoes$externos,
    internos = particoes$internos,
    sementes = sementes
  )
  validar_plano_experimental(plano, dados)

  utils::write.csv(
    particoes$externos, ARQUIVO_FOLDS_EXTERNOS, row.names = FALSE
  )
  utils::write.csv(
    particoes$internos, ARQUIVO_FOLDS_INTERNOS, row.names = FALSE
  )
  utils::write.csv(sementes, ARQUIVO_SEMENTES, row.names = FALSE)

  manifesto <- data.frame(
    Campo = c(
      "Protocolo", "Execucao", "Base", "Fonte_UCI", "Data_Preparacao",
      "Registros", "Preditores", "Classe_Negativa", "Classe_Positiva",
      "Ausencias_CA", "Ausencias_Thal", "Assinatura_Original",
      "Assinatura_Preparado", "Assinatura_Folds_Externos",
      "Assinatura_Folds_Internos", "Assinatura_Sementes", "RNGkind",
      "Versao_R"
    ),
    Valor = c(
      PROTOCOLO, EXECUCAO, BASE_ESTUDO,
      "UCI Machine Learning Repository, dataset 45",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S %z"),
      nrow(dados), length(VARIAVEIS_PREDITORAS),
      sum(dados[[VARIAVEL_ALVO]] == CLASSE_NEGATIVA),
      sum(dados[[VARIAVEL_ALVO]] == CLASSE_POSITIVA),
      sum(is.na(dados$vasos_principais)), sum(is.na(dados$thal)),
      assinatura_arquivo(ARQUIVO_DADOS_ORIGINAIS),
      assinatura_arquivo(ARQUIVO_DADOS_PREPARADOS),
      assinatura_arquivo(ARQUIVO_FOLDS_EXTERNOS),
      assinatura_arquivo(ARQUIVO_FOLDS_INTERNOS),
      assinatura_arquivo(ARQUIVO_SEMENTES),
      paste(RNGkind(), collapse = "/"), R.version.string
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    manifesto,
    file.path(DIRETORIO_MANIFESTO, "preparacao_manifesto.csv"),
    row.names = FALSE
  )
  writeLines(
    utils::capture.output(sessionInfo()),
    file.path(DIRETORIO_MANIFESTO, "preparacao_session_info.txt")
  )
  cat(sprintf(
    "Experimento preparado: %d registros, %d particoes externas.\n",
    nrow(dados),
    length(unique(interaction(
      particoes$externos$Repeticao,
      particoes$externos$Fold_Externo
    )))
  ))
}

preparar_experimento()
