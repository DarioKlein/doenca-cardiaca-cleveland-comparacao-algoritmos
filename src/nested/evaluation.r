NOMES_METRICAS <- c(
  "Acuracia", "Sensibilidade", "Especificidade", "Precisao", "F1", "MCC",
  "ROC_AUC", "Brier", "Log_Loss", "Acuracia_Balanceada"
)

NOMES_TEMPOS <- c(
  "Tempo_Selecao_Segundos", "Tempo_Reajuste_Segundos",
  "Tempo_Predicao_Segundos", "Tempo_Total_Fold_Segundos"
)

criar_folds_estratificados <- function(classe, numero_folds, semente) {
  set.seed(semente)
  folds <- integer(length(classe))
  indices_por_classe <- split(seq_along(classe), classe)
  quantidade_por_fold <- integer(numero_folds)

  for (indices in indices_por_classe) {
    indices <- indices[sample.int(length(indices))]
    quantidades <- rep(length(indices) %/% numero_folds, numero_folds)
    sobras <- length(indices) %% numero_folds
    if (sobras > 0L) {
      prioridade <- order(quantidade_por_fold, stats::runif(numero_folds))
      quantidades[prioridade[seq_len(sobras)]] <-
        quantidades[prioridade[seq_len(sobras)]] + 1L
    }
    folds[indices] <- rep(seq_len(numero_folds), times = quantidades)
    quantidade_por_fold <- quantidade_por_fold + quantidades
  }
  folds
}

calcular_auc_roc <- function(classe_real, probabilidade) {
  positivos <- classe_real == CLASSE_POSITIVA
  quantidade_positivos <- sum(positivos)
  quantidade_negativos <- length(positivos) - quantidade_positivos
  if (quantidade_positivos == 0L || quantidade_negativos == 0L) {
    return(NA_real_)
  }
  postos <- rank(probabilidade, ties.method = "average")
  (sum(postos[positivos]) - quantidade_positivos *
     (quantidade_positivos + 1) / 2) /
    (quantidade_positivos * quantidade_negativos)
}

validar_probabilidades <- function(probabilidade, quantidade_esperada) {
  if (length(probabilidade) != quantidade_esperada ||
      any(!is.finite(probabilidade)) ||
      any(probabilidade < 0 | probabilidade > 1)) {
    stop("Probabilidades invalidas produzidas pelo modelo.", call. = FALSE)
  }
  invisible(TRUE)
}

calcular_metricas <- function(classe_real, probabilidade, limiar = LIMIAR) {
  validar_probabilidades(probabilidade, length(classe_real))
  classe_real <- factor(
    classe_real, levels = c(CLASSE_NEGATIVA, CLASSE_POSITIVA)
  )
  classe_prevista <- factor(
    ifelse(probabilidade >= limiar, CLASSE_POSITIVA, CLASSE_NEGATIVA),
    levels = c(CLASSE_NEGATIVA, CLASSE_POSITIVA)
  )

  vp <- sum(classe_prevista == CLASSE_POSITIVA & classe_real == CLASSE_POSITIVA)
  vn <- sum(classe_prevista == CLASSE_NEGATIVA & classe_real == CLASSE_NEGATIVA)
  fp <- sum(classe_prevista == CLASSE_POSITIVA & classe_real == CLASSE_NEGATIVA)
  fn <- sum(classe_prevista == CLASSE_NEGATIVA & classe_real == CLASSE_POSITIVA)
  if ((vp + fn) == 0L || (vn + fp) == 0L) {
    stop("O conjunto avaliado precisa conter as duas classes.", call. = FALSE)
  }

  sensibilidade <- vp / (vp + fn)
  especificidade <- vn / (vn + fp)
  precisao_zero <- (vp + fp) == 0L
  precisao <- if (precisao_zero) 0 else vp / (vp + fp)
  denominador_f1 <- 2 * vp + fp + fn
  f1 <- if (denominador_f1 == 0L) 0 else 2 * vp / denominador_f1
  denominador_mcc <- sqrt(prod(as.numeric(c(
    vp + fp, vp + fn, vn + fp, vn + fn
  ))))
  mcc_zero <- denominador_mcc == 0
  mcc <- if (mcc_zero) 0 else (vp * vn - fp * fn) / denominador_mcc

  classe_binaria <- as.numeric(classe_real == CLASSE_POSITIVA)
  probabilidade_segura <- pmin(
    pmax(probabilidade, .Machine$double.eps), 1 - .Machine$double.eps
  )
  c(
    Acuracia = (vp + vn) / length(classe_real),
    Sensibilidade = sensibilidade,
    Especificidade = especificidade,
    Precisao = precisao,
    F1 = f1,
    MCC = mcc,
    ROC_AUC = calcular_auc_roc(classe_real, probabilidade),
    Brier = mean((probabilidade - classe_binaria)^2),
    Log_Loss = -mean(
      classe_binaria * log(probabilidade_segura) +
        (1 - classe_binaria) * log1p(-probabilidade_segura)
    ),
    Acuracia_Balanceada = (sensibilidade + especificidade) / 2,
    VP = vp, VN = vn, FP = fp, FN = fn,
    Precisao_Denominador_Zero = as.integer(precisao_zero),
    MCC_Denominador_Zero = as.integer(mcc_zero)
  )
}

