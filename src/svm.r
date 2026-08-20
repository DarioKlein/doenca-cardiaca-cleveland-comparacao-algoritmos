#!/usr/bin/env Rscript

# Support Vector Machine para a base Heart Disease (Cleveland) da UCI
#
# O script segue o mesmo protocolo dos demais modelos:
#   1. validacao cruzada estratificada externa 10-fold repetida 5 vezes;
#   2. ajuste de hiperparametros, imputacao, padronizacao e limiar somente no
#      treino de cada fold (CV interna estratificada 5-fold repetida 3 vezes);
#   3. media +/- DP das mesmas metricas de avaliacao;
#   4. testes 5x2cv de Dietterich e Alpaydin entre SVM linear e SVM RBF.
#
# A imputacao por moda e a padronizacao z-score sao aprendidas separadamente em
# cada conjunto de treino. Nenhuma estatistica do fold de validacao ou teste e
# usada no pre-processamento.

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
  elapsed_seconds <- as.numeric(difftime(
    Sys.time(), SCRIPT_START_TIME, units = "secs"
  ))
  cat(sprintf("\nTempo total de execucao: %.2f segundos\n", elapsed_seconds))
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

ensure_package("e1071")
ensure_package("withr")
ensure_package("digest")
suppressPackageStartupMessages(library(e1071))
source(file.path("src", "heart_disease_data.r"))
source(file.path("src", "common_evaluation.r"))

software_versions <- function() {
  c(
    R = paste(R.version$major, R.version$minor, sep = "."),
    e1071 = as.character(utils::packageVersion("e1071")),
    withr = as.character(utils::packageVersion("withr")),
    digest = as.character(utils::packageVersion("digest"))
  )
}

VARIAVEIS_COM_IMPUTACAO <- c("vasos_principais", "talassemia")
SEED_ALLOCATOR <- NULL

# -----------------------------------------------------------------------------
# Pre-processamento aprendido apenas no treino
# -----------------------------------------------------------------------------

calculate_factor_mode <- function(variable, variable_name) {
  if (!is.factor(variable)) {
    stop(sprintf(
      "A variavel '%s' deve ser um fator para imputacao por moda.",
      variable_name
    ))
  }

  observed <- variable[!is.na(variable)]
  if (length(observed) == 0L) {
    stop(sprintf("Nao ha valores observados para imputar '%s'.", variable_name))
  }

  counts <- table(factor(observed, levels = levels(variable)))
  counts <- counts[counts > 0L]
  candidates <- names(counts)[counts == max(counts)]
  candidates[1L]
}

learn_preprocessing <- function(training_data) {
  required_variables <- c(VARIAVEIS_COM_IMPUTACAO, VARIAVEIS_NUMERICAS)
  missing_variables <- setdiff(required_variables, names(training_data))
  if (length(missing_variables) > 0L) {
    stop(
      "Variaveis ausentes para o pre-processamento: ",
      paste(missing_variables, collapse = ", ")
    )
  }

  imputation_values <- vapply(
    VARIAVEIS_COM_IMPUTACAO,
    function(variable_name) {
      calculate_factor_mode(training_data[[variable_name]], variable_name)
    },
    character(1)
  )

  imputed_training <- training_data
  for (variable_name in VARIAVEIS_COM_IMPUTACAO) {
    variable <- imputed_training[[variable_name]]
    variable[is.na(variable)] <- imputation_values[[variable_name]]
    imputed_training[[variable_name]] <- variable
  }

  centers <- vapply(
    VARIAVEIS_NUMERICAS,
    function(variable_name) mean(imputed_training[[variable_name]]),
    numeric(1)
  )
  scales <- vapply(
    VARIAVEIS_NUMERICAS,
    function(variable_name) stats::sd(imputed_training[[variable_name]]),
    numeric(1)
  )
  invalid_scales <- !is.finite(scales) | scales <= sqrt(.Machine$double.eps)
  scales[invalid_scales] <- 1

  list(
    method = "moda para fatores ausentes e z-score para variaveis numericas",
    imputation_values = imputation_values,
    numeric_variables = VARIAVEIS_NUMERICAS,
    centers = centers,
    scales = scales,
    constant_numeric_variables = names(scales)[invalid_scales]
  )
}

