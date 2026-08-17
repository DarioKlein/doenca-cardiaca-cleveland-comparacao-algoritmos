#!/usr/bin/env Rscript

# Random Forest para a base Heart Disease (Cleveland) da UCI
#
# O script segue o mesmo protocolo dos modelos existentes:
#   1. validacao cruzada estratificada externa 10-fold repetida 5 vezes;
#   2. ajuste de hiperparametros, imputacao e limiar somente no treino de cada
#      fold (CV interna estratificada 5-fold repetida 3 vezes);
#   3. media +/- DP das mesmas metricas de avaliacao;
#   4. testes 5x2cv de Dietterich e Alpaydin entre Random Forest com Gini e
#      floresta com divisoes extremamente aleatorizadas (Extra-Trees).
#
# A imputacao por moda e aprendida separadamente em cada conjunto de treino.
# Nenhuma estatistica do fold de validacao ou teste e usada no pre-processamento.

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
# O ranger permanece sequencial. O paralelismo ocorre entre configuracoes,
# onde esta o maior volume de trabalho independente do pipeline.
RANGER_THREADS <- 1L
TUNING_WORKERS <- 12L
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

ensure_package("ranger")
ensure_package("withr")
ensure_package("digest")
ensure_package("foreach")
ensure_package("doParallel")
suppressPackageStartupMessages(library(ranger))
suppressPackageStartupMessages(library(foreach))
suppressPackageStartupMessages(library(doParallel))
source(file.path("src", "heart_disease_data.R"))
source(file.path("src", "common_evaluation.R"))

VARIAVEIS_COM_IMPUTACAO <- c("vasos_principais", "talassemia")
TUNING_CLUSTER <- NULL
SEED_ALLOCATOR <- NULL

# -----------------------------------------------------------------------------
# Imputacao aprendida apenas no treino
# -----------------------------------------------------------------------------

calculate_factor_mode <- function(variable, variable_name) {
  if (!is.factor(variable)) {
    stop(sprintf("A variavel '%s' deve ser um fator para imputacao por moda.", variable_name))
  }

  observed <- variable[!is.na(variable)]
  if (length(observed) == 0L) {
    stop(sprintf("Nao ha valores observados para imputar '%s'.", variable_name))
  }

  counts <- table(factor(observed, levels = levels(variable)))
  counts <- counts[counts > 0L]
  candidates <- names(counts)[counts == max(counts)]
  # Em empate, a ordem predefinida dos niveis do fator torna a escolha
  # deterministica e independente da ordem das linhas.
  candidates[1L]
}

learn_imputation_values <- function(training_data) {
  missing_variables <- setdiff(VARIAVEIS_COM_IMPUTACAO, names(training_data))
  if (length(missing_variables) > 0L) {
    stop("Variaveis ausentes para imputacao: ", paste(missing_variables, collapse = ", "))
  }

  values <- vapply(
    VARIAVEIS_COM_IMPUTACAO,
    function(variable_name) {
      calculate_factor_mode(training_data[[variable_name]], variable_name)
    },
    character(1)
  )
  values
}

