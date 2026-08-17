#!/usr/bin/env Rscript

# Naive Bayes para a base Heart Disease (Cleveland) da UCI
#
# O script faz uma avaliacao honesta do pipeline:
#   1. validacao cruzada estratificada externa 10-fold repetida 5 vezes;
#   2. em CADA fold externo, seleciona configuracao e limiar apenas nos dados
#      de treino (CV interna estratificada 5-fold repetida 3 vezes);
#   3. apresenta media +/- desvio-padrao de Accuracy, Sensitivity,
#      Specificity, F1, MCC, ROC-AUC e PR-AUC;
#   4. executa os testes 5x2cv de Dietterich e Alpaydin entre as familias
#      Gaussian Naive Bayes e Naive Bayes com KDE.
#
# A classe positiva e sempre "doenca". A configuracao escolhida maximiza MCC
# na CV interna; em empate, usa F1 e o limiar mais proximo de 0.5. Isso evita
# escolher o modelo apenas por accuracy em um problema de diagnostico.

options(stringsAsFactors = FALSE)
MASTER_SEED <- 20260804L
OUTER_CV_SEED <- MASTER_SEED
INNER_SEED_STEP <- 1009L
FINAL_TUNING_SEED <- MASTER_SEED + 3571L
DIETTERICH_SEED <- MASTER_SEED + 7919L
OUTER_FOLDS <- 10L
OUTER_REPEATS <- 5L
set.seed(MASTER_SEED)
SCRIPT_START_TIME <- Sys.time()