apply_preprocessing <- function(data, preprocessing) {
  processed_data <- data

  if (!all(VARIAVEIS_COM_IMPUTACAO %in%
           names(preprocessing$imputation_values))) {
    stop("Os valores de imputacao nao contem todas as variaveis necessarias.")
  }

  for (variable_name in VARIAVEIS_COM_IMPUTACAO) {
    variable <- processed_data[[variable_name]]
    if (!is.factor(variable)) {
      stop(sprintf(
        "A variavel '%s' deve ser um fator durante a imputacao.",
        variable_name
      ))
    }
    imputation_value <- unname(
      preprocessing$imputation_values[[variable_name]]
    )
    if (!(imputation_value %in% levels(variable))) {
      stop(sprintf(
        "O valor de imputacao '%s' nao e um nivel valido de '%s'.",
        imputation_value, variable_name
      ))
    }
    variable[is.na(variable)] <- imputation_value
    processed_data[[variable_name]] <- variable
  }

  for (variable_name in preprocessing$numeric_variables) {
    processed_data[[variable_name]] <- (
      processed_data[[variable_name]] - preprocessing$centers[[variable_name]]
    ) / preprocessing$scales[[variable_name]]
  }

  predictors <- processed_data[, VARIAVEIS_PREDITORAS, drop = FALSE]
  if (anyNA(predictors)) {
    stop("Ainda existem valores ausentes apos o pre-processamento do SVM.")
  }
  numeric_values <- unlist(
    predictors[, preprocessing$numeric_variables, drop = FALSE],
    use.names = FALSE
  )
  if (any(!is.finite(numeric_values))) {
    stop("O pre-processamento do SVM produziu valor numerico nao finito.")
  }
  processed_data
}

# -----------------------------------------------------------------------------
# Seeds deterministicas por ajuste
# -----------------------------------------------------------------------------

canonical_task_key <- function(config_id, resample, training_row_ids, phase) {
  fields <- c(
    phase = phase,
    config = config_id,
    resample = resample,
    train_rows = paste(sort(as.character(training_row_ids)), collapse = ",")
  )
  paste0(
    names(fields), "=", nchar(fields, type = "bytes"), ":", fields,
    collapse = "|"
  )
}

new_seed_allocator <- function(master_seed) {
  state <- new.env(parent = emptyenv(), hash = TRUE)
  state$master_seed <- as.integer(master_seed)
  state$key_to_seed <- new.env(parent = emptyenv(), hash = TRUE)
  state$seed_to_key <- new.env(parent = emptyenv(), hash = TRUE)
  state$collisions <- 0L
  state
}

positive_seed <- function(hash_value) {
  as.integer((as.double(hash_value) %% (.Machine$integer.max - 1)) + 1)
}

allocate_task_seed <- function(key) {
  if (is.null(SEED_ALLOCATOR)) {
    stop("O alocador de seeds ainda nao foi inicializado.")
  }
  if (exists(key, envir = SEED_ALLOCATOR$key_to_seed, inherits = FALSE)) {
    return(get(key, envir = SEED_ALLOCATOR$key_to_seed, inherits = FALSE))
  }

  salt <- 0L
  repeat {
    candidate <- positive_seed(digest::digest2int(
      paste0(key, "|salt=", salt), seed = SEED_ALLOCATOR$master_seed
    ))
    candidate_name <- as.character(candidate)
    if (!exists(
      candidate_name, envir = SEED_ALLOCATOR$seed_to_key, inherits = FALSE
    )) {
      assign(key, candidate, envir = SEED_ALLOCATOR$key_to_seed)
      assign(candidate_name, key, envir = SEED_ALLOCATOR$seed_to_key)
      return(candidate)
    }

    occupied_by <- get(
      candidate_name, envir = SEED_ALLOCATOR$seed_to_key, inherits = FALSE
    )
    if (identical(occupied_by, key)) return(candidate)
    SEED_ALLOCATOR$collisions <- SEED_ALLOCATOR$collisions + 1L
    salt <- salt + 1L
  }
}

seed_for_fit <- function(training_data, config, resample, phase) {
  key <- canonical_task_key(
    config$id, resample, rownames(training_data), phase
  )
  allocate_task_seed(key)
}

