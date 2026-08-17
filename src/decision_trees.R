#!/usr/bin/env Rscript

# Arvores de Decisao para a base Heart Disease (Cleveland) da UCI
#
# O script segue o mesmo protocolo do Naive Bayes:
#   1. validacao cruzada estratificada externa 10-fold repetida 5 vezes;
#   2. ajuste de hiperparametros e limiar somente no treino de cada fold;
#   3. media +/- DP das mesmas metricas de avaliacao;
#   4. testes 5x2cv de Dietterich e Alpaydin entre criterios de divisao.

options(stringsAsFactors = FALSE)
MASTER_SEED <- 20260804L
OUTER_CV_SEED <- MASTER_SEED
INNER_SEED_STEP <- 1009L
FINAL_TUNING_SEED <- MASTER_SEED + 3571L
DIETTERICH_SEED <- MASTER_SEED + 7919L
OUTER_FOLDS <- 10L
OUTER_REPEATS <- 5L
INNER_FOLDS <- 5L
INNER_REPEATS <- 3L
set.seed(MASTER_SEED)
SCRIPT_START_TIME <- Sys.time()

report_execution_time <- function() {
  elapsed_seconds <- as.numeric(difftime(Sys.time(), SCRIPT_START_TIME, units = "secs"))
  cat(sprintf(
    "\nTempo total de execucao: %.2f segundos\n", elapsed_seconds
  ))
}

ensure_package <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    message("Pacote necessario ausente: ", package)
    stop(
      sprintf(
        paste0(
          "O pacote necessario '%s' nao esta instalado. Antes de executar o script, ",
          "instale-o manualmente com: install.packages('%s')"
        ),
        package, package
      ),
      call. = FALSE
    )
  }
}

ensure_package("rpart")
ensure_package("withr")
suppressPackageStartupMessages(library(rpart))
source(file.path("src", "heart_disease_data.R"))
source(file.path("src", "common_evaluation.R"))

# -----------------------------------------------------------------------------
# Ajuste, selecao de hiperparametros e limiar
# -----------------------------------------------------------------------------

fit_decision_tree <- function(training_data, config) {
  control <- rpart::rpart.control(
    cp = config$cp,
    minsplit = as.integer(config$minsplit),
    maxdepth = as.integer(config$maxdepth),
    xval = 0L
  )
  rpart::rpart(
    formula = stats::reformulate(VARIAVEIS_PREDITORAS, response = VARIAVEL_ALVO),
    data = training_data[, c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO), drop = FALSE],
    method = "class",
    parms = list(split = config$criterio_divisao),
    control = control
  )
}

predict_disease_probability <- function(model, new_data) {
  probability <- predict(
    model,
    newdata = new_data[, VARIAVEIS_PREDITORAS, drop = FALSE],
    type = "prob"
  )
  if (is.null(dim(probability)) || !(POSITIVE_CLASS %in% colnames(probability))) {
    stop("A probabilidade da classe positiva nao foi produzida pela arvore.")
  }
  as.numeric(probability[, POSITIVE_CLASS])
}

