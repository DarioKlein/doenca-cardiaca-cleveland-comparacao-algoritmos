# =============================================================================
# Dados compartilhados: UCI Heart Disease - Cleveland
# =============================================================================
# Este arquivo fixa o subconjunto Cleveland (303 pacientes), traduz os nomes
# das variaveis para portugues e prepara a classe alvo para todos os modelos.

POSITIVE_CLASS <- "doenca"
NEGATIVE_CLASS <- "sem_doenca"

NOMES_ORIGINAIS_UCI <- c(
  "age", "sex", "cp", "trestbps", "chol", "fbs", "restecg",
  "thalach", "exang", "oldpeak", "slope", "ca", "thal"
)
VARIAVEIS_PREDITORAS <- c(
  "idade", "sexo", "tipo_dor_toracica", "pressao_arterial_repouso",
  "colesterol_serico", "glicemia_jejum", "eletrocardiograma_repouso",
  "frequencia_cardiaca_maxima", "angina_induzida_exercicio",
  "depressao_segmento_st", "inclinacao_segmento_st", "vasos_principais",
  "talassemia"
)
VARIAVEIS_NUMERICAS <- c(
  "idade", "pressao_arterial_repouso", "colesterol_serico",
  "frequencia_cardiaca_maxima", "depressao_segmento_st"
)
VARIAVEL_ALVO <- "classe_doenca"

validate_uci_heart_data <- function(data, origin) {
  if (nrow(data) != 303L || ncol(data) != 14L) {
    stop(
      sprintf(
        "O conteudo de '%s' nao corresponde ao esperado para Cleveland (303 linhas x 14 colunas).",
        origin
      ),
      call. = FALSE
    )
  }
  data
}

read_uci_heart_disease <- function(force_download = FALSE) {
  # A UCI usa abreviacoes em ingles no arquivo bruto. Elas sao traduzidas para
  # nomes semanticos em portugues em prepare_heart_disease().
  column_names <- c(NOMES_ORIGINAIS_UCI, "num")
  cache_directory <- "data"
  cache_file <- file.path(cache_directory, "processed.cleveland.data")
  if (!force_download && file.exists(cache_file) && file.info(cache_file)$size > 0) {
    cached_data <- utils::read.csv(
      cache_file, header = FALSE, na.strings = "?", col.names = column_names
    )
    return(validate_uci_heart_data(cached_data, cache_file))
  }
  direct_url <- paste0(
    "https://archive.ics.uci.edu/ml/machine-learning-databases/",
    "heart-disease/processed.cleveland.data"
  )

  # Usar explicitamente o arquivo Cleveland fixa o experimento em 303 casos.
  # O ZIP oficial atual e uma contingencia para a indisponibilidade da URL
  # historica, preservando exatamente o mesmo arquivo.
  direct_file <- tempfile(fileext = ".data")
  on.exit(unlink(direct_file), add = TRUE)
  direct_status <- tryCatch(
    utils::download.file(direct_url, direct_file, mode = "wb", quiet = TRUE),
    error = function(e) 1L
  )
  if (isTRUE(direct_status == 0) && file.exists(direct_file) &&
      file.info(direct_file)$size > 0) {
    parsed_data <- utils::read.csv(
      direct_file, header = FALSE, na.strings = "?", col.names = column_names
    )
    parsed_data <- validate_uci_heart_data(parsed_data, direct_url)
    dir.create(cache_directory, showWarnings = FALSE, recursive = TRUE)
    file.copy(direct_file, cache_file, overwrite = TRUE)
    return(parsed_data)
  }

  zip_url <- "https://archive.ics.uci.edu/static/public/45/heart+disease.zip"
  zip_file <- tempfile(fileext = ".zip")
  on.exit(unlink(zip_file), add = TRUE)
  zip_status <- tryCatch(
    utils::download.file(zip_url, zip_file, mode = "wb", quiet = TRUE),
    error = function(e) 1L
  )
  if (!isTRUE(zip_status == 0)) {
    stop("Nao foi possivel baixar a base da UCI. Verifique a conexao com a internet.")
  }

  listing <- utils::unzip(zip_file, list = TRUE)$Name
  cleveland_file <- listing[grepl("processed[.]cleveland[.]data$", listing)]
  if (length(cleveland_file) == 0L) {
    stop("O ZIP baixado da UCI nao contem processed.cleveland.data.")
  }

  extraction_dir <- tempfile("heart_disease_")
  dir.create(extraction_dir)
  on.exit(unlink(extraction_dir, recursive = TRUE), add = TRUE)
  utils::unzip(zip_file, files = cleveland_file[1L], exdir = extraction_dir)
  parsed_data <- utils::read.csv(
    file.path(extraction_dir, cleveland_file[1L]),
    header = FALSE, na.strings = "?", col.names = column_names
  )
  parsed_data <- validate_uci_heart_data(parsed_data, zip_url)
  dir.create(cache_directory, showWarnings = FALSE, recursive = TRUE)
  file.copy(file.path(extraction_dir, cleveland_file[1L]), cache_file, overwrite = TRUE)
  parsed_data
}

prepare_heart_disease <- function(raw_data) {
  if (ncol(raw_data) != 14L) {
    stop("Esperadas 14 colunas na versao Cleveland da UCI; foram encontradas: ", ncol(raw_data))
  }

  data <- raw_data
  names(data)[match(NOMES_ORIGINAIS_UCI, names(data))] <- VARIAVEIS_PREDITORAS
  for (variavel in VARIAVEIS_NUMERICAS) {
    data[[variavel]] <- as.numeric(data[[variavel]])
  }

  # As variaveis clinicamente categoricas sao fatores. Modelos que tratam NAs
  # por seus proprios mecanismos os recebem sem imputacao global, evitando
  # vazamento de informacao entre treino e teste.
  data$sexo <- factor(data$sexo, levels = c(0, 1))
  data$tipo_dor_toracica <- factor(data$tipo_dor_toracica, levels = 1:4)
  data$glicemia_jejum <- factor(data$glicemia_jejum, levels = c(0, 1))
  data$eletrocardiograma_repouso <- factor(data$eletrocardiograma_repouso, levels = 0:2)
  data$angina_induzida_exercicio <- factor(data$angina_induzida_exercicio, levels = c(0, 1))
  data$inclinacao_segmento_st <- factor(data$inclinacao_segmento_st, levels = 1:3)
  data$vasos_principais <- factor(data$vasos_principais, levels = 0:3)
  data$talassemia <- factor(data$talassemia, levels = c(3, 6, 7))

  data[[VARIAVEL_ALVO]] <- factor(
    ifelse(as.numeric(data$num) > 0, POSITIVE_CLASS, NEGATIVE_CLASS),
    levels = c(NEGATIVE_CLASS, POSITIVE_CLASS)
  )
  data$num <- NULL
  data
}