carregar_plano_experimental <- function(dados) {
  arquivos <- c(
    ARQUIVO_FOLDS_EXTERNOS, ARQUIVO_FOLDS_INTERNOS, ARQUIVO_SEMENTES
  )
  ausentes <- arquivos[!file.exists(arquivos)]
  if (length(ausentes) > 0L) {
    stop(
      "Plano experimental ausente. Execute prepare_experiment.r primeiro.",
      call. = FALSE
    )
  }
  plano <- list(
    externos = utils::read.csv(ARQUIVO_FOLDS_EXTERNOS),
    internos = utils::read.csv(ARQUIVO_FOLDS_INTERNOS),
    sementes = utils::read.csv(ARQUIVO_SEMENTES, stringsAsFactors = FALSE)
  )
  validar_plano_experimental(plano, dados)
  plano
}

validar_plano_experimental <- function(plano, dados) {
  externos <- plano$externos
  internos <- plano$internos
  sementes <- plano$sementes
  ids <- dados$id_registro

  for (repeticao in seq_along(SEMENTES_EXTERNAS)) {
    parte <- externos[externos$Repeticao == repeticao, ]
    if (nrow(parte) != nrow(dados) ||
        !setequal(parte$id_registro, ids) ||
        anyDuplicated(parte$id_registro) ||
        !setequal(parte$Fold_Externo, seq_len(NUMERO_FOLDS_EXTERNOS))) {
      stop("Plano externo invalido na repeticao ", repeticao, call. = FALSE)
    }
    for (fold_externo in seq_len(NUMERO_FOLDS_EXTERNOS)) {
      teste <- parte$id_registro[parte$Fold_Externo == fold_externo]
      treino <- setdiff(ids, teste)
      plano_interno <- internos[
        internos$Repeticao == repeticao &
          internos$Fold_Externo == fold_externo, ]
      if (nrow(plano_interno) != length(treino) ||
          !setequal(plano_interno$id_registro, treino) ||
          anyDuplicated(plano_interno$id_registro) ||
          !setequal(
            plano_interno$Fold_Interno, seq_len(NUMERO_FOLDS_INTERNOS)
          )) {
        stop(
          "Plano interno invalido na repeticao/fold ",
          repeticao, "/", fold_externo,
          call. = FALSE
        )
      }
    }
  }

  chave_semente <- c(
    "Algoritmo", "Repeticao", "Fold_Externo", "Configuracao",
    "Fold_Interno", "Tipo"
  )
  if (!all(chave_semente %in% names(sementes)) ||
      anyDuplicated(sementes[chave_semente]) ||
      anyDuplicated(sementes$Semente) ||
      any(!sementes$Tipo %in% c("interno", "reajuste"))) {
    stop("O plano de sementes e invalido.", call. = FALSE)
  }
  for (algoritmo in ALGORITMOS) {
    quantidade_configuracoes <- nrow(
      obter_especificacao_modelo(algoritmo)$configuracoes
    )
    esperado <- 15L * quantidade_configuracoes * 4L
    if (sum(sementes$Algoritmo == algoritmo) != esperado) {
      stop("Quantidade de sementes invalida para ", algoritmo, call. = FALSE)
    }
  }
  invisible(TRUE)
}