# -----------------------------------------------------------------------------
# Ajuste, selecao de hiperparametros e limiar
# -----------------------------------------------------------------------------

family_name <- function(kernel) {
  if (identical(kernel, "linear")) {
    "SVM Linear"
  } else if (identical(kernel, "radial")) {
    "SVM RBF"
  } else {
    stop("Kernel desconhecido: ", kernel)
  }
}

build_svm_configs <- function() {
  # Cost usa quatro valores em escala logaritmica, de 0.1 a 100. Para o RBF,
  # gamma inclui valores ao redor de 1 / numero de colunas do model.matrix
  # (aproximadamente 0.05), alem de alternativas mais suaves e mais locais.
  # O kernel linear nao usa gamma.
  cost_values <- c(0.1, 1, 10, 100)
  linear_configs <- data.frame(
    id = paste0("svm_linear_cost_", cost_values),
    kernel = "linear",
    cost = cost_values,
    gamma = NA_real_,
    stringsAsFactors = FALSE
  )
  radial_configs <- expand.grid(
    cost = cost_values,
    gamma = c(0.01, 0.05, 0.1, 0.5),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  radial_configs$id <- sprintf(
    "svm_rbf_cost_%s_gamma_%s",
    radial_configs$cost,
    radial_configs$gamma
  )
  radial_configs$kernel <- "radial"
  radial_configs <- radial_configs[, c("id", "kernel", "cost", "gamma")]
  rbind(linear_configs, radial_configs)
}

fit_svm <- function(training_data, config, svm_seed = NULL,
                    seed_context = "ajuste_direto") {
  preprocessing <- learn_preprocessing(training_data)
  processed_training <- apply_preprocessing(training_data, preprocessing)
  model_data <- processed_training[
    , c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO), drop = FALSE
  ]

  if (is.null(svm_seed)) {
    svm_seed <- seed_for_fit(
      training_data, config, seed_context, "fit"
    )
  }

  # A formula precisa ser o primeiro argumento posicional para que o despacho
  # S3 do e1071 encaminhe corretamente para svm.formula().
  arguments <- list(
    stats::as.formula(paste(VARIAVEL_ALVO, "~ .")),
    data = model_data,
    type = "C-classification",
    kernel = config$kernel,
    cost = as.numeric(config$cost),
    scale = FALSE,
    probability = TRUE,
    fitted = FALSE
  )
  if (identical(config$kernel, "radial")) {
    arguments$gamma <- as.numeric(config$gamma)
  }

  model <- withr::with_seed(
    as.integer(svm_seed),
    do.call(e1071::svm, arguments)
  )

  list(
    model = model,
    preprocessing = preprocessing,
    svm_seed = as.integer(svm_seed)
  )
}

predict_disease_probability <- function(fitted_pipeline, new_data) {
  processed_new_data <- apply_preprocessing(
    new_data, fitted_pipeline$preprocessing
  )
  predictor_data <- processed_new_data[, VARIAVEIS_PREDITORAS, drop = FALSE]
  prediction <- predict(
    fitted_pipeline$model,
    newdata = predictor_data,
    probability = TRUE,
    decision.values = FALSE
  )
  probabilities <- attr(prediction, "probabilities")
  if (is.null(probabilities) ||
      !(POSITIVE_CLASS %in% colnames(probabilities))) {
    stop("A probabilidade da classe positiva nao foi produzida pelo SVM.")
  }
  probability <- as.numeric(probabilities[, POSITIVE_CLASS])
  if (anyNA(probability) || any(!is.finite(probability))) {
    stop("O SVM retornou probabilidade ausente ou nao finita.")
  }
  probability
}

