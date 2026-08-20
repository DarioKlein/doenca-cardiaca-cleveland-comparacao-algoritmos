#!/usr/bin/env Rscript

# Testes focados e rapidos do pipeline Random Forest. Nao geram resultados
# oficiais, CSVs nem modelos; usam uma grade e uma CV reduzidas.

options(heart_disease.skip_main = TRUE)
source(file.path("src", "random_forest.r"))
options(heart_disease.skip_main = NULL)

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

run_reduced_tuning <- function(workers, data, configs, folds) {
  cluster <- NULL
  SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
  on.exit({
    stop_tuning_cluster(cluster)
    TUNING_CLUSTER <<- NULL
    SEED_ALLOCATOR <<- NULL
  }, add = TRUE)

  cluster <- start_tuning_cluster(workers)
  TUNING_CLUSTER <<- cluster
  tuning <- tune_random_forest(data, configs, folds)

  list(
    config = tuning$config,
    threshold = tuning$threshold,
    tuning_table = tuning$tuning_table
  )
}

raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)

# A moda deve ser aprendida no treino e aplicada sem deixar NA.
training_subset <- heart_data[-c(88L, 167L, 193L, 267L, 303L), , drop = FALSE]
imputation_values <- learn_imputation_values(training_subset)
imputed_subset <- apply_imputation_values(training_subset, imputation_values)
assert_true(
  !anyNA(imputed_subset[VARIAVEIS_COM_IMPUTACAO]),
  "A imputacao deixou valores ausentes."
)

reduced_configs <- data.frame(
  id = c("test_gini", "test_extratrees"),
  splitrule = c("gini", "extratrees"),
  num_trees = c(50L, 50L),
  mtry = c(3L, 3L),
  min_node_size = c(10L, 10L),
  stringsAsFactors = FALSE
)
reduced_folds <- make_repeated_folds(
  heart_data[[VARIAVEL_ALVO]], k = 2L, repeats = 1L, seed = MASTER_SEED
)

parallel_workers <- min(2L, resolve_tuning_workers(2L))
sequential_result <- run_reduced_tuning(
  1L, heart_data, reduced_configs, reduced_folds
)
parallel_result_1 <- run_reduced_tuning(
  parallel_workers, heart_data, reduced_configs, reduced_folds
)
parallel_result_2 <- run_reduced_tuning(
  parallel_workers, heart_data, reduced_configs, reduced_folds
)

assert_true(
  identical(sequential_result$config, parallel_result_1$config),
  "A configuracao escolhida mudou com o numero de workers."
)
assert_true(
  identical(sequential_result$threshold, parallel_result_1$threshold),
  "O limiar mudou com o numero de workers."
)
assert_true(
  identical(sequential_result$tuning_table, parallel_result_1$tuning_table),
  "O ranking numerico mudou com o numero de workers."
)
assert_true(
  identical(parallel_result_1, parallel_result_2),
  "Duas execucoes paralelas com a mesma seed produziram resultados diferentes."
)

cat(sprintf(
  paste0(
    "OK: imputacao valida e tuning numericamente identico com 1 e %d workers; ",
    "duas execucoes paralelas identicas.\n"
  ),
  parallel_workers
))