evaluate_config_cv <- function(data, config, folds) {
  predictions <- vector("list", length(folds))
  for (i in seq_along(folds)) {
    test_index <- folds[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]
    model <- fit_decision_tree(training_data, config)
    probability <- predict_disease_probability(model, test_data)
    if (anyNA(probability)) stop("A arvore retornou probabilidade NA.")

    predictions[[i]] <- data.frame(
      resample = names(folds)[i],
      truth = as.character(test_data[[VARIAVEL_ALVO]]),
      probability = probability,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, predictions)
}

tune_decision_tree <- function(data, configs, folds) {
  all_results <- vector("list", nrow(configs))

  for (i in seq_len(nrow(configs))) {
    config <- configs[i, , drop = FALSE]
    oof <- evaluate_config_cv(data, config, folds)
    threshold_result <- select_threshold(oof)
    fold_metrics <- metrics_by_resample(oof, threshold_result$threshold)

    all_results[[i]] <- list(
      config = config,
      oof = oof,
      threshold = threshold_result$threshold,
      threshold_scores = threshold_result$threshold_scores,
      fold_metrics = fold_metrics
    )
  }

  tuning_table <- do.call(rbind, lapply(all_results, function(result) {
    fold_metrics <- result$fold_metrics
    data.frame(
      id = result$config$id,
      criterio_divisao = ifelse(
        result$config$criterio_divisao == "gini", "Gini", "Informacao"
      ),
      cp = result$config$cp,
      minsplit = result$config$minsplit,
      maxdepth = result$config$maxdepth,
      threshold = result$threshold,
      N_resamples = sum(!is.na(fold_metrics$MCC)),
      Mean_MCC = mean_without_na(fold_metrics$MCC),
      SD_MCC = sd_without_na(fold_metrics$MCC),
      Mean_F1 = mean_without_na(fold_metrics$F1),
      SD_F1 = sd_without_na(fold_metrics$F1),
      Mean_ROC_AUC = mean_without_na(fold_metrics$ROC_AUC),
      SD_ROC_AUC = sd_without_na(fold_metrics$ROC_AUC),
      stringsAsFactors = FALSE
    )
  }))

  ordered <- order(
    -ifelse(is.na(tuning_table$Mean_MCC), -Inf, tuning_table$Mean_MCC),
    -ifelse(is.na(tuning_table$Mean_F1), -Inf, tuning_table$Mean_F1),
    -ifelse(is.na(tuning_table$Mean_ROC_AUC), -Inf, tuning_table$Mean_ROC_AUC),
    # Em empate exato de desempenho, prefere a arvore mais parcimoniosa.
    -tuning_table$cp,
    tuning_table$maxdepth,
    tuning_table$id
  )
  best_index <- ordered[1L]

  list(
    config = all_results[[best_index]]$config,
    threshold = all_results[[best_index]]$threshold,
    tuning_table = tuning_table[ordered, , drop = FALSE],
    details = all_results
  )
}

config_description <- function(config, threshold = NULL) {
  criterio <- if (config$criterio_divisao == "gini") "Gini" else "Informacao"
  description <- sprintf(
    "%s (cp = %s, minsplit = %d, profundidade maxima = %d)",
    criterio,
    format(config$cp, trim = TRUE),
    as.integer(config$minsplit),
    as.integer(config$maxdepth)
  )
  if (!is.null(threshold)) {
    description <- paste0(description, "; limiar = ", format(threshold, digits = 3))
  }
  description
}

# -----------------------------------------------------------------------------
# Avaliacao externa: validacao cruzada aninhada
# -----------------------------------------------------------------------------

nested_repeated_cv <- function(data, configs, outer_folds, outer_repeats,
                               inner_folds, inner_repeats, seed) {
  outer_splits <- make_repeated_folds(
    data[[VARIAVEL_ALVO]], k = outer_folds, repeats = outer_repeats, seed = seed
  )
  output <- vector("list", length(outer_splits))

  for (i in seq_along(outer_splits)) {
    message(sprintf("CV externa: %d/%d", i, length(outer_splits)))
    test_index <- outer_splits[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]

    inner_splits <- make_repeated_folds(
      training_data[[VARIAVEL_ALVO]],
      k = inner_folds,
      repeats = inner_repeats,
      seed = seed + i * INNER_SEED_STEP
    )
    tuning <- tune_decision_tree(training_data, configs, inner_splits)
    model <- fit_decision_tree(training_data, tuning$config)
    probability <- predict_disease_probability(model, test_data)
    if (anyNA(probability)) stop("A arvore retornou probabilidade NA na CV externa.")
    metrics <- binary_metrics(test_data[[VARIAVEL_ALVO]], probability, tuning$threshold)

    output[[i]] <- data.frame(
      resample = names(outer_splits)[i],
      selected_id = tuning$config$id,
      criterio_divisao = ifelse(tuning$config$criterio_divisao == "gini", "Gini", "Informacao"),
      cp = tuning$config$cp,
      minsplit = tuning$config$minsplit,
      maxdepth = tuning$config$maxdepth,
      threshold = tuning$threshold,
      t(metrics),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, output)
}

# -----------------------------------------------------------------------------
# Testes 5x2cv: Gini versus ganho de informacao
# -----------------------------------------------------------------------------

decision_tree_5x2cv <- function(data, configs_a, configs_b, seed,
                                 inner_folds, inner_repeats) {
  return(run_paired_5x2cv(
    data, VARIAVEL_ALVO, configs_a, configs_b,
    fit_fn = fit_decision_tree,
    predict_prob_fn = predict_disease_probability,
    tune_fn = tune_decision_tree,
    seed = seed, inner_folds = inner_folds, inner_repeats = inner_repeats
  ))

  set.seed(seed)
  outer_splits <- lapply(
    seq_len(5L),
    function(i) stratified_fold_ids(data[[VARIAVEL_ALVO]], k = 2L)
  )
  differences <- matrix(NA_real_, nrow = 5L, ncol = 2L)
  selected_a <- character(10L)
  selected_b <- character(10L)
  selection_counter <- 1L

  for (repeat_id in seq_len(5L)) {
    split_id <- outer_splits[[repeat_id]]
    for (fold_id in seq_len(2L)) {
      test_index <- which(split_id == fold_id)
      training_data <- data[-test_index, , drop = FALSE]
      test_data <- data[test_index, , drop = FALSE]

      # Cada criterio seleciona seus proprios hiperparametros e limiar usando
      # apenas a metade de treino; a outra metade permanece totalmente externa.
      inner_splits <- make_repeated_folds(
        training_data[[VARIAVEL_ALVO]],
        k = inner_folds,
        repeats = inner_repeats,
        seed = seed + repeat_id * 100L + fold_id * 10L
      )
      tuning_a <- tune_decision_tree(training_data, configs_a, inner_splits)
      tuning_b <- tune_decision_tree(training_data, configs_b, inner_splits)

      model_a <- fit_decision_tree(training_data, tuning_a$config)
      model_b <- fit_decision_tree(training_data, tuning_b$config)
      probability_a <- predict_disease_probability(model_a, test_data)
      probability_b <- predict_disease_probability(model_b, test_data)
      if (anyNA(probability_a) || anyNA(probability_b)) {
        stop("A arvore retornou probabilidade NA no teste 5x2cv.")
      }
      f1_a <- binary_metrics(
        test_data[[VARIAVEL_ALVO]], probability_a, tuning_a$threshold
      )["F1"]
      f1_b <- binary_metrics(
        test_data[[VARIAVEL_ALVO]], probability_b, tuning_b$threshold
      )["F1"]
      if (is.na(f1_a) || is.na(f1_b)) {
        warning(sprintf(
          paste0(
            "5x2cv: F1 indefinido na repeticao %d, metade %d ",
            "(F1_A = %s, F1_B = %s). O teste sera inconclusivo."
          ),
          repeat_id, fold_id, format(f1_a), format(f1_b)
        ))
      }
      differences[repeat_id, fold_id] <- f1_a - f1_b
      selected_a[selection_counter] <- tuning_a$config$id
      selected_b[selection_counter] <- tuning_b$config$id
      selection_counter <- selection_counter + 1L
    }
  }

  dietterich_result <- summarize_dietterich_5x2cv(differences)
  alpaydin_result <- summarize_alpaydin_5x2cv(differences)
  list(
    differences = differences,
    mean_difference = dietterich_result$mean_difference,
    statistic = dietterich_result$statistic,
    df = dietterich_result$df,
    p_value = dietterich_result$p_value,
    reason = dietterich_result$reason,
    alpaydin_f_statistic = alpaydin_result$f_statistic,
    alpaydin_df1 = alpaydin_result$df1,
    alpaydin_df2 = alpaydin_result$df2,
    alpaydin_p_value = alpaydin_result$p_value,
    alpaydin_reason = alpaydin_result$reason,
    selected_a = selected_a,
    selected_b = selected_b
  )
}

# -----------------------------------------------------------------------------
# Execucao
# -----------------------------------------------------------------------------

cat("\n========================================\n")
cat(" Analise de Doencas Cardiacas - UCI\n")
cat(" Modelo: Arvore de Decisao\n")
cat("========================================\n\n")

cat("1. Carregando e preparando a base Heart Disease - Cleveland (UCI)...\n")
raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)
cat(sprintf("   + Total de registros: %d\n", nrow(heart_data)))
cat("   + Distribuicao da classe alvo:\n")
print(table(heart_data[[VARIAVEL_ALVO]]))
cat("   + Valores ausentes antes do ajuste:\n")
print(colSums(is.na(heart_data)))

# cp controla a poda por complexidade; minsplit exige suporte minimo para uma
# divisao; maxdepth limita a profundidade. A grade inclui arvores mais simples
# e mais flexiveis sem tornar a busca excessivamente grande para n = 303.
cp_values <- c(0.001, 0.005, 0.01, 0.02, 0.05)
tree_configs <- expand.grid(
  criterio_divisao = c("gini", "information"),
  cp = cp_values,
  minsplit = c(10L, 20L),
  maxdepth = c(3L, 5L, 7L),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
tree_configs$id <- sprintf(
  "arvore_%s_cp_%s_minsplit_%d_profundidade_%d",
  tree_configs$criterio_divisao,
  format(tree_configs$cp, trim = TRUE, scientific = FALSE),
  tree_configs$minsplit,
  tree_configs$maxdepth
)
CONFIGS <- tree_configs[, c("id", "criterio_divisao", "cp", "minsplit", "maxdepth")]

cat("\n2. Avaliando o modelo com validacao cruzada aninhada...\n")
cat(sprintf(
  "   + Validacao externa: %d-fold estratificado repetido %d vezes\n",
  OUTER_FOLDS, OUTER_REPEATS
))
cat(sprintf(
  "   + Ajuste interno: %d-fold estratificado repetido %d vezes\n",
  INNER_FOLDS, INNER_REPEATS
))
outer_results <- nested_repeated_cv(
  data = heart_data,
  configs = CONFIGS,
  outer_folds = OUTER_FOLDS,
  outer_repeats = OUTER_REPEATS,
  inner_folds = INNER_FOLDS,
  inner_repeats = INNER_REPEATS,
  seed = OUTER_CV_SEED
)

metric_summary <- summarize_metrics(outer_results)
cat(sprintf(
  "   + Metricas de generalizacao (media +/- DP nos %d folds externos):\n",
  nrow(outer_results)
))
print(transform(metric_summary, Media = round(Media, 4), DP = round(DP, 4)), row.names = FALSE)
cat(
  "   + Nota: o DP descreve a variabilidade entre folds sobrepostos; nao e ",
  "erro-padrao de amostras independentes e nao deve ser usado para construir ICs.\n",
  sep = ""
)

cat("\n   + Matriz de confusao agregada dos folds externos repetidos:\n")
cat(sprintf(
  "   + Nota: esta agregacao soma %d predicoes em %d folds; cada paciente contribui %d vezes.\n",
  nrow(heart_data) * OUTER_REPEATS, nrow(outer_results), OUTER_REPEATS
))
print(matrix(
  c(sum(outer_results$TN), sum(outer_results$FP),
    sum(outer_results$FN), sum(outer_results$TP)),
  nrow = 2L, byrow = TRUE,
  dimnames = list(
    Real = c(NEGATIVE_CLASS, POSITIVE_CLASS),
    Predito = c(NEGATIVE_CLASS, POSITIVE_CLASS)
  )
))

cat("\n   + Configuracoes selecionadas nos folds externos:\n")
print(sort(table(outer_results$selected_id), decreasing = TRUE))

cat("\n3. Selecionando a configuracao final com todos os dados...\n")
cat(sprintf(
  "   + Validacao usada no ajuste final: %d-fold estratificado repetido %d vezes\n",
  OUTER_FOLDS, OUTER_REPEATS
))
final_splits <- make_repeated_folds(
  heart_data[[VARIAVEL_ALVO]],
  k = OUTER_FOLDS, repeats = OUTER_REPEATS, seed = FINAL_TUNING_SEED
)
final_tuning <- tune_decision_tree(heart_data, CONFIGS, final_splits)
save_evaluation_artifacts("decision_trees", outer_results, final_tuning$tuning_table)
cat("   + Resultados detalhados salvos em arquivos CSV.\n")
best_config <- final_tuning$config
best_threshold <- final_tuning$threshold
cat("   + Ranking das configuracoes (MCC como criterio primario):\n")
print(transform(
  final_tuning$tuning_table,
  cp = round(cp, 4),
  Mean_MCC = round(Mean_MCC, 4),
  SD_MCC = round(SD_MCC, 4),
  Mean_F1 = round(Mean_F1, 4),
  SD_F1 = round(SD_F1, 4),
  Mean_ROC_AUC = round(Mean_ROC_AUC, 4),
  SD_ROC_AUC = round(SD_ROC_AUC, 4),
  threshold = round(threshold, 3)
), row.names = FALSE)
cat("\n   + Melhor Arvore de Decisao:", config_description(best_config, best_threshold), "\n")

final_model <- fit_decision_tree(heart_data, best_config)
model_output <- list(
  model = final_model,
  configuration = best_config,
  threshold = best_threshold,
  predictors = VARIAVEIS_PREDITORAS,
  target_variable = VARIAVEL_ALVO,
  positive_class = POSITIVE_CLASS,
  negative_class = NEGATIVE_CLASS,
  trained_at = Sys.time(),
  source = "UCI Heart Disease - Cleveland (dataset 45)"
)
dir.create("models", showWarnings = FALSE, recursive = TRUE)
saveRDS(model_output, file = file.path("models", "modelo_decision_tree_heart_disease.rds"))
cat("   + Modelo final salvo em: models/modelo_decision_tree_heart_disease.rds\n")

if (best_config$criterio_divisao == "gini") {
  configs_a <- subset(CONFIGS, criterio_divisao == "gini")
  configs_b <- subset(CONFIGS, criterio_divisao == "information")
  family_a <- "Arvore de Decisao com Gini"
  family_b <- "Arvore de Decisao com ganho de Informacao"
} else {
  configs_a <- subset(CONFIGS, criterio_divisao == "information")
  configs_b <- subset(CONFIGS, criterio_divisao == "gini")
  family_a <- "Arvore de Decisao com ganho de Informacao"
  family_b <- "Arvore de Decisao com Gini"
}

cat("\n4. Executando testes estatisticos 5x2cv...\n")
cat("   + Metrica primaria: F1\n")
cat("   + Nota: o teste de Dietterich foi derivado para taxa de erro; seu uso com F1 e uma extensao usual.\n")
cat("   + A:", family_a, "(hiperparametros e limiar ajustados dentro do treino)\n")
cat("   + B:", family_b, "(hiperparametros e limiar ajustados dentro do treino)\n")
five_x_two <- run_paired_5x2cv(
  heart_data, VARIAVEL_ALVO, configs_a, configs_b,
  fit_fn = fit_decision_tree,
  predict_prob_fn = predict_disease_probability,
  tune_fn = tune_decision_tree,
  seed = DIETTERICH_SEED,
  inner_folds = INNER_FOLDS, inner_repeats = INNER_REPEATS
)
cat("   + Dietterich 5x2cv para MCC (criterio primario de selecao):\n")
print(data.frame(
  Diferenca_media_MCC_A_menos_B = round(five_x_two$tests$MCC$dietterich$mean_difference, 4),
  t = round(five_x_two$tests$MCC$dietterich$statistic, 4),
  gl = five_x_two$tests$MCC$dietterich$df,
  p_valor = round(five_x_two$tests$MCC$dietterich$p_value, 5)
), row.names = FALSE)
cat("   + Dietterich 5x2cv para F1 (metrica complementar):\n")
print(data.frame(
  Diferenca_media_F1_A_menos_B = round(five_x_two$mean_difference, 4),
  t = round(five_x_two$statistic, 4),
  gl = five_x_two$df,
  p_valor = round(five_x_two$p_value, 5)
), row.names = FALSE)
cat("   + F-test combinado de Alpaydin (evidencia complementar):\n")
print(data.frame(
  F = round(five_x_two$alpaydin_f_statistic, 4),
  gl_numerador = five_x_two$alpaydin_df1,
  gl_denominador = five_x_two$alpaydin_df2,
  p_valor = round(five_x_two$alpaydin_p_value, 5)
), row.names = FALSE)
cat("   + Configuracoes escolhidas em A ao longo dos 10 testes:\n")
print(sort(table(five_x_two$selected_a), decreasing = TRUE))
cat("   + Configuracoes escolhidas em B ao longo dos 10 testes:\n")
print(sort(table(five_x_two$selected_b), decreasing = TRUE))
if (is.na(five_x_two$p_value)) {
  if (identical(five_x_two$reason, "undefined_f1")) {
    cat("   + Resultado inconclusivo: pelo menos um F1 nao pode ser calculado em um par 5x2cv.\n")
  } else {
    cat("   + Resultado inconclusivo: as variancias das diferencas foram nulas.\n")
  }
} else if (five_x_two$p_value < 0.05) {
  cat("   + Resultado: diferenca estatisticamente significativa em F1 (alpha = 0.05).\n")
} else {
  cat("   + Resultado: nao ha evidencia de diferenca estatisticamente significativa em F1 (alpha = 0.05).\n")
}
if (is.na(five_x_two$alpaydin_p_value)) {
  cat("   + Alpaydin: resultado inconclusivo devido a F1 indefinido ou variancia nula.\n")
} else if (five_x_two$alpaydin_p_value < 0.05) {
  cat("   + Alpaydin: evidencia complementar de diferenca significativa em F1 (alpha = 0.05).\n")
} else {
  cat("   + Alpaydin: nao ha evidencia complementar de diferenca significativa em F1 (alpha = 0.05).\n")
}

cat("\n========================================\n")
cat(" RESULTADO FINAL DO MODELO\n")
cat("========================================\n")
cat("A estimativa de desempenho esta na validacao externa; o ajuste final\n")
cat("serve somente para gerar o modelo usado em novas previsoes.\n")
report_execution_time()
cat("\nAnalise concluida com sucesso!\n")
cat("========================================\n")
