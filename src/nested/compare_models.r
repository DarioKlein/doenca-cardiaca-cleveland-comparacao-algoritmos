#!/usr/bin/env Rscript

source(file.path("src", "nested", "config.r"))

MODELOS <- data.frame(
  prefixo = c("naive_bayes", "decision_trees", "random_forest", "svm"),
  nome = c("Naive Bayes", "Arvore de Decisao", "Random Forest", "SVM linear"),
  rotulo = c("Naive\nBayes", "Arvore de\nDecisao", "Random\nForest", "SVM\nlinear"),
  cor = c("#0072B2", "#E69F00", "#009E73", "#CC79A7"),
  stringsAsFactors = FALSE
)

METRICAS_GRAFICOS <- data.frame(
  metrica = c(
    "Acuracia", "Sensibilidade", "Especificidade", "Precisao", "F1", "MCC",
    "ROC_AUC", "Acuracia_Balanceada", "Brier", "Log_Loss",
    "Tempo_Total_Fold_Segundos"
  ),
  arquivo = c(
    "comparacao_acuracia.png", "comparacao_sensibilidade.png",
    "comparacao_especificidade.png", "comparacao_precisao.png",
    "comparacao_f1.png", "comparacao_mcc.png", "comparacao_roc_auc.png",
    "comparacao_acuracia_balanceada.png", "comparacao_brier.png",
    "comparacao_log_loss.png", "comparacao_tempo.png"
  ),
  titulo = c(
    "Comparacao da acuracia", "Comparacao da sensibilidade",
    "Comparacao da especificidade", "Comparacao da precisao",
    "Comparacao do F1", "Comparacao do MCC",
    "Comparacao da ROC-AUC", "Comparacao da acuracia balanceada",
    "Comparacao do Brier Score (menor e melhor)",
    "Comparacao da Log Loss (menor e melhor)",
    "Comparacao do tempo por fold externo (menor e melhor)"
  ),
  eixo_y = c(
    "Acuracia", "Sensibilidade", "Especificidade", "Precisao", "F1", "MCC",
    "ROC-AUC", "Acuracia balanceada", "Brier Score", "Log Loss",
    "Tempo total do fold externo (segundos)"
  ),
  tipo_escala = c(rep("zero_um", 5), "mcc", rep("zero_um", 2),
                  rep("positiva", 3)),
  stringsAsFactors = FALSE
)

carregar_resumos <- function() {
  resumos <- lapply(seq_len(nrow(MODELOS)), function(indice) {
    caminho <- file.path(
      DIRETORIO_CSV,
      paste0(MODELOS$prefixo[indice], "_ncv_resumo_modelo.csv")
    )
    if (!file.exists(caminho)) {
      stop("Arquivo nao encontrado: ", caminho, call. = FALSE)
    }
    resumo <- utils::read.csv(caminho, stringsAsFactors = FALSE)
    if (any(resumo$Unidade_Agregacao != "fold_externo") ||
        any(resumo$N_Avaliacoes != 15L)) {
      stop("Resumo incompativel: ", caminho, call. = FALSE)
    }
    resumo$Modelo <- MODELOS$nome[indice]
    resumo
  })
  do.call(rbind, resumos)
}

formatar_valor <- function(valor) {
  sub("[.]", ",", sprintf("%.3f", valor))
}

definir_limites <- function(tipo, medias, desvios) {
  inferiores <- medias - desvios
  superiores <- medias + desvios
  if (tipo == "zero_um") {
    return(c(0, 1))
  }
  if (tipo == "mcc") {
    inferior <- max(-1, min(-0.05, inferiores) * 1.10)
    superior <- min(1, max(0.05, superiores) * 1.10)
    return(c(inferior, superior))
  }
  maximo <- max(superiores)
  c(0, if (maximo <= 0) 1 else maximo * 1.25)
}