obter_semente <- function(plano, algoritmo, repeticao, fold_externo,
                          configuracao, fold_interno, tipo) {
  linhas <- plano$sementes[
    plano$sementes$Algoritmo == algoritmo &
      plano$sementes$Repeticao == repeticao &
      plano$sementes$Fold_Externo == fold_externo &
      plano$sementes$Configuracao == configuracao &
      plano$sementes$Fold_Interno == fold_interno &
      plano$sementes$Tipo == tipo, ]
  if (nrow(linhas) != 1L) {
    stop("Semente ausente ou duplicada no plano.", call. = FALSE)
  }
  as.integer(linhas$Semente[1L])
}

avaliar_configuracao_interna <- function(
    algoritmo, especificacao, configuracao, dados_treino_externo,
    folds_internos, plano, repeticao, fold_externo) {
  resultados <- vector("list", NUMERO_FOLDS_INTERNOS)
  for (fold_interno in seq_len(NUMERO_FOLDS_INTERNOS)) {
    ids_validacao <- folds_internos$id_registro[
      folds_internos$Fold_Interno == fold_interno
    ]
    posicoes_validacao <- match(ids_validacao, dados_treino_externo$id_registro)
    dados_validacao <- dados_treino_externo[posicoes_validacao, , drop = FALSE]
    dados_treino <- dados_treino_externo[-posicoes_validacao, , drop = FALSE]
    if (length(intersect(
      dados_treino$id_registro, dados_validacao$id_registro
    )) > 0L) {
      stop("Vazamento entre treino e validacao interna.", call. = FALSE)
    }

    semente <- obter_semente(
      plano, algoritmo, repeticao, fold_externo,
      configuracao$id, fold_interno, "interno"
    )
    ajuste <- especificacao$ajustar(dados_treino, configuracao, semente)
    probabilidades <- especificacao$prever(ajuste, dados_validacao)
    metricas <- calcular_metricas(
      dados_validacao[[VARIAVEL_ALVO]], probabilidades
    )
    resultados[[fold_interno]] <- cbind(
      data.frame(
        Protocolo = PROTOCOLO,
        Execucao = EXECUCAO,
        Base = BASE_ESTUDO,
        Algoritmo = algoritmo,
        Repeticao = repeticao,
        Fold_Externo = fold_externo,
        Fold_Interno = fold_interno,
        Semente = semente,
        Configuracao = configuracao$id,
        stringsAsFactors = FALSE
      ),
      configuracao[setdiff(names(configuracao), "id")],
      as.data.frame(as.list(metricas), check.names = FALSE)
    )
  }
  do.call(rbind, resultados)
}