apply_imputation_values <- function(data, imputation_values) {
  if (!all(VARIAVEIS_COM_IMPUTACAO %in% names(imputation_values))) {
    stop("Os valores de imputacao nao contem todas as variaveis necessarias.")
  }

  imputed_data <- data
  for (variable_name in VARIAVEIS_COM_IMPUTACAO) {
    variable <- imputed_data[[variable_name]]
    if (!is.factor(variable)) {
      stop(sprintf("A variavel '%s' deve ser um fator durante a imputacao.", variable_name))
    }

    imputation_value <- unname(imputation_values[[variable_name]])
    if (!(imputation_value %in% levels(variable))) {
      stop(sprintf(
        "O valor de imputacao '%s' nao e um nivel valido de '%s'.",
        imputation_value, variable_name
      ))
    }
    variable[is.na(variable)] <- imputation_value
    imputed_data[[variable_name]] <- variable
  }
  imputed_data
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
  # O comprimento explicito de cada campo evita ambiguidades de concatenacao.
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
  # A conversao para double evita overflow com o menor inteiro representavel.
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
    if (!exists(candidate_name, envir = SEED_ALLOCATOR$seed_to_key, inherits = FALSE)) {
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

make_seed_matrix <- function(data, configs, folds) {
  seeds <- matrix(
    NA_integer_, nrow = nrow(configs), ncol = length(folds),
    dimnames = list(configs$id, names(folds))
  )
  for (config_index in seq_len(nrow(configs))) {
    for (fold_index in seq_along(folds)) {
      training_data <- data[-folds[[fold_index]], , drop = FALSE]
      seeds[config_index, fold_index] <- seed_for_fit(
        training_data,
        configs[config_index, , drop = FALSE],
        names(folds)[fold_index],
        "tuning"
      )
    }
  }
  seeds
}

# -----------------------------------------------------------------------------
# Ajuste, selecao de hiperparametros e limiar
# -----------------------------------------------------------------------------

family_name <- function(splitrule) {
  if (identical(splitrule, "gini")) {
    "Random Forest com Gini"
  } else if (identical(splitrule, "extratrees")) {
    "Random Forest Extra-Trees"
  } else {
    stop("Regra de divisao desconhecida: ", splitrule)
  }
}

fit_random_forest <- function(training_data, config, ranger_seed = NULL,
                              seed_context = "ajuste_direto") {
  imputation_values <- learn_imputation_values(training_data)
  imputed_training_data <- apply_imputation_values(training_data, imputation_values)
  model_data <- imputed_training_data[
    , c(VARIAVEIS_PREDITORAS, VARIAVEL_ALVO), drop = FALSE
  ]
  if (anyNA(model_data)) {
    stop("Ainda existem valores ausentes no treino apos a imputacao.")
  }

  if (is.null(ranger_seed)) {
    ranger_seed <- seed_for_fit(
      training_data, config, seed_context, "fit"
    )
  }

  arguments <- list(
    dependent.variable.name = VARIAVEL_ALVO,
    data = model_data,
    num.trees = as.integer(config$num_trees),
    mtry = as.integer(config$mtry),
    min.node.size = as.integer(config$min_node_size),
    splitrule = config$splitrule,
    probability = TRUE,
    replace = TRUE,
    sample.fraction = 1,
    respect.unordered.factors = "order",
    importance = "none",
    write.forest = TRUE,
    oob.error = FALSE,
    num.threads = RANGER_THREADS,
    seed = as.integer(ranger_seed),
    verbose = FALSE
  )
  if (identical(config$splitrule, "extratrees")) {
    # Mantem uma unica divisao aleatoria candidata por variavel. O bootstrap,
    # o tratamento dos fatores e os demais parametros permanecem iguais aos
    # da familia Gini, isolando a regra de divisao na comparacao.
    arguments$num.random.splits <- 1L
  }

  list(
    model = do.call(ranger::ranger, arguments),
    imputation_values = imputation_values,
    ranger_seed = as.integer(ranger_seed)
  )
}

predict_disease_probability <- function(fitted_pipeline, new_data) {
  imputed_new_data <- apply_imputation_values(
    new_data, fitted_pipeline$imputation_values
  )
  predictor_data <- imputed_new_data[, VARIAVEIS_PREDITORAS, drop = FALSE]
  if (anyNA(predictor_data)) {
    stop("Ainda existem valores ausentes nos novos dados apos a imputacao.")
  }

  prediction <- predict(
    fitted_pipeline$model,
    data = predictor_data,
    type = "response",
    num.threads = RANGER_THREADS,
    verbose = FALSE
  )$predictions
  if (is.null(dim(prediction)) || !(POSITIVE_CLASS %in% colnames(prediction))) {
    stop("A probabilidade da classe positiva nao foi produzida pela floresta.")
  }
  as.numeric(prediction[, POSITIVE_CLASS])
}

evaluate_config_cv <- function(data, config, folds, model_seeds = NULL) {
  if (is.null(model_seeds)) {
    model_seeds <- make_seed_matrix(data, config, folds)[1L, ]
  }
  if (length(model_seeds) != length(folds)) {
    stop("O numero de seeds deve ser igual ao numero de folds internos.")
  }
  predictions <- vector("list", length(folds))
  for (i in seq_along(folds)) {
    test_index <- folds[[i]]
    training_data <- data[-test_index, , drop = FALSE]
    test_data <- data[test_index, , drop = FALSE]

    # fit_random_forest aprende as modas somente neste treino. A predicao usa
    # os valores armazenados no pipeline, sem recalcular nada no teste.
    fitted_pipeline <- fit_random_forest(
      training_data, config, ranger_seed = model_seeds[i],
      seed_context = names(folds)[i]
    )
    probability <- predict_disease_probability(fitted_pipeline, test_data)
    if (anyNA(probability)) stop("A floresta retornou probabilidade NA.")

    predictions[[i]] <- data.frame(
      resample = names(folds)[i],
      truth = as.character(test_data[[VARIAVEL_ALVO]]),
      probability = probability,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, predictions)
}

STATIC_WORKER_EXPORTS <- c(
  "RANGER_THREADS", "VARIAVEIS_COM_IMPUTACAO", "VARIAVEIS_PREDITORAS",
  "VARIAVEL_ALVO", "POSITIVE_CLASS", "calculate_factor_mode",
  "learn_imputation_values", "apply_imputation_values", "fit_random_forest",
  "predict_disease_probability", "evaluate_config_cv"
)

start_tuning_cluster <- function(workers) {
  cluster <- parallel::makeCluster(as.integer(workers), type = "PSOCK")
  tryCatch({
    doParallel::registerDoParallel(cluster)
    invisible(parallel::clusterEvalQ(cluster, {
      suppressPackageStartupMessages(library(ranger))
      NULL
    }))
    parallel::clusterExport(
      cluster, STATIC_WORKER_EXPORTS, envir = .GlobalEnv
    )
    cluster
  }, error = function(error) {
    try(parallel::stopCluster(cluster), silent = TRUE)
    stop(error)
  })
}

stop_tuning_cluster <- function(cluster) {
  if (!is.null(cluster)) {
    try(parallel::stopCluster(cluster), silent = TRUE)
  }
  foreach::registerDoSEQ()
  invisible(NULL)
}

tune_random_forest <- function(data, configs, folds) {
  if (is.null(TUNING_CLUSTER)) {
    stop("O cluster de tuning ainda nao foi inicializado.")
  }
  seed_matrix <- make_seed_matrix(data, configs, folds)

  # Dados e folds mudam em cada treino externo, mas sao enviados somente uma
  # vez por worker nesta chamada. Cada tarefa recebe depois apenas seu indice.
  transfer_environment <- list2env(list(
    worker_tuning_data = data,
    worker_tuning_configs = configs,
    worker_tuning_folds = folds,
    worker_tuning_seeds = seed_matrix
  ), parent = emptyenv())
  dynamic_exports <- c(
    "worker_tuning_data", "worker_tuning_configs",
    "worker_tuning_folds", "worker_tuning_seeds"
  )
  parallel::clusterExport(
    TUNING_CLUSTER, dynamic_exports, envir = transfer_environment
  )

  oof_by_config <- foreach::foreach(
    i = seq_len(nrow(configs)),
    .inorder = TRUE,
    .packages = "ranger",
    .noexport = c(STATIC_WORKER_EXPORTS, dynamic_exports)
  ) %dopar% {
    evaluate_config_cv(
      worker_tuning_data,
      worker_tuning_configs[i, , drop = FALSE],
      worker_tuning_folds,
      worker_tuning_seeds[i, ]
    )
  }

  # Limiar, metricas, ranking e desempates permanecem no processo mestre e
  # seguem exatamente a mesma ordem deterministica da grade original.
  all_results <- vector("list", nrow(configs))
  for (i in seq_len(nrow(configs))) {
    config <- configs[i, , drop = FALSE]
    oof <- oof_by_config[[i]]
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
      familia = family_name(result$config$splitrule),
      splitrule = result$config$splitrule,
      num_trees = result$config$num_trees,
      mtry = result$config$mtry,
      min_node_size = result$config$min_node_size,
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
    # Em empate exato, prefere menor custo e arvores mais regularizadas.
    tuning_table$num_trees,
    -tuning_table$min_node_size,
    abs(tuning_table$mtry - sqrt(length(VARIAVEIS_PREDITORAS))),
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
  description <- sprintf(
    "%s (ntree = %d, mtry = %d, node size = %d)",
    family_name(config$splitrule),
    as.integer(config$num_trees),
    as.integer(config$mtry),
    as.integer(config$min_node_size)
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
    tuning <- tune_random_forest(training_data, configs, inner_splits)
    fitted_pipeline <- fit_random_forest(training_data, tuning$config)
    probability <- predict_disease_probability(fitted_pipeline, test_data)
    if (anyNA(probability)) {
      stop("A floresta retornou probabilidade NA na CV externa.")
    }
    metrics <- binary_metrics(
      test_data[[VARIAVEL_ALVO]], probability, tuning$threshold
    )

    output[[i]] <- data.frame(
      resample = names(outer_splits)[i],
      selected_id = tuning$config$id,
      familia = family_name(tuning$config$splitrule),
      splitrule = tuning$config$splitrule,
      num_trees = tuning$config$num_trees,
      mtry = tuning$config$mtry,
      min_node_size = tuning$config$min_node_size,
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
cat(" Modelo: Random Forest\n")
cat("========================================\n\n")

cat("1. Carregando e preparando a base Heart Disease - Cleveland (UCI)...\n")
raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)
cat(sprintf("   + Total de registros: %d\n", nrow(heart_data)))
cat("   + Distribuicao da classe alvo:\n")
print(table(heart_data[[VARIAVEL_ALVO]]))
cat("   + Valores ausentes antes da imputacao:\n")
print(colSums(is.na(heart_data)))
cat(
  "   + Imputacao: moda aprendida apenas no treino para vasos_principais e talassemia.\n"
)
cat(sprintf("   + Threads internas do ranger: %d\n", RANGER_THREADS))
cat(sprintf("   + Workers paralelos no tuning: %d\n", TUNING_WORKERS))

# A grade cobre valores em torno de sqrt(13) para mtry, diferentes niveis de
# regularizacao das folhas e duas quantidades de arvores suficientemente altas
# para estabilizar as probabilidades sem ampliar excessivamente a busca.
forest_configs <- expand.grid(
  splitrule = c("gini", "extratrees"),
  num_trees = c(500L, 1000L),
  mtry = c(3L, 4L, 6L),
  min_node_size = c(1L, 5L, 10L),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
forest_configs$id <- sprintf(
  "random_forest_%s_ntree_%d_mtry_%d_node_size_%d",
  forest_configs$splitrule,
  forest_configs$num_trees,
  forest_configs$mtry,
  forest_configs$min_node_size
)
CONFIGS <- forest_configs[
  , c("id", "splitrule", "num_trees", "mtry", "min_node_size")
]

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
final_tuning <- tune_random_forest(heart_data, CONFIGS, final_splits)
save_evaluation_artifacts("random_forest", outer_results, final_tuning$tuning_table)
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
cat("\n   + Melhor Random Forest:", config_description(best_config, best_threshold), "\n")

final_pipeline <- fit_random_forest(heart_data, best_config)
model_output <- list(
  model = final_pipeline$model,
  configuration = best_config,
  threshold = best_threshold,
  preprocessing = list(
    method = "moda calculada no conjunto de treino",
    variables = VARIAVEIS_COM_IMPUTACAO,
    imputation_values = final_pipeline$imputation_values
  ),
  training_seed = final_pipeline$ranger_seed,
  model_threads = RANGER_THREADS,
  predictors = VARIAVEIS_PREDITORAS,
  target_variable = VARIAVEL_ALVO,
  positive_class = POSITIVE_CLASS,
  negative_class = NEGATIVE_CLASS,
  trained_at = Sys.time(),
  source = "UCI Heart Disease - Cleveland (dataset 45)"
)
dir.create("models", showWarnings = FALSE, recursive = TRUE)
saveRDS(model_output, file = file.path("models", "modelo_random_forest_heart_disease.rds"))
cat("   + Modelo final salvo em: models/modelo_random_forest_heart_disease.rds\n")

if (best_config$splitrule == "gini") {
  configs_a <- subset(CONFIGS, splitrule == "gini")
  configs_b <- subset(CONFIGS, splitrule == "extratrees")
  family_a <- "Random Forest com Gini"
  family_b <- "Random Forest Extra-Trees"
} else {
  configs_a <- subset(CONFIGS, splitrule == "extratrees")
  configs_b <- subset(CONFIGS, splitrule == "gini")
  family_a <- "Random Forest Extra-Trees"
  family_b <- "Random Forest com Gini"
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
  fit_fn = fit_random_forest,
  predict_prob_fn = predict_disease_probability,
  tune_fn = tune_random_forest,
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
      "   + Dietterich para %s: resultado inconclusivo por metrica indefinida ou variancia nula.\n",
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
      "   + Alpaydin para %s: resultado inconclusivo por metrica indefinida ou variancia nula.\n",
      metric_name
    ))
  } else if (alpaydin_result$p_value < 0.05) {
    cat(sprintf(
      "   + Alpaydin para %s: evidencia complementar de diferenca significativa (alpha = 0.05).\n",
      metric_name
    ))
  } else {
    cat(sprintf(
      "   + Alpaydin para %s: nao ha evidencia complementar de diferenca significativa (alpha = 0.05).\n",
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
  cluster <- NULL
  SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
  on.exit({
    stop_tuning_cluster(cluster)
    TUNING_CLUSTER <<- NULL
    SEED_ALLOCATOR <<- NULL
  }, add = TRUE)

  cluster <- start_tuning_cluster(TUNING_WORKERS)
  TUNING_CLUSTER <<- cluster
  run_analysis()
}

main()