gerar_grafico <- function(configuracao, resumos) {
  dados <- resumos[resumos$Metrica == configuracao$metrica, ]
  dados <- dados[match(MODELOS$nome, dados$Modelo), ]
  if (nrow(dados) != nrow(MODELOS) ||
      any(!is.finite(as.matrix(dados[, c("Media", "DP")]))) ) {
    stop("Resultado incompleto para ", configuracao$metrica, call. = FALSE)
  }
  medias <- dados$Media
  desvios <- dados$DP
  limites_y <- definir_limites(configuracao$tipo_escala, medias, desvios)
  limite_inferior <- pmax(limites_y[1], medias - desvios)
  limite_superior <- pmin(limites_y[2], medias + desvios)
  caminho <- file.path(DIRETORIO_IMAGENS, configuracao$arquivo)

  grDevices::png(
    caminho, width = 2400, height = 1600, res = 240, bg = "white"
  )
  parametros <- graphics::par(
    mar = c(7.2, 6.2, 5.2, 2.0), las = 1, family = "sans",
    cex.axis = 0.95, cex.lab = 1.1, cex.main = 1.35
  )
  posicoes <- graphics::barplot(
    medias,
    names.arg = MODELOS$rotulo,
    col = MODELOS$cor,
    border = NA,
    ylim = limites_y,
    ylab = configuracao$eixo_y,
    main = paste0(configuracao$titulo, " - Cleveland complementar"),
    cex.names = 1.05,
    space = 0.45
  )
  graphics::arrows(
    posicoes, limite_inferior, posicoes, limite_superior,
    angle = 90, code = 3, length = 0.06, lwd = 2
  )
  deslocamento <- diff(limites_y) * 0.035
  graphics::text(
    posicoes,
    pmin(limite_superior + deslocamento, limites_y[2] - deslocamento / 2),
    labels = vapply(medias, formatar_valor, character(1)),
    cex = 0.95, font = 2
  )
  graphics::mtext(
    "Media +/- DP de 15 folds externos | CV aninhada 5 x 3; interna 3-fold",
    side = 1, line = 5.7, cex = 0.80
  )
  graphics::box(bty = "l")
  graphics::par(parametros)
  grDevices::dev.off()
  caminho
}

gerar_grafico_inferencia <- function() {
  caminho_csv <- file.path(
    DIRETORIO_INFERENCIA, "mcc_comparacoes_pareadas.csv"
  )
  if (!file.exists(caminho_csv)) {
    stop(
      "Execute statistical_analysis.r antes de gerar os graficos.",
      call. = FALSE
    )
  }
  dados <- utils::read.csv(caminho_csv, stringsAsFactors = FALSE)
  if (nrow(dados) != 6L || any(dados$Status != "valido")) {
    stop("Comparacoes estatisticas incompletas ou invalidas.", call. = FALSE)
  }
  caminho <- file.path(DIRETORIO_IMAGENS, "comparacoes_pareadas_mcc.png")
  limites <- range(c(
    dados$IC95_Marginal_Inferior, dados$IC95_Marginal_Superior, 0
  ))
  margem <- max(diff(limites) * 0.08, 0.01)
  limites <- limites + c(-margem, margem)
  limites[2L] <- limites[2L] + max(diff(limites) * 0.20, 0.05)

  grDevices::png(
    caminho, width = 2400, height = 1700, res = 240, bg = "white"
  )
  parametros <- graphics::par(mar = c(6, 14, 5, 2), las = 1, family = "sans")
  posicoes <- rev(seq_len(nrow(dados)))
  graphics::plot(
    dados$Diferenca_Media_A_menos_B, posicoes,
    xlim = limites, ylim = c(0.5, nrow(dados) + 0.5),
    yaxt = "n", pch = 19, col = "#0072B2",
    xlab = "Diferenca media de MCC (A - B)", ylab = "",
    main = "Comparacoes pareadas de MCC - Cleveland complementar"
  )
  graphics::axis(2, at = posicoes, labels = dados$Rotulo_Par, las = 1)
  graphics::segments(
    dados$IC95_Marginal_Inferior, posicoes,
    dados$IC95_Marginal_Superior, posicoes,
    col = "#0072B2", lwd = 2
  )
  graphics::abline(v = 0, lty = 2, col = "#D55E00")
  rotulos_p <- ifelse(
    dados$P_Holm < 0.001, "p Holm < 0,001",
    paste0("p Holm = ", sub("[.]", ",", sprintf("%.3f", dados$P_Holm)))
  )
  graphics::text(
    dados$IC95_Marginal_Superior + margem * 0.15,
    posicoes, labels = rotulos_p, pos = 4, cex = 0.78
  )
  graphics::mtext(
    "Intervalos marginais de 95%; a decisao usa p-valores ajustados por Holm",
    side = 1, line = 4.5, cex = 0.80
  )
  graphics::par(parametros)
  grDevices::dev.off()
  caminho
}

executar_comparacao <- function() {
  verificar_diretorio_projeto()
  criar_diretorios_experimento()
  resumos <- carregar_resumos()
  caminhos <- vapply(seq_len(nrow(METRICAS_GRAFICOS)), function(indice) {
    gerar_grafico(METRICAS_GRAFICOS[indice, ], resumos)
  }, character(1))
  caminho_inferencia <- gerar_grafico_inferencia()
  caminhos <- c(caminhos, caminho_inferencia)
  cat(sprintf(
    "%d graficos gerados em %s.\n", length(caminhos), DIRETORIO_IMAGENS
  ))
  invisible(caminhos)
}

executar_comparacao()