report_execution_time <- function() {
  elapsed_seconds <- as.numeric(difftime(Sys.time(), SCRIPT_START_TIME, units = "secs"))
  cat(sprintf(
    "\nTempo total de execucao: %.2f segundos\n",
    elapsed_seconds
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

ensure_package("naivebayes")
ensure_package("withr")
suppressPackageStartupMessages(library(naivebayes))

source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))
# -----------------------------------------------------------------------------
# Ajuste, selecao de hiperparametros e limiar
# -----------------------------------------------------------------------------

fit_naive_bayes <- function(training_data, config) {
  arguments <- list(
    x = training_data[, VARIAVEIS_PREDITORAS, drop = FALSE],
    y = training_data$classe_doenca,
    laplace = config$laplace,
    usekernel = config$usekernel
  )
  if (isTRUE(config$usekernel)) arguments$adjust <- config$adjust
  do.call(naivebayes::naive_bayes, arguments)
}

predict_disease_probability <- function(model, new_data) {
  probability <- predict(
    model, newdata = new_data[, VARIAVEIS_PREDITORAS, drop = FALSE], type = "prob"
  )
  if (!(POSITIVE_CLASS %in% colnames(probability))) {
    stop("A probabilidade da classe positiva nao foi produzida pelo modelo.")
  }
  as.numeric(probability[, POSITIVE_CLASS])
}

evaluate_config_cv <- function(data, config, folds) {
  predictions <- vector("list", length(folds))
  for (i in seq_along(folds)) {
    test_index <- folds[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]
    model <- fit_naive_bayes(training_data, config)
    probability <- predict_disease_probability(model, test_data)
    if (anyNA(probability)) stop("O modelo retornou probabilidade NA.")

    predictions[[i]] <- data.frame(
      resample = names(folds)[i],
      truth = as.character(test_data$classe_doenca),
      probability = probability,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, predictions)
}

tune_naive_bayes <- function(data, configs, folds) {
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
      density = ifelse(result$config$usekernel, "KDE", "Gaussian"),
      laplace = result$config$laplace,
      adjust = result$config$adjust,
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
  density <- if (isTRUE(config$usekernel)) "KDE" else "Gaussian"
  description <- sprintf(
    "%s (laplace = %s%s)",
    density,
    format(config$laplace, trim = TRUE),
    if (isTRUE(config$usekernel)) {
      paste0(", adjust = ", format(config$adjust, trim = TRUE))
    } else {
      ""
    }
  )
  if (!is.null(threshold)) {
    description <- paste0(description, "; limiar = ", format(threshold, digits = 3))
  }
  description
}

# -----------------------------------------------------------------------------
# Avaliacao externa (nested repeated stratified 10-fold CV)
# -----------------------------------------------------------------------------

nested_repeated_cv <- function(data, configs, outer_folds, outer_repeats,
                               inner_folds, inner_repeats, seed) {
  outer_splits <- make_repeated_folds(
    data$classe_doenca, k = outer_folds, repeats = outer_repeats, seed = seed
  )
  output <- vector("list", length(outer_splits))

  for (i in seq_along(outer_splits)) {
    message(sprintf("CV externa: %d/%d", i, length(outer_splits)))
    test_index <- outer_splits[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]

    inner_splits <- make_repeated_folds(
      training_data$classe_doenca,
      k = inner_folds,
      repeats = inner_repeats,
      seed = seed + i * INNER_SEED_STEP
    )
    tuning <- tune_naive_bayes(training_data, configs, inner_splits)
    model <- fit_naive_bayes(training_data, tuning$config)
    probability <- predict_disease_probability(model, test_data)
    if (anyNA(probability)) stop("O modelo retornou probabilidade NA na CV externa.")
    metrics <- binary_metrics(test_data$classe_doenca, probability, tuning$threshold)

    output[[i]] <- data.frame(
      resample = names(outer_splits)[i],
      selected_id = tuning$config$id,
      density = ifelse(tuning$config$usekernel, "KDE", "Gaussian"),
      laplace = tuning$config$laplace,
      adjust = tuning$config$adjust,
      threshold = tuning$threshold,
      t(metrics),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, output)
}

dietterich_5x2cv <- function(data, configs_a, configs_b, seed,
                              inner_folds, inner_repeats) {
  return(run_paired_5x2cv(
    data, VARIAVEL_ALVO, configs_a, configs_b,
    fit_fn = fit_naive_bayes,
    predict_prob_fn = predict_disease_probability,
    tune_fn = tune_naive_bayes,
    seed = seed, inner_folds = inner_folds, inner_repeats = inner_repeats
  ))

  set.seed(seed)
  # Gerar todos os cinco splits externos antes dos folds internos torna a
  # sequencia dos sorteios externos explicitamente independente do ajuste.
  outer_splits <- lapply(
    seq_len(5L),
    function(i) stratified_fold_ids(data$classe_doenca, k = 2L)
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

      # Configuracao e limiar de cada familia sao escolhidos apenas no treino
      # da respectiva metade. Portanto, o 5x2cv compara pipelines completos,
      # sem que a metade de teste influencie a selecao de hiperparametros.
      inner_splits <- make_repeated_folds(
        training_data$classe_doenca, k = inner_folds, repeats = inner_repeats,
        seed = seed + repeat_id * 100L + fold_id * 10L
      )
      tuning_a <- tune_naive_bayes(training_data, configs_a, inner_splits)
      tuning_b <- tune_naive_bayes(training_data, configs_b, inner_splits)

      model_a <- fit_naive_bayes(training_data, tuning_a$config)
      model_b <- fit_naive_bayes(training_data, tuning_b$config)
      probability_a <- predict_disease_probability(model_a, test_data)
      probability_b <- predict_disease_probability(model_b, test_data)
      if (anyNA(probability_a) || anyNA(probability_b)) {
        stop("O modelo retornou probabilidade NA no teste 5x2cv.")
      }
      f1_a <- binary_metrics(
        test_data$classe_doenca,
        probability_a,
        tuning_a$threshold
      )["F1"]
      f1_b <- binary_metrics(
        test_data$classe_doenca,
        probability_b,
        tuning_b$threshold
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

  test_result <- summarize_dietterich_5x2cv(differences)
  alpaydin_result <- summarize_alpaydin_5x2cv(differences)

  list(
    differences = differences,
    mean_difference = test_result$mean_difference,
    statistic = test_result$statistic,
    df = test_result$df,
    p_value = test_result$p_value,
    reason = test_result$reason,
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
cat(" Modelo: Naive Bayes\n")
cat("========================================\n\n")

cat("1. Carregando e preparando a base Heart Disease - Cleveland (UCI)...\n")
raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)
cat(sprintf("   + Total de registros: %d\n", nrow(heart_data)))
cat("   + Distribuicao da classe alvo:\n")
print(table(heart_data$classe_doenca))
cat("   + Valores ausentes antes da imputacao:\n")
print(colSums(is.na(heart_data)))

# As configuracoes preservam a natureza mista da base: fatores sao
# categoricos; as 5 medidas continuas sao Gaussianas ou estimadas por KDE.
# Laplace > 0 evita probabilidades nulas quando alguma categoria rara nao
# aparece em um fold de treino, situacao comum nesta amostra pequena.
laplace_values <- c(0.5, 1, 2)
gaussian_configs <- data.frame(
  id = paste0("gaussian_laplace_", laplace_values),
  laplace = laplace_values,
  usekernel = FALSE,
  adjust = NA_real_,
  stringsAsFactors = FALSE
)
kde_configs <- expand.grid(
  laplace = laplace_values,
  adjust = c(0.5, 1, 1.5),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
kde_configs$id <- paste0(
  "kde_laplace_", kde_configs$laplace, "_adjust_", kde_configs$adjust
)
kde_configs$usekernel <- TRUE
kde_configs <- kde_configs[, c("id", "laplace", "usekernel", "adjust")]
CONFIGS <- rbind(gaussian_configs, kde_configs)
INNER_FOLDS <- 5L
INNER_REPEATS <- 3L

cat("\n2. Avaliando o modelo com validacao cruzada aninhada...\n")
cat(sprintf(
  "   + Validacao externa: %d-fold estratificado repetido %d vezes\n",
  OUTER_FOLDS, OUTER_REPEATS
))
cat("   + Ajuste interno: 5-fold estratificado repetido 3 vezes\n")
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

# Ajuste final: usa todos os dados, com repeated stratified 10-fold CV (5x)
# para escolher a configuracao definitiva e o limiar de decisao.
cat("\n3. Selecionando a configuracao final com todos os dados...\n")
cat(sprintf(
  "   + Validacao usada no ajuste final: %d-fold estratificado repetido %d vezes\n",
  OUTER_FOLDS, OUTER_REPEATS
))
final_splits <- make_repeated_folds(
  heart_data$classe_doenca,
  k = OUTER_FOLDS, repeats = OUTER_REPEATS, seed = FINAL_TUNING_SEED
)
final_tuning <- tune_naive_bayes(
  heart_data, CONFIGS, final_splits
)
save_evaluation_artifacts("naive_bayes", outer_results, final_tuning$tuning_table)
cat("   + Resultados detalhados salvos em arquivos CSV.\n")
best_config <- final_tuning$config
best_threshold <- final_tuning$threshold
cat("   + Ranking das configuracoes (MCC como criterio primario):\n")
print(transform(
  final_tuning$tuning_table,
  Mean_MCC = round(Mean_MCC, 4),
  SD_MCC = round(SD_MCC, 4),
  Mean_F1 = round(Mean_F1, 4),
  SD_F1 = round(SD_F1, 4),
  Mean_ROC_AUC = round(Mean_ROC_AUC, 4),
  SD_ROC_AUC = round(SD_ROC_AUC, 4),
  threshold = round(threshold, 3)
), row.names = FALSE)
cat("\n   + Melhor Naive Bayes:", config_description(best_config, best_threshold), "\n")

final_model <- fit_naive_bayes(heart_data, best_config)
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
saveRDS(model_output, file = file.path("models", "modelo_naive_bayes_heart_disease.rds"))
cat("   + Modelo final salvo em: models/modelo_naive_bayes_heart_disease.rds\n")

# Para o 5x2cv, cada familia e ajustada novamente dentro de cada metade de
# treino. Isso e mais correto que escolher uma configuracao usando todos os
# dados e depois testa-la nos mesmos dados.
if (isTRUE(best_config$usekernel)) {
  configs_a <- subset(CONFIGS, usekernel)
  configs_b <- subset(CONFIGS, !usekernel)
  family_a <- "Naive Bayes com KDE"
  family_b <- "Naive Bayes Gaussiano"
} else {
  configs_a <- subset(CONFIGS, !usekernel)
  configs_b <- subset(CONFIGS, usekernel)
  family_a <- "Naive Bayes Gaussiano"
  family_b <- "Naive Bayes com KDE"
}

cat("\n4. Executando testes estatisticos 5x2cv...\n")
cat("   + Metrica primaria: F1\n")
cat("   + Nota: o teste de Dietterich foi derivado para taxa de erro; seu uso com F1 e uma extensao usual.\n")
cat("   + A:", family_a, "(hiperparametros e limiar ajustados dentro do treino)\n")
cat("   + B:", family_b, "(hiperparametros e limiar ajustados dentro do treino)\n")
five_x_two <- run_paired_5x2cv(
  heart_data, VARIAVEL_ALVO, configs_a, configs_b,
  fit_fn = fit_naive_bayes,
  predict_prob_fn = predict_disease_probability,
  tune_fn = tune_naive_bayes,
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
