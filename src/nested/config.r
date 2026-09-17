PROTOCOLO <- "cleveland_ncv_5x3_inner3_v1"
EXECUCAO <- Sys.getenv("PIBIC_EXECUCAO", unset = PROTOCOLO)
BASE_ESTUDO <- "Cleveland"

SEMENTES_EXTERNAS <- c(20260804L, 20260805L, 20260806L)
NUMERO_FOLDS_EXTERNOS <- 5L
NUMERO_FOLDS_INTERNOS <- 3L
LIMIAR <- 0.5

CLASSE_NEGATIVA <- "sem_doenca"
CLASSE_POSITIVA <- "doenca"
VARIAVEL_ALVO <- "classe_doenca"

VARIAVEIS_PREDITORAS <- c(
  "idade", "sexo", "tipo_dor_toracica", "pressao_arterial_repouso",
  "colesterol_serico", "glicemia_jejum", "eletrocardiograma_repouso",
  "frequencia_cardiaca_maxima", "angina_induzida_exercicio",
  "depressao_segmento_st", "inclinacao_segmento_st", "vasos_principais",
  "thal"
)

VARIAVEIS_NUMERICAS <- c(
  "idade", "pressao_arterial_repouso", "colesterol_serico",
  "frequencia_cardiaca_maxima", "depressao_segmento_st"
)

ALGORITMOS <- c(
  "naive_bayes", "decision_trees", "random_forest", "svm"
)

DIRETORIO_DADOS <- file.path("dataset", "nested")
DIRETORIO_RESULTADOS <- file.path("results", PROTOCOLO)
DIRETORIO_PARTICOES <- file.path(DIRETORIO_RESULTADOS, "partitions")
DIRETORIO_CHECKPOINTS <- file.path(DIRETORIO_RESULTADOS, "checkpoints")
DIRETORIO_CSV <- file.path(DIRETORIO_RESULTADOS, "csvs")
DIRETORIO_INFERENCIA <- file.path(DIRETORIO_RESULTADOS, "inferencia")
DIRETORIO_IMAGENS <- file.path(DIRETORIO_RESULTADOS, "imagens")
DIRETORIO_MANIFESTO <- file.path(DIRETORIO_RESULTADOS, "manifest")
DIRETORIO_LOGS <- file.path(DIRETORIO_RESULTADOS, "logs")

ARQUIVO_DADOS_ORIGINAIS <- file.path(
  DIRETORIO_DADOS, "cleveland_original.rds"
)
ARQUIVO_DADOS_PREPARADOS <- file.path(
  DIRETORIO_DADOS, "cleveland_preparado.rds"
)
ARQUIVO_FOLDS_EXTERNOS <- file.path(
  DIRETORIO_PARTICOES, "folds_externos.csv"
)
ARQUIVO_FOLDS_INTERNOS <- file.path(
  DIRETORIO_PARTICOES, "folds_internos.csv"
)
ARQUIVO_SEMENTES <- file.path(
  DIRETORIO_PARTICOES, "sementes_ajustes.csv"
)

verificar_diretorio_projeto <- function() {
  marcador <- file.path("src", "nested", "config.r")
  if (!file.exists(marcador)) {
    stop(
      "Execute o script a partir da pasta Clevand.",
      call. = FALSE
    )
  }
}

criar_diretorios_experimento <- function() {
  diretorios <- c(
    DIRETORIO_DADOS, DIRETORIO_PARTICOES, DIRETORIO_CHECKPOINTS,
    DIRETORIO_CSV, DIRETORIO_INFERENCIA, DIRETORIO_IMAGENS,
    DIRETORIO_MANIFESTO, DIRETORIO_LOGS
  )
  invisible(lapply(
    diretorios, dir.create, showWarnings = FALSE, recursive = TRUE
  ))
}

assinatura_arquivo <- function(caminho) {
  if (!file.exists(caminho)) {
    stop("Arquivo nao encontrado: ", caminho, call. = FALSE)
  }
  unname(tools::md5sum(caminho))
}
