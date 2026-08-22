NOMES_METRICAS <- c(
  "Acuracia", "Sensibilidade", "Especificidade", "Precisao", "F1", "MCC",
  "ROC_AUC", "Brier", "Log_Loss", "Acuracia_Balanceada"
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

calcular_metricas <- function(classe_real, probabilidade, limiar = 0.5) {
  if (any(!is.finite(probabilidade)) ||
      any(probabilidade < 0 | probabilidade > 1)) {
    stop("As probabilidades devem estar entre zero e um.", call. = FALSE)
  }

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

  sensibilidade <- vp / (vp + fn)
  especificidade <- vn / (vn + fp)
  precisao <- if ((vp + fp) == 0L) 0 else vp / (vp + fp)
  denominador_f1 <- 2 * vp + fp + fn
  f1 <- if (denominador_f1 == 0L) NA_real_ else 2 * vp / denominador_f1

  denominador_mcc <- sqrt(prod(as.numeric(c(
    vp + fp, vp + fn, vn + fp, vn + fn
  ))))
  mcc <- if (denominador_mcc == 0) 0 else {
    (vp * vn - fp * fn) / denominador_mcc
  }

  classe_binaria <- as.numeric(classe_real == CLASSE_POSITIVA)
  probabilidade_segura <- pmin(
    pmax(probabilidade, .Machine$double.eps), 1 - .Machine$double.eps
  )

  c(
    Acuracia = (vp + vn) / (vp + vn + fp + fn),
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
    VP = vp, VN = vn, FP = fp, FN = fn
  )
}

criar_ranking_medio <- function(resultados, configuracoes) {
  colunas <- c(NOMES_METRICAS, "Tempo_Execucao_Segundos")
  medias <- stats::aggregate(
    resultados[colunas],
    by = list(id = resultados$id),
    FUN = mean,
    na.rm = TRUE
  )
  names(medias)[-1L] <- paste0(names(medias)[-1L], "_Media")

  ranking <- merge(configuracoes, medias, by = "id", sort = FALSE)
  ordem <- order(
    -ranking$MCC_Media,
    -ranking$F1_Media,
    -ranking$ROC_AUC_Media,
    ranking$id
  )
  ranking[ordem, , drop = FALSE]
}

resumir_resultados <- function(resultados) {
  colunas <- c(NOMES_METRICAS, "Tempo_Execucao_Segundos")
  data.frame(
    Metrica = colunas,
    Media = vapply(colunas, function(nome) mean(resultados[[nome]]), numeric(1)),
    DP = vapply(colunas, function(nome) stats::sd(resultados[[nome]]), numeric(1)),
    row.names = NULL
  )
}

criar_tabela_predicoes <- function(dados, probabilidade, limiar) {
  data.frame(
    id_registro = dados$id_registro,
    classe_real = as.character(dados[[VARIAVEL_ALVO]]),
    probabilidade_doenca = probabilidade,
    classe_prevista = ifelse(
      probabilidade >= limiar, CLASSE_POSITIVA, CLASSE_NEGATIVA
    ),
    stringsAsFactors = FALSE
  )
}

executar_cv_repetida <- function(dados, configuracoes, ajustar_modelo,
                                 prever_probabilidade, semente_base,
                                 numero_folds = 5L, repeticoes = 3L,
                                 limiar = 0.5) {
  resultados <- vector("list", repeticoes * nrow(configuracoes))
  predicoes <- vector("list", repeticoes * nrow(configuracoes))
  posicao <- 1L

  for (repeticao in seq_len(repeticoes)) {
    semente_divisao <- semente_base + repeticao - 1L
    folds <- criar_folds_estratificados(
      dados[[VARIAVEL_ALVO]], numero_folds, semente_divisao
    )

    for (indice_configuracao in seq_len(nrow(configuracoes))) {
      inicio <- Sys.time()
      configuracao <- configuracoes[indice_configuracao, , drop = FALSE]
      probabilidades_oof <- numeric(nrow(dados))

      for (fold in seq_len(numero_folds)) {
        indices_teste <- which(folds == fold)
        dados_treino <- dados[-indices_teste, , drop = FALSE]
        dados_teste <- dados[indices_teste, , drop = FALSE]
        semente_modelo <- semente_divisao + indice_configuracao * 100L + fold

        ajuste <- ajustar_modelo(
          dados_treino, configuracao, semente_modelo
        )
        probabilidades_oof[indices_teste] <- prever_probabilidade(
          ajuste, dados_teste
        )
      }

      metricas <- calcular_metricas(
        dados[[VARIAVEL_ALVO]], probabilidades_oof, limiar
      )
      tempo <- as.numeric(difftime(Sys.time(), inicio, units = "secs"))

      resultados[[posicao]] <- data.frame(
        Repeticao = repeticao,
        Semente = semente_divisao,
        configuracao,
        t(metricas),
        Tempo_Execucao_Segundos = tempo,
        row.names = NULL
      )
      predicoes[[posicao]] <- data.frame(
        Repeticao = repeticao,
        Semente = semente_divisao,
        Configuracao = configuracao$id,
        Fold = folds,
        criar_tabela_predicoes(dados, probabilidades_oof, limiar),
        row.names = NULL
      )
      posicao <- posicao + 1L
    }

    cat(sprintf("Repeticao %d/%d concluida.\n", repeticao, repeticoes))
  }

  resultados <- do.call(rbind, resultados)
  predicoes <- do.call(rbind, predicoes)
  ranking <- criar_ranking_medio(resultados, configuracoes)
  melhor_id <- ranking$id[1L]
  resultados_melhor <- resultados[resultados$id == melhor_id, , drop = FALSE]
  predicoes_melhor <- predicoes[
    predicoes$Configuracao == melhor_id, , drop = FALSE
  ]

  list(
    resultados_configuracoes = resultados,
    ranking_configuracoes = ranking,
    resultados_repeticoes = resultados_melhor,
    resumo_modelo = resumir_resultados(resultados_melhor),
    predicoes_oof = predicoes_melhor,
    melhor_configuracao = configuracoes[
      match(melhor_id, configuracoes$id), , drop = FALSE
    ],
    quantidade_ajustes = nrow(configuracoes) * numero_folds * repeticoes
  )
}

aprender_modas <- function(dados_treino, variaveis) {
  vapply(variaveis, function(variavel) {
    contagens <- table(dados_treino[[variavel]], useNA = "no")
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

salvar_resultados <- function(prefixo, avaliacao) {
  diretorio_csv <- file.path("results", "csvs")
  dir.create(diretorio_csv, showWarnings = FALSE, recursive = TRUE)

  arquivos <- list(
    cv_resultados_configuracoes = avaliacao$resultados_configuracoes,
    cv_ranking_configuracoes = avaliacao$ranking_configuracoes,
    cv_resultados_repeticoes = avaliacao$resultados_repeticoes,
    cv_resumo_modelo = avaliacao$resumo_modelo,
    cv_predicoes_oof = avaliacao$predicoes_oof
  )

  for (sufixo in names(arquivos)) {
    utils::write.csv(
      arquivos[[sufixo]],
      file.path(diretorio_csv, paste0(prefixo, "_", sufixo, ".csv")),
      row.names = FALSE
    )
  }
}

mostrar_resumo <- function(resumo) {
  resumo_exibicao <- resumo
  resumo_exibicao$Media <- round(resumo_exibicao$Media, 4)
  resumo_exibicao$DP <- round(resumo_exibicao$DP, 4)
  print(resumo_exibicao, row.names = FALSE)
}