criar_ranking_interno <- function(metricas_internas, configuracoes,
                                  repeticao, fold_externo, algoritmo) {
  agregados <- lapply(configuracoes$id, function(id) {
    linhas <- metricas_internas$Configuracao == id
    valores <- metricas_internas[linhas, NOMES_METRICAS, drop = FALSE]
    if (nrow(valores) != NUMERO_FOLDS_INTERNOS ||
        any(!is.finite(as.matrix(valores)))) {
      stop("Metricas internas incompletas para ", id, call. = FALSE)
    }
    data.frame(
      Configuracao = id,
      t(vapply(valores, mean, numeric(1))),
      row.names = NULL,
      check.names = FALSE
    )
  })
  agregados <- do.call(rbind, agregados)
  names(agregados)[-1L] <- paste0(names(agregados)[-1L], "_Media")
  ranking <- merge(
    configuracoes, agregados,
    by.x = "id", by.y = "Configuracao", sort = FALSE
  )
  ordem <- order(
    -ranking$MCC_Media, -ranking$F1_Media,
    -ranking$ROC_AUC_Media, ranking$id
  )
  ranking <- ranking[ordem, , drop = FALSE]
  ranking$Posicao <- seq_len(nrow(ranking))
  ranking$Selecionada <- ranking$Posicao == 1L
  cbind(
    data.frame(
      Protocolo = PROTOCOLO,
      Execucao = EXECUCAO,
      Base = BASE_ESTUDO,
      Algoritmo = algoritmo,
      Repeticao = repeticao,
      Fold_Externo = fold_externo,
      stringsAsFactors = FALSE
    ),
    ranking
  )
}

avaliar_fold_externo <- function(algoritmo, especificacao, dados, plano,
                                 repeticao, fold_externo) {
  inicio_total <- Sys.time()
  folds_externos <- plano$externos[
    plano$externos$Repeticao == repeticao, ]
  ids_teste <- folds_externos$id_registro[
    folds_externos$Fold_Externo == fold_externo
  ]
  posicoes_teste <- match(ids_teste, dados$id_registro)
  dados_teste <- dados[posicoes_teste, , drop = FALSE]
  dados_treino_externo <- dados[-posicoes_teste, , drop = FALSE]
  if (length(intersect(
    dados_treino_externo$id_registro, dados_teste$id_registro
  )) > 0L) {
    stop("Vazamento entre treino e teste externo.", call. = FALSE)
  }
  folds_internos <- plano$internos[
    plano$internos$Repeticao == repeticao &
      plano$internos$Fold_Externo == fold_externo, ]

  inicio_selecao <- Sys.time()
  metricas_internas <- lapply(
    seq_len(nrow(especificacao$configuracoes)),
    function(indice) {
      avaliar_configuracao_interna(
        algoritmo, especificacao,
        especificacao$configuracoes[indice, , drop = FALSE],
        dados_treino_externo, folds_internos, plano,
        repeticao, fold_externo
      )
    }
  )
  metricas_internas <- do.call(rbind, metricas_internas)
  ranking <- criar_ranking_interno(
    metricas_internas, especificacao$configuracoes,
    repeticao, fold_externo, algoritmo
  )
  tempo_selecao <- as.numeric(difftime(
    Sys.time(), inicio_selecao, units = "secs"
  ))

  melhor_id <- ranking$id[1L]
  indice_melhor <- match(melhor_id, especificacao$configuracoes$id)
  configuracao <- especificacao$configuracoes[
    indice_melhor, , drop = FALSE
  ]
  semente_reajuste <- obter_semente(
    plano, algoritmo, repeticao, fold_externo,
    melhor_id, 0L, "reajuste"
  )

  inicio_reajuste <- Sys.time()
  ajuste <- especificacao$ajustar(
    dados_treino_externo, configuracao, semente_reajuste
  )
  tempo_reajuste <- as.numeric(difftime(
    Sys.time(), inicio_reajuste, units = "secs"
  ))

  inicio_predicao <- Sys.time()
  probabilidades <- especificacao$prever(ajuste, dados_teste)
  validar_probabilidades(probabilidades, nrow(dados_teste))
  tempo_predicao <- as.numeric(difftime(
    Sys.time(), inicio_predicao, units = "secs"
  ))
  metricas <- calcular_metricas(
    dados_teste[[VARIAVEL_ALVO]], probabilidades
  )
  tempo_total <- as.numeric(difftime(
    Sys.time(), inicio_total, units = "secs"
  ))

  metadados <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Algoritmo = algoritmo,
    Repeticao = repeticao,
    Fold_Externo = fold_externo,
    Semente_Externa = SEMENTES_EXTERNAS[repeticao],
    Semente_Interna = unique(folds_internos$Semente_Interna),
    Semente_Reajuste = semente_reajuste,
    N_Treino_Externo = nrow(dados_treino_externo),
    N_Teste_Externo = nrow(dados_teste),
    Configuracao_Selecionada = melhor_id,
    MCC_Interno_Medio = ranking$MCC_Media[1L],
    stringsAsFactors = FALSE
  )
  resultado_fold <- cbind(
    metadados,
    as.data.frame(as.list(metricas), check.names = FALSE),
    data.frame(
      Tempo_Selecao_Segundos = tempo_selecao,
      Tempo_Reajuste_Segundos = tempo_reajuste,
      Tempo_Predicao_Segundos = tempo_predicao,
      Tempo_Total_Fold_Segundos = tempo_total,
      Status = "completo",
      stringsAsFactors = FALSE
    )
  )
  selecionada <- cbind(
    metadados,
    configuracao[setdiff(names(configuracao), "id")]
  )
  predicoes <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Algoritmo = algoritmo,
    Repeticao = repeticao,
    Fold_Externo = fold_externo,
    Configuracao_Selecionada = melhor_id,
    id_registro = dados_teste$id_registro,
    classe_real = as.character(dados_teste[[VARIAVEL_ALVO]]),
    probabilidade_doenca = probabilidades,
    classe_prevista = ifelse(
      probabilidades >= LIMIAR, CLASSE_POSITIVA, CLASSE_NEGATIVA
    ),
    stringsAsFactors = FALSE
  )
  list(
    metricas_internas = metricas_internas,
    ranking_interno = ranking,
    resultado_fold = resultado_fold,
    configuracao_selecionada = selecionada,
    predicoes = predicoes
  )
}

