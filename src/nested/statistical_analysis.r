#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))

ROTULOS_ALGORITMOS <- c(
  naive_bayes = "Naive Bayes",
  decision_trees = "Arvore de Decisao",
  random_forest = "Random Forest",
  svm = "SVM linear"
)

ler_folds_externos <- function(algoritmo) {
  caminho <- file.path(
    DIRETORIO_CSV,
    paste0(algoritmo, "_ncv_resultados_folds.csv")
  )
  if (!file.exists(caminho)) {
    stop("Resultado ausente: ", caminho, call. = FALSE)
  }
  dados <- utils::read.csv(caminho, stringsAsFactors = FALSE)
  if (nrow(dados) != 15L ||
      anyDuplicated(dados[c("Repeticao", "Fold_Externo")]) ||
      any(dados$Status != "completo") ||
      any(!is.finite(dados$MCC))) {
    stop("Resultados externos invalidos para ", algoritmo, call. = FALSE)
  }
  dados
}

verificar_validacao_previa <- function() {
  caminho <- file.path(DIRETORIO_MANIFESTO, "validacao_resultados.csv")
  if (!file.exists(caminho)) {
    stop("Execute validate_results.r antes da analise estatistica.", call. = FALSE)
  }
  validacao <- utils::read.csv(caminho, stringsAsFactors = FALSE)
  if (nrow(validacao) != length(ALGORITMOS) ||
      !setequal(validacao$Algoritmo, ALGORITMOS) ||
      any(validacao$Status != "valido") ||
      any(validacao$Protocolo != PROTOCOLO) ||
      any(validacao$Execucao != EXECUCAO)) {
    stop("A validacao previa nao corresponde ao experimento.", call. = FALSE)
  }
}

comparar_par <- function(algoritmo_a, algoritmo_b, resultados) {
  colunas <- c(
    "Repeticao", "Fold_Externo", "MCC", "N_Treino_Externo",
    "N_Teste_Externo"
  )
  a <- resultados[[algoritmo_a]][colunas]
  b <- resultados[[algoritmo_b]][colunas]
  nomes_chave <- c("Repeticao", "Fold_Externo")
  pareados <- merge(
    a, b, by = nomes_chave, suffixes = c("_A", "_B"), sort = TRUE
  )
  if (nrow(pareados) != 15L ||
      any(pareados$N_Treino_Externo_A != pareados$N_Treino_Externo_B) ||
      any(pareados$N_Teste_Externo_A != pareados$N_Teste_Externo_B)) {
    stop("Pareamento invalido entre ", algoritmo_a, " e ", algoritmo_b)
  }

  diferencas <- pareados$MCC_A - pareados$MCC_B
  variancia <- stats::var(diferencas)
  razao <- mean(
    pareados$N_Teste_Externo_A / pareados$N_Treino_Externo_A
  )
  media_diferenca <- mean(diferencas)
  status <- "valido"
  erro_padrao <- estatistica_t <- p_bruto <- ic_inferior <- ic_superior <- NA_real_

  if (!is.finite(variancia) || variancia <= .Machine$double.eps) {
    status <- "variancia_das_diferencas_degenerada"
  } else {
    erro_padrao <- sqrt((1 / length(diferencas) + razao) * variancia)
    estatistica_t <- media_diferenca / erro_padrao
    p_bruto <- 2 * stats::pt(-abs(estatistica_t), df = 14L)
    margem <- stats::qt(0.975, df = 14L) * erro_padrao
    ic_inferior <- media_diferenca - margem
    ic_superior <- media_diferenca + margem
  }

  melhor <- if (media_diferenca > 0) {
    ROTULOS_ALGORITMOS[[algoritmo_a]]
  } else if (media_diferenca < 0) {
    ROTULOS_ALGORITMOS[[algoritmo_b]]
  } else {
    "Empate"
  }
  resumo <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Algoritmo_A = algoritmo_a,
    Algoritmo_B = algoritmo_b,
    Rotulo_Par = paste(
      ROTULOS_ALGORITMOS[[algoritmo_a]],
      ROTULOS_ALGORITMOS[[algoritmo_b]], sep = " - "
    ),
    N_Avaliacoes = length(diferencas),
    MCC_Medio_A = mean(pareados$MCC_A),
    MCC_Medio_B = mean(pareados$MCC_B),
    Diferenca_Media_A_menos_B = media_diferenca,
    Variancia_Diferencas = variancia,
    Razao_Teste_Treino = razao,
    Erro_Padrao_Corrigido = erro_padrao,
    T_Corrigido = estatistica_t,
    Graus_Liberdade = 14L,
    P_Bruto = p_bruto,
    IC95_Marginal_Inferior = ic_inferior,
    IC95_Marginal_Superior = ic_superior,
    Maior_MCC_Medio = melhor,
    Status = status,
    stringsAsFactors = FALSE
  )
  auditoria <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Algoritmo_A = algoritmo_a,
    Algoritmo_B = algoritmo_b,
    Repeticao = pareados$Repeticao,
    Fold_Externo = pareados$Fold_Externo,
    MCC_A = pareados$MCC_A,
    MCC_B = pareados$MCC_B,
    Diferenca_A_menos_B = diferencas,
    stringsAsFactors = FALSE
  )
  list(resumo = resumo, auditoria = auditoria)
}

