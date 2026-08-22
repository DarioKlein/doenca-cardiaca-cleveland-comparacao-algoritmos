#!/usr/bin/env Rscript

DIRETORIO_CSV <- file.path("results", "csvs")
DIRETORIO_IMAGENS <- file.path("results", "imagens")

MODELOS <- data.frame(
  prefixo = c("naive_bayes", "decision_trees", "random_forest", "svm"),
  nome = c("Naive Bayes", "Arvore de Decisao", "Random Forest", "SVM"),
  rotulo = c(
    "Naive\nBayes", "\u00c1rvore de\nDecis\u00e3o", "Random\nForest", "SVM"
  ),
  cor = c("#0072B2", "#E69F00", "#009E73", "#CC79A7"),
  stringsAsFactors = FALSE
)

METRICAS_GRAFICOS <- data.frame(
  metrica = c(
    "Acuracia", "Sensibilidade", "Especificidade", "Precisao", "F1", "MCC",
    "ROC_AUC", "Acuracia_Balanceada", "Brier", "Log_Loss",
    "Tempo_Execucao_Segundos"
  ),
  arquivo = c(
    "comparacao_acuracia.png", "comparacao_sensibilidade.png",
    "comparacao_especificidade.png", "comparacao_precisao.png",
    "comparacao_f1.png", "comparacao_mcc.png", "comparacao_roc_auc.png",
    "comparacao_acuracia_balanceada.png", "comparacao_brier.png",
    "comparacao_log_loss.png", "comparacao_tempo.png"
  ),
  titulo = c(
    "Compara\u00e7\u00e3o da acur\u00e1cia",
    "Compara\u00e7\u00e3o da sensibilidade",
    "Compara\u00e7\u00e3o da especificidade",
    "Compara\u00e7\u00e3o da precis\u00e3o",
    "Compara\u00e7\u00e3o do F1", "Compara\u00e7\u00e3o do MCC",
    "Compara\u00e7\u00e3o da ROC-AUC",
    "Compara\u00e7\u00e3o da acur\u00e1cia balanceada",
    "Compara\u00e7\u00e3o do Brier Score (menor \u00e9 melhor)",
    "Compara\u00e7\u00e3o da Log Loss (menor \u00e9 melhor)",
    "Compara\u00e7\u00e3o do tempo (menor \u00e9 melhor)"
  ),
  eixo_y = c(
    "Acur\u00e1cia", "Sensibilidade", "Especificidade", "Precis\u00e3o",
    "F1", "MCC", "ROC-AUC", "Acur\u00e1cia balanceada", "Brier Score",
    "Log Loss", "Tempo por repeti\u00e7\u00e3o (segundos)"
  ),
  escala_zero_um = c(rep(TRUE, 8), FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

carregar_resumos <- function() {
  resumos <- lapply(seq_len(nrow(MODELOS)), function(indice) {
    caminho <- file.path(
      DIRETORIO_CSV,
      paste0(MODELOS$prefixo[indice], "_cv_resumo_modelo.csv")
    )
    if (!file.exists(caminho)) {
      stop("Arquivo nao encontrado: ", caminho, call. = FALSE)
    }

    resumo <- utils::read.csv(caminho, stringsAsFactors = FALSE)
    resumo$Modelo <- MODELOS$nome[indice]
    resumo
  })

  do.call(rbind, resumos)
}

formatar_valor <- function(valor) {
  sub("[.]", ",", sprintf("%.3f", valor))
}

gerar_grafico <- function(configuracao, resumos) {
  dados <- resumos[resumos$Metrica == configuracao$metrica, ]
  dados <- dados[match(MODELOS$nome, dados$Modelo), ]

  if (nrow(dados) != nrow(MODELOS) || anyNA(dados[, c("Media", "DP")])) {
    stop("Resultado incompleto para a metrica: ", configuracao$metrica)
  }

  medias <- dados$Media
  desvios <- dados$DP
  limite_inferior <- pmax(0, medias - desvios)
  limite_superior <- medias + desvios

  if (configuracao$escala_zero_um) {
    limites_y <- c(0, 1)
  } else {
    maximo <- max(limite_superior)
    limites_y <- c(0, if (maximo == 0) 1 else maximo * 1.30)
  }

  caminho <- file.path(DIRETORIO_IMAGENS, configuracao$arquivo)
  grDevices::png(
    filename = caminho,
    width = 2400,
    height = 1600,
    res = 240,
    bg = "white"
  )
  parametros_anteriores <- graphics::par(
    mar = c(7.2, 6.2, 5.2, 2.0),
    las = 1,
    family = "sans",
    cex.axis = 0.95,
    cex.lab = 1.1,
    cex.main = 1.35
  )

  posicoes <- graphics::barplot(
    medias,
    names.arg = MODELOS$rotulo,
    col = MODELOS$cor,
    border = NA,
    ylim = limites_y,
    ylab = configuracao$eixo_y,
    main = configuracao$titulo,
    cex.names = 1.05,
    space = 0.45
  )
  graphics::arrows(
    posicoes, limite_inferior,
    posicoes, limite_superior,
    angle = 90,
    code = 3,
    length = 0.06,
    lwd = 2
  )

  deslocamento <- diff(limites_y) * 0.035
  graphics::text(
    posicoes,
    pmin(limite_superior + deslocamento, limites_y[2] * 0.98),
    labels = vapply(medias, formatar_valor, character(1)),
    cex = 0.95,
    font = 2
  )
  graphics::mtext(
    "M\u00e9dia +/- desvio-padr\u00e3o | 5-fold CV repetida 3 vezes",
    side = 1,
    line = 5.7,
    cex = 0.82
  )
  graphics::box(bty = "l")

  graphics::par(parametros_anteriores)
  grDevices::dev.off()
  caminho
}

executar_comparacao <- function() {
  dir.create(DIRETORIO_IMAGENS, showWarnings = FALSE, recursive = TRUE)
  resumos <- carregar_resumos()

  caminhos <- vapply(seq_len(nrow(METRICAS_GRAFICOS)), function(indice) {
    gerar_grafico(METRICAS_GRAFICOS[indice, ], resumos)
  }, character(1))

  cat(sprintf("\n%d graficos gerados em %s:\n", length(caminhos), DIRETORIO_IMAGENS))
  cat(paste0("- ", caminhos, collapse = "\n"), "\n")
}

executar_comparacao()