assinatura_codigo_nested <- function() {
  arquivos <- file.path(
    "src", "nested",
    c("config.r", "data.r", "models.r", "evaluation.r")
  )
  paste(unname(tools::md5sum(arquivos)), collapse = ":")
}

salvar_checkpoint <- function(checkpoint, caminho) {
  temporario <- tempfile("checkpoint_", tmpdir = dirname(caminho))
  saveRDS(checkpoint, temporario)
  if (!file.rename(temporario, caminho)) {
    unlink(temporario)
    stop("Nao foi possivel finalizar o checkpoint.", call. = FALSE)
  }
}

obter_checkpoint <- function(algoritmo, especificacao, dados, plano,
                             repeticao, fold_externo) {
  caminho <- file.path(
    DIRETORIO_CHECKPOINTS,
    sprintf("%s_rep_%d_fold_%d.rds", algoritmo, repeticao, fold_externo)
  )
  identificacao <- list(
    protocolo = PROTOCOLO,
    execucao = EXECUCAO,
    algoritmo = algoritmo,
    repeticao = repeticao,
    fold_externo = fold_externo,
    assinatura_dados = assinatura_arquivo(ARQUIVO_DADOS_PREPARADOS),
    assinatura_particoes = paste(
      assinatura_arquivo(ARQUIVO_FOLDS_EXTERNOS),
      assinatura_arquivo(ARQUIVO_FOLDS_INTERNOS),
      assinatura_arquivo(ARQUIVO_SEMENTES),
      sep = ":"
    ),
    assinatura_codigo = assinatura_codigo_nested()
  )
  if (file.exists(caminho)) {
    checkpoint <- readRDS(caminho)
    if (!identical(checkpoint$identificacao, identificacao)) {
      stop(
        "Checkpoint incompativel: ", caminho,
        ". Remova-o somente depois de conferir o protocolo.",
        call. = FALSE
      )
    }
    cat(sprintf(
      "Repeticao %d, fold %d recuperado do checkpoint.\n",
      repeticao, fold_externo
    ))
    return(checkpoint$resultados)
  }
  resultados <- avaliar_fold_externo(
    algoritmo, especificacao, dados, plano, repeticao, fold_externo
  )
  salvar_checkpoint(
    list(identificacao = identificacao, resultados = resultados), caminho
  )
  cat(sprintf(
    "Repeticao %d, fold %d concluido.\n", repeticao, fold_externo
  ))
  resultados
}