nome_seguro <- function(texto) {
  gsub("[^a-z0-9]+", "_", tolower(texto))
}

gerar_diagnosticos <- function(comparacao, auditoria, diretorio) {
  rotulo <- comparacao$Rotulo_Par
  diferencas <- auditoria$Diferenca_A_menos_B
  prefixo <- nome_seguro(rotulo)

  grDevices::png(
    file.path(diretorio, paste0(prefixo, "_diferencas.png")),
    width = 1800, height = 1200, res = 180, bg = "white"
  )
  graphics::plot(
    seq_along(diferencas), diferencas,
    type = "b", pch = 19, col = "#0072B2",
    xlab = "Avaliacao externa pareada",
    ylab = "Diferenca de MCC (A - B)",
    main = paste("Diferencas pareadas:", rotulo)
  )
  graphics::abline(h = 0, lty = 2, col = "#D55E00")
  grDevices::dev.off()

  grDevices::png(
    file.path(diretorio, paste0(prefixo, "_qq.png")),
    width = 1800, height = 1200, res = 180, bg = "white"
  )
  stats::qqnorm(
    diferencas, pch = 19, col = "#0072B2",
    main = paste("Q-Q das diferencas:", rotulo),
    xlab = "Quantis teoricos", ylab = "Diferencas observadas"
  )
  stats::qqline(diferencas, col = "#D55E00", lwd = 2)
  grDevices::dev.off()
}

executar_analise_estatistica <- function() {
  verificar_diretorio_projeto()
  criar_diretorios_experimento()
  verificar_validacao_previa()
  resultados <- lapply(ALGORITMOS, ler_folds_externos)
  names(resultados) <- ALGORITMOS
  pares <- list(
    c("naive_bayes", "decision_trees"),
    c("naive_bayes", "random_forest"),
    c("naive_bayes", "svm"),
    c("decision_trees", "random_forest"),
    c("decision_trees", "svm"),
    c("random_forest", "svm")
  )
  comparacoes <- lapply(pares, function(par) {
    comparar_par(par[1L], par[2L], resultados)
  })
  resumo <- do.call(rbind, lapply(comparacoes, `[[`, "resumo"))
  auditoria <- do.call(rbind, lapply(comparacoes, `[[`, "auditoria"))

  if (all(resumo$Status == "valido") && all(is.finite(resumo$P_Bruto))) {
    resumo$P_Holm <- stats::p.adjust(resumo$P_Bruto, method = "holm")
  } else {
    resumo$P_Holm <- NA_real_
  }
  resumo <- resumo[, c(
    setdiff(names(resumo), c("P_Holm", "Status")), "P_Holm", "Status"
  )]
  significativos <- resumo$Rotulo_Par[
    is.finite(resumo$P_Holm) & resumo$P_Holm <= 0.05
  ]
  if (any(resumo$Status != "valido")) {
    decisao <- "Inconclusiva: ao menos uma comparacao foi invalida"
  } else if (length(significativos) > 0L) {
    decisao <- "Rejeitar H0 na Cleveland complementar"
  } else {
    decisao <- "Nao rejeitar H0 na Cleveland complementar"
  }
  decisao_global <- data.frame(
    Protocolo = PROTOCOLO,
    Execucao = EXECUCAO,
    Base = BASE_ESTUDO,
    Alfa = 0.05,
    Familia = "Seis comparacoes bilaterais de MCC",
    Pares_Validos = sum(resumo$Status == "valido"),
    Pares_Significativos = length(significativos),
    Lista_Pares_Significativos = paste(significativos, collapse = "; "),
    Decisao = decisao,
    stringsAsFactors = FALSE
  )

  utils::write.csv(
    auditoria,
    file.path(DIRETORIO_INFERENCIA, "mcc_diferencas_por_fold.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    resumo,
    file.path(DIRETORIO_INFERENCIA, "mcc_comparacoes_pareadas.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    decisao_global,
    file.path(DIRETORIO_INFERENCIA, "mcc_decisao_global.csv"),
    row.names = FALSE
  )

  diretorio_diagnosticos <- file.path(DIRETORIO_IMAGENS, "diagnosticos_mcc")
  dir.create(diretorio_diagnosticos, showWarnings = FALSE, recursive = TRUE)
  for (indice in seq_along(comparacoes)) {
    gerar_diagnosticos(
      resumo[indice, ], comparacoes[[indice]]$auditoria,
      diretorio_diagnosticos
    )
  }
  cat("Analise estatistica concluida.\n")
  print(resumo[, c(
    "Rotulo_Par", "Diferenca_Media_A_menos_B", "P_Bruto", "P_Holm",
    "Status"
  )], row.names = FALSE)
  cat("\n", decisao, "\n", sep = "")
  invisible(list(comparacoes = resumo, decisao = decisao_global))
}

executar_analise_estatistica()
