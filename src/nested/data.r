COLUNAS_ORIGINAIS <- c(
  "age", "sex", "cp", "trestbps", "chol", "fbs", "restecg",
  "thalach", "exang", "oldpeak", "slope", "ca", "thal", "num"
)

NOMES_PORTUGUES <- c(
  "idade", "sexo", "tipo_dor_toracica", "pressao_arterial_repouso",
  "colesterol_serico", "glicemia_jejum", "eletrocardiograma_repouso",
  "frequencia_cardiaca_maxima", "angina_induzida_exercicio",
  "depressao_segmento_st", "inclinacao_segmento_st", "vasos_principais",
  "thal", "num"
)

validar_dados_originais <- function(dados) {
  faltantes <- setdiff(COLUNAS_ORIGINAIS, names(dados))
  if (length(faltantes) > 0L) {
    stop(
      "Colunas ausentes na base UCI: ", paste(faltantes, collapse = ", "),
      call. = FALSE
    )
  }
  if (nrow(dados) != 303L) {
    stop("A base Cleveland deve conter 303 registros.", call. = FALSE)
  }
  invisible(TRUE)
}

preparar_dados_cleveland <- function(dados_originais) {
  validar_dados_originais(dados_originais)
  dados <- dados_originais[, COLUNAS_ORIGINAIS, drop = FALSE]
  names(dados) <- NOMES_PORTUGUES

  for (variavel in VARIAVEIS_NUMERICAS) {
    dados[[variavel]] <- as.numeric(dados[[variavel]])
  }

  dados$sexo <- factor(dados$sexo, levels = c(0, 1))
  dados$tipo_dor_toracica <- factor(dados$tipo_dor_toracica, levels = 1:4)
  dados$glicemia_jejum <- factor(dados$glicemia_jejum, levels = c(0, 1))
  dados$eletrocardiograma_repouso <- factor(
    dados$eletrocardiograma_repouso, levels = 0:2
  )
  dados$angina_induzida_exercicio <- factor(
    dados$angina_induzida_exercicio, levels = c(0, 1)
  )
  dados$inclinacao_segmento_st <- factor(
    dados$inclinacao_segmento_st, levels = 1:3
  )
  dados$vasos_principais <- factor(dados$vasos_principais, levels = 0:3)
  dados$thal <- factor(dados$thal, levels = c(3, 6, 7))

  classe_original <- as.numeric(as.character(dados$num))
  if (anyNA(classe_original)) {
    stop("A variavel alvo possui valores ausentes.", call. = FALSE)
  }
  dados[[VARIAVEL_ALVO]] <- factor(
    ifelse(classe_original > 0, CLASSE_POSITIVA, CLASSE_NEGATIVA),
    levels = c(CLASSE_NEGATIVA, CLASSE_POSITIVA)
  )
  dados$num <- NULL
  dados$id_registro <- seq_len(nrow(dados))
  validar_dados_preparados(dados)
  dados
}

validar_dados_preparados <- function(dados) {
  colunas <- c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO, "id_registro")
  if (!identical(names(dados), colunas)) {
    stop("As colunas preparadas nao correspondem ao protocolo.", call. = FALSE)
  }
  if (nrow(dados) != 303L || anyDuplicated(dados$id_registro)) {
    stop("Identidade ou quantidade de registros invalida.", call. = FALSE)
  }

  classes <- table(dados[[VARIAVEL_ALVO]])
  esperadas <- c(sem_doenca = 164L, doenca = 139L)
  if (!identical(as.integer(classes[names(esperadas)]), unname(esperadas))) {
    stop("A distribuicao das classes difere do protocolo.", call. = FALSE)
  }
  if (sum(is.na(dados$vasos_principais)) != 4L ||
      sum(is.na(dados$thal)) != 2L) {
    stop("As ausencias de ca/thal diferem do esperado.", call. = FALSE)
  }
  invisible(TRUE)
}

carregar_dados_preparados <- function() {
  if (!file.exists(ARQUIVO_DADOS_PREPARADOS)) {
    stop(
      "Dados preparados ausentes. Execute prepare_experiment.r primeiro.",
      call. = FALSE
    )
  }
  dados <- readRDS(ARQUIVO_DADOS_PREPARADOS)
  validar_dados_preparados(dados)
  dados
}