evaluate_config_cv <- function(data, config, folds) {
  predictions <- vector("list", length(folds))
  for (i in seq_along(folds)) {
    test_index <- folds[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]
    model_seed <- seed_for_fit(
      training_data, config, names(folds)[i], "tuning"
    )
    fitted_pipeline <- fit_svm(
      training_data, config, svm_seed = model_seed,
      seed_context = names(folds)[i]
    )
    probability <- predict_disease_probability(fitted_pipeline, test_data)

    predictions[[i]] <- data.frame(
      resample = names(folds)[i],
      truth = as.character(test_data[[VARIAVEL_ALVO]]),
      probability = probability,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, predictions)
}

tune_svm <- function(data, configs, folds) {
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
      familia = family_name(result$config$kernel),
      kernel = result$config$kernel,
      cost = result$config$cost,
      gamma = result$config$gamma,
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

  kernel_complexity <- ifelse(tuning_table$kernel == "linear", 0L, 1L)
  gamma_for_order <- ifelse(
    is.na(tuning_table$gamma), -Inf, tuning_table$gamma
  )
  ordered <- order(
    -ifelse(is.na(tuning_table$Mean_MCC), -Inf, tuning_table$Mean_MCC),
    -ifelse(is.na(tuning_table$Mean_F1), -Inf, tuning_table$Mean_F1),
    -ifelse(
      is.na(tuning_table$Mean_ROC_AUC), -Inf, tuning_table$Mean_ROC_AUC
    ),
    # Em empate exato, prefere fronteira mais simples e maior regularizacao.
    kernel_complexity,
    tuning_table$cost,
    gamma_for_order,
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
  description <- if (identical(config$kernel, "radial")) {
    sprintf(
      "%s (cost = %s, gamma = %s)",
      family_name(config$kernel),
      format(config$cost, trim = TRUE),
      format(config$gamma, trim = TRUE)
    )
  } else {
    sprintf(
      "%s (cost = %s)",
      family_name(config$kernel),
      format(config$cost, trim = TRUE)
    )
  }
  if (!is.null(threshold)) {
    description <- paste0(
      description, "; limiar = ", format(threshold, digits = 3)
    )
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
    tuning <- tune_svm(training_data, configs, inner_splits)
    fitted_pipeline <- fit_svm(
      training_data, tuning$config,
      seed_context = names(outer_splits)[i]
    )
    probability <- predict_disease_probability(fitted_pipeline, test_data)
    metrics <- binary_metrics(
      test_data[[VARIAVEL_ALVO]], probability, tuning$threshold
    )

    output[[i]] <- data.frame(
      resample = names(outer_splits)[i],
      selected_id = tuning$config$id,
      familia = family_name(tuning$config$kernel),
      kernel = tuning$config$kernel,
      cost = tuning$config$cost,
      gamma = tuning$config$gamma,
      threshold = tuning$threshold,
      t(metrics),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, output)
}

# -----------------------------------------------------------------------------
# Execucao
# -----------------------------------------------------------------------------

run_analysis <- function() {
cat("\n========================================\n")
cat(" Analise de Doencas Cardiacas - UCI\n")
cat(" Modelo: Support Vector Machine (SVM)\n")
cat("========================================\n\n")

cat("1. Carregando e preparando a base Heart Disease - Cleveland (UCI)...\n")
raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)
cat(sprintf("   + Total de registros: %d\n", nrow(heart_data)))
cat("   + Distribuicao da classe alvo:\n")
print(table(heart_data[[VARIAVEL_ALVO]]))
cat("   + Valores ausentes antes da imputacao:\n")
print(colSums(is.na(heart_data)))
cat(paste0(
  "   + Imputacao: moda aprendida apenas no treino para ",
  "vasos_principais e talassemia.\n"
))
cat(paste0(
  "   + Padronizacao: z-score aprendido apenas no treino para as ",
  "5 variaveis numericas.\n"
))
cat("   + Tuning sequencial: paralelismo nao habilitado para o SVM.\n")
versions <- software_versions()
cat(sprintf(
  "   + Versoes: %s\n",
  paste(names(versions), versions, sep = "=", collapse = "; ")
))

CONFIGS <- build_svm_configs()

cat("\n2. Avaliando o modelo com validacao cruzada aninhada...\n")
cat(sprintf(
  "   + Validacao externa: %d-fold estratificado repetido %d vezes\n",
  OUTER_FOLDS, OUTER_REPEATS
))
cat(sprintf(
  "   + Ajuste interno: %d-fold estratificado repetido %d vezes\n",
  INNER_FOLDS, INNER_REPEATS
))
cat(sprintf("   + Configuracoes avaliadas: %d\n", nrow(CONFIGS)))
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
print(transform(
  metric_summary, Media = round(Media, 4), DP = round(DP, 4)
), row.names = FALSE)
cat(
  "   + Nota: o DP descreve a variabilidade entre folds sobrepostos; nao e ",
  "erro-padrao de amostras independentes e nao deve ser usado para construir ICs.\n",
  sep = ""
)

cat("\n   + Matriz de confusao agregada dos folds externos repetidos:\n")
cat(sprintf(
  paste0(
    "   + Nota: esta agregacao soma %d predicoes em %d folds; ",
    "cada paciente contribui %d vezes.\n"
  ),
  nrow(heart_data) * OUTER_REPEATS, nrow(outer_results), OUTER_REPEATS
))
print(matrix(
  c(
    sum(outer_results$TN), sum(outer_results$FP),
    sum(outer_results$FN), sum(outer_results$TP)
  ),
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
final_tuning <- tune_svm(heart_data, CONFIGS, final_splits)
save_evaluation_artifacts("svm", outer_results, final_tuning$tuning_table)
cat("   + Resultados detalhados salvos em arquivos CSV.\n")
best_config <- final_tuning$config
best_threshold <- final_tuning$threshold
cat("   + Ranking das configuracoes (MCC como criterio primario):\n")
print(transform(
  final_tuning$tuning_table,
  cost = round(cost, 4),
  gamma = round(gamma, 4),
  Mean_MCC = round(Mean_MCC, 4),
  SD_MCC = round(SD_MCC, 4),
  Mean_F1 = round(Mean_F1, 4),
  SD_F1 = round(SD_F1, 4),
  Mean_ROC_AUC = round(Mean_ROC_AUC, 4),
  SD_ROC_AUC = round(SD_ROC_AUC, 4),
  threshold = round(threshold, 3)
), row.names = FALSE)
cat("\n   + Melhor SVM:", config_description(best_config, best_threshold), "\n")

final_pipeline <- fit_svm(
  heart_data, best_config, seed_context = "modelo_final"
)
model_output <- list(
  model = final_pipeline$model,
  configuration = best_config,
  threshold = best_threshold,
  preprocessing = final_pipeline$preprocessing,
  training_seed = final_pipeline$svm_seed,
  software_versions = software_versions(),
  predictors = VARIAVEIS_PREDITORAS,
  target_variable = VARIAVEL_ALVO,
  positive_class = POSITIVE_CLASS,
  negative_class = NEGATIVE_CLASS,
  trained_at = Sys.time(),
  source = "UCI Heart Disease - Cleveland (dataset 45)"
)
dir.create("models", showWarnings = FALSE, recursive = TRUE)
saveRDS(
  model_output,
  file = file.path("models", "modelo_svm_heart_disease.rds")
)
cat("   + Modelo final salvo em: models/modelo_svm_heart_disease.rds\n")

if (identical(best_config$kernel, "linear")) {
  configs_a <- subset(CONFIGS, kernel == "linear")
  configs_b <- subset(CONFIGS, kernel == "radial")
  family_a <- "SVM Linear"
  family_b <- "SVM RBF"
} else {
  configs_a <- subset(CONFIGS, kernel == "radial")
  configs_b <- subset(CONFIGS, kernel == "linear")
  family_a <- "SVM RBF"
  family_b <- "SVM Linear"
}

cat("\n4. Executando testes estatisticos 5x2cv...\n")
cat("   + Metricas: MCC (primaria) e F1 (complementar)\n")
cat(paste0(
  "   + Nota: o teste de Dietterich foi derivado para taxa de erro; ",
  "seu uso com MCC e F1 e uma extensao pratica.\n"
))
cat("   + A:", family_a, "(hiperparametros e limiar ajustados dentro do treino)\n")
cat("   + B:", family_b, "(hiperparametros e limiar ajustados dentro do treino)\n")
five_x_two <- run_paired_5x2cv(
  heart_data, VARIAVEL_ALVO, configs_a, configs_b,
  fit_fn = fit_svm,
  predict_prob_fn = predict_disease_probability,
  tune_fn = tune_svm,
  seed = DIETTERICH_SEED,
  inner_folds = INNER_FOLDS, inner_repeats = INNER_REPEATS
)

cat("   + Dietterich 5x2cv para MCC:\n")
print(data.frame(
  Diferenca_media_MCC_A_menos_B = round(
    five_x_two$tests$MCC$dietterich$mean_difference, 4
  ),
  t = round(five_x_two$tests$MCC$dietterich$statistic, 4),
  gl = five_x_two$tests$MCC$dietterich$df,
  p_valor = round(five_x_two$tests$MCC$dietterich$p_value, 5)
), row.names = FALSE)
cat("   + Dietterich 5x2cv para F1:\n")
print(data.frame(
  Diferenca_media_F1_A_menos_B = round(
    five_x_two$tests$F1$dietterich$mean_difference, 4
  ),
  t = round(five_x_two$tests$F1$dietterich$statistic, 4),
  gl = five_x_two$tests$F1$dietterich$df,
  p_valor = round(five_x_two$tests$F1$dietterich$p_value, 5)
), row.names = FALSE)
cat("   + F-test combinado de Alpaydin para MCC:\n")
print(data.frame(
  F = round(five_x_two$tests$MCC$alpaydin$f_statistic, 4),
  gl_numerador = five_x_two$tests$MCC$alpaydin$df1,
  gl_denominador = five_x_two$tests$MCC$alpaydin$df2,
  p_valor = round(five_x_two$tests$MCC$alpaydin$p_value, 5)
), row.names = FALSE)
cat("   + F-test combinado de Alpaydin para F1:\n")
print(data.frame(
  F = round(five_x_two$tests$F1$alpaydin$f_statistic, 4),
  gl_numerador = five_x_two$tests$F1$alpaydin$df1,
  gl_denominador = five_x_two$tests$F1$alpaydin$df2,
  p_valor = round(five_x_two$tests$F1$alpaydin$p_value, 5)
), row.names = FALSE)
cat("   + Configuracoes escolhidas em A ao longo dos 10 testes:\n")
print(sort(table(five_x_two$selected_a), decreasing = TRUE))
cat("   + Configuracoes escolhidas em B ao longo dos 10 testes:\n")
print(sort(table(five_x_two$selected_b), decreasing = TRUE))

for (metric_name in c("MCC", "F1")) {
  dietterich_result <- five_x_two$tests[[metric_name]]$dietterich
  alpaydin_result <- five_x_two$tests[[metric_name]]$alpaydin
  if (is.na(dietterich_result$p_value)) {
    cat(sprintf(
      paste0(
        "   + Dietterich para %s: resultado inconclusivo por metrica ",
        "indefinida ou variancia nula.\n"
      ),
      metric_name
    ))
  } else if (dietterich_result$p_value < 0.05) {
    cat(sprintf(
      "   + Dietterich para %s: diferenca estatisticamente significativa (alpha = 0.05).\n",
      metric_name
    ))
  } else {
    cat(sprintf(
      "   + Dietterich para %s: nao ha evidencia de diferenca significativa (alpha = 0.05).\n",
      metric_name
    ))
  }

  if (is.na(alpaydin_result$p_value)) {
    cat(sprintf(
      paste0(
        "   + Alpaydin para %s: resultado inconclusivo por metrica ",
        "indefinida ou variancia nula.\n"
      ),
      metric_name
    ))
  } else if (alpaydin_result$p_value < 0.05) {
    cat(sprintf(
      "   + Alpaydin para %s: evidencia complementar de diferenca significativa (alpha = 0.05).\n",
      metric_name
    ))
  } else {
    cat(sprintf(
      paste0(
        "   + Alpaydin para %s: nao ha evidencia complementar de ",
        "diferenca significativa (alpha = 0.05).\n"
      ),
      metric_name
    ))
  }
}

cat("\n========================================\n")
cat(" RESULTADO FINAL DO MODELO\n")
cat("========================================\n")
cat("A estimativa de desempenho esta na validacao externa; o ajuste final\n")
cat("serve somente para gerar o modelo usado em novas previsoes.\n")
cat(sprintf(
  "Seeds deterministicas alocadas: %d; colisoes resolvidas: %d.\n",
  length(ls(SEED_ALLOCATOR$key_to_seed, all.names = TRUE)),
  SEED_ALLOCATOR$collisions
))
report_execution_time()
cat("\nAnalise concluida com sucesso!\n")
cat("========================================\n")
}

main <- function() {
  SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
  on.exit({
    SEED_ALLOCATOR <<- NULL
  }, add = TRUE)
  run_analysis()
}

if (!isTRUE(getOption("heart_disease.skip_main", FALSE))) {
  main()
}