resumir_resultados_externos <- function(resultados) {
  colunas <- c(NOMES_METRICAS, NOMES_TEMPOS)
  if (any(!is.finite(as.matrix(resultados[colunas])))) {
    stop("Resultados externos possuem valores invalidos.", call. = FALSE)
  }
  data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Metrica = colunas,
    Media = vapply(resultados[colunas], mean, numeric(1)),
    DP = vapply(resultados[colunas], stats::sd, numeric(1)),
    N_Avaliacoes = nrow(resultados),
    Unidade_Agregacao = "fold_externo",
    row.names = NULL
  )
}

resumir_predicoes_oof <- function(predicoes) {
  resultados <- lapply(seq_along(SEMENTES_EXTERNAS), function(repeticao) {
    parte <- predicoes[predicoes$Repeticao == repeticao, ]
    if (nrow(parte) != 303L || anyDuplicated(parte$id_registro)) {
      stop("Predicoes OOF incompletas na repeticao ", repeticao, call. = FALSE)
    }
    parte <- parte[order(parte$id_registro), ]
    metricas <- calcular_metricas(
      parte$classe_real, parte$probabilidade_doenca
    )
    cbind(
      data.frame(
        Protocolo = PROTOCOLO,
        Execucao = EXECUCAO,
        Base = BASE_ESTUDO,
        Algoritmo = unique(parte$Algoritmo),
        Repeticao = repeticao,
        Semente_Externa = SEMENTES_EXTERNAS[repeticao],
        stringsAsFactors = FALSE
      ),
      as.data.frame(as.list(metricas), check.names = FALSE)
    )
  })
  do.call(rbind, resultados)
}

salvar_tabela <- function(tabela, algoritmo, sufixo) {
  caminho <- file.path(
    DIRETORIO_CSV, paste0(algoritmo, "_", sufixo, ".csv")
  )
  utils::write.csv(tabela, caminho, row.names = FALSE)
  caminho
}

