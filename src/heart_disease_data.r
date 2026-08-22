ID_BASE_UCI <- 45L

CLASSE_POSITIVA <- "doenca"
CLASSE_NEGATIVA <- "sem_doenca"
VARIAVEL_ALVO <- "classe_doenca"

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

carregar_dados_coracao <- function() {
  base_uci <- ucimlrepo::fetch_ucirepo(id = ID_BASE_UCI)
  dados <- cbind(base_uci$data$features, base_uci$data$targets)

  if (nrow(dados) == 0L) {
    stop("Nao foi possivel carregar a base Heart Disease da UCI.", call. = FALSE)
  }

  names(dados) <- c(VARIAVEIS_PREDITORAS, "num")

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
  dados$talassemia <- factor(dados$talassemia, levels = c(3, 6, 7))

  classe_original <- as.numeric(as.character(dados$num))
  dados[[VARIAVEL_ALVO]] <- factor(
    ifelse(classe_original > 0, CLASSE_POSITIVA, CLASSE_NEGATIVA),
    levels = c(CLASSE_NEGATIVA, CLASSE_POSITIVA)
  )

  dados$num <- NULL
  dados$id_registro <- seq_len(nrow(dados))
  dados
}