salvar_manifesto_algoritmo <- function(algoritmo, inicio, fim,
                                       quantidade_ajustes) {
  manifesto <- data.frame(
    Campo = c(
      "Protocolo", "Execucao", "Base", "Algoritmo",
      "Assinatura_Dados", "Assinatura_Folds_Externos",
      "Assinatura_Folds_Internos", "Assinatura_Sementes",
      "Assinatura_Codigo", "RNGkind", "Versao_R", "Inicio", "Fim",
      "Quantidade_Ajustes", "Status"
    ),
    Valor = c(
      PROTOCOLO, EXECUCAO, BASE_ESTUDO, algoritmo,
      assinatura_arquivo(ARQUIVO_DADOS_PREPARADOS),
      assinatura_arquivo(ARQUIVO_FOLDS_EXTERNOS),
      assinatura_arquivo(ARQUIVO_FOLDS_INTERNOS),
      assinatura_arquivo(ARQUIVO_SEMENTES),
      assinatura_codigo_nested(), paste(RNGkind(), collapse = "/"),
      R.version.string, format(inicio, "%Y-%m-%d %H:%M:%S %z"),
      format(fim, "%Y-%m-%d %H:%M:%S %z"), quantidade_ajustes, "completo"
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    manifesto,
    file.path(DIRETORIO_MANIFESTO, paste0(algoritmo, "_manifesto.csv")),
    row.names = FALSE
  )
  captura <- utils::capture.output(sessionInfo())
  writeLines(
    captura,
    file.path(DIRETORIO_MANIFESTO, paste0(algoritmo, "_session_info.txt"))
  )
}

executar_cv_aninhada <- function(algoritmo) {
  verificar_diretorio_projeto()
  criar_diretorios_experimento()
  inicio <- Sys.time()
  dados <- carregar_dados_preparados()
  plano <- carregar_plano_experimental(dados)
  especificacao <- obter_especificacao_modelo(algoritmo)
  resultados <- list()
  posicao <- 1L

  for (repeticao in seq_along(SEMENTES_EXTERNAS)) {
    for (fold_externo in seq_len(NUMERO_FOLDS_EXTERNOS)) {
      resultados[[posicao]] <- obter_checkpoint(
        algoritmo, especificacao, dados, plano, repeticao, fold_externo
      )
      posicao <- posicao + 1L
    }
  }

  metricas_internas <- do.call(rbind, lapply(
    resultados, `[[`, "metricas_internas"
  ))
  ranking_interno <- do.call(rbind, lapply(
    resultados, `[[`, "ranking_interno"
  ))
  resultados_folds <- do.call(rbind, lapply(
    resultados, `[[`, "resultado_fold"
  ))
  configuracoes_selecionadas <- do.call(rbind, lapply(
    resultados, `[[`, "configuracao_selecionada"
  ))
  predicoes <- do.call(rbind, lapply(resultados, `[[`, "predicoes"))

  frequencias <- as.data.frame(
    table(configuracoes_selecionadas$Configuracao_Selecionada),
    stringsAsFactors = FALSE
  )
  names(frequencias) <- c("Configuracao", "Frequencia")
  frequencias <- cbind(
    data.frame(
      Protocolo = PROTOCOLO,
      Execucao = EXECUCAO,
      Base = BASE_ESTUDO,
      Algoritmo = algoritmo,
      stringsAsFactors = FALSE
    ),
    frequencias
  )
  resumo <- resumir_resultados_externos(resultados_folds)
  resumo$Algoritmo <- algoritmo
  resumo <- resumo[, c(
    "Protocolo", "Execucao", "Base", "Algoritmo", "Metrica", "Media",
    "DP", "N_Avaliacoes", "Unidade_Agregacao"
  )]
  resultados_oof <- resumir_predicoes_oof(predicoes)

  arquivos <- c(
    salvar_tabela(metricas_internas, algoritmo, "ncv_metricas_internas"),
    salvar_tabela(ranking_interno, algoritmo, "ncv_ranking_interno"),
    salvar_tabela(resultados_folds, algoritmo, "ncv_resultados_folds"),
    salvar_tabela(
      configuracoes_selecionadas, algoritmo,
      "ncv_configuracoes_selecionadas"
    ),
    salvar_tabela(
      frequencias, algoritmo, "ncv_frequencia_configuracoes"
    ),
    salvar_tabela(predicoes, algoritmo, "ncv_predicoes_oof"),
    salvar_tabela(resumo, algoritmo, "ncv_resumo_modelo"),
    salvar_tabela(
      resultados_oof, algoritmo, "ncv_resultados_repeticoes_oof"
    )
  )
  fim <- Sys.time()
  quantidade_ajustes <- 15L * (
    3L * nrow(especificacao$configuracoes) + 1L
  )
  salvar_manifesto_algoritmo(
    algoritmo, inicio, fim, quantidade_ajustes
  )

  cat(sprintf(
    "\n%s concluido: %d ajustes, %d folds externos.\n",
    algoritmo, quantidade_ajustes, nrow(resultados_folds)
  ))
  cat("Arquivos gerados:\n", paste0("- ", arquivos, collapse = "\n"), "\n")
  invisible(list(
    resultados_folds = resultados_folds,
    resumo = resumo,
    arquivos = arquivos
  ))
}
