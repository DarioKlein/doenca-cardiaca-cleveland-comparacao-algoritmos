#!/usr/bin/env Rscript

# Testes reduzidos do pipeline SVM. Nao geram resultados oficiais, CSVs nem
# modelos e nao executam a validacao cruzada completa.

options(heart_disease.skip_main = TRUE)
source(file.path("src", "svm.r"))
options(heart_disease.skip_main = NULL)

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

run_reduced_tuning <- function(data, configs, folds) {
  SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
  on.exit({
    SEED_ALLOCATOR <<- NULL
  }, add = TRUE)
  tuning <- tune_svm(data, configs, folds)
  list(
    config = tuning$config,
    threshold = tuning$threshold,
    tuning_table = tuning$tuning_table
  )
}

raw_data <- read_uci_heart_disease()
heart_data <- prepare_heart_disease(raw_data)
production_configs <- build_svm_configs()
assert_true(
  nrow(production_configs) == 20L &&
    sum(production_configs$kernel == "linear") == 4L &&
    sum(production_configs$kernel == "radial") == 16L,
  "A grade de producao do SVM nao contem as 20 configuracoes esperadas."
)
reduced_folds <- make_repeated_folds(
  heart_data[[VARIAVEL_ALVO]], k = 2L, repeats = 1L, seed = MASTER_SEED
)

test_index <- reduced_folds[[1L]]
training_data <- heart_data[-test_index, , drop = FALSE]
test_data <- heart_data[test_index, , drop = FALSE]
preprocessing <- learn_preprocessing(training_data)
processed_training <- apply_preprocessing(training_data, preprocessing)
processed_test <- apply_preprocessing(test_data, preprocessing)

assert_true(
  !anyNA(processed_training[, VARIAVEIS_PREDITORAS, drop = FALSE]),
  "A imputacao deixou valores ausentes no treino."
)
assert_true(
  !anyNA(processed_test[, VARIAVEIS_PREDITORAS, drop = FALSE]),
  "A imputacao deixou valores ausentes no teste."
)
assert_true(
  isTRUE(all.equal(
    unname(preprocessing$centers),
    unname(vapply(training_data[VARIAVEIS_NUMERICAS], mean, numeric(1)))
  )),
  "Os centros da padronizacao nao foram calculados apenas no treino."
)
assert_true(
  max(abs(vapply(
    processed_training[VARIAVEIS_NUMERICAS], mean, numeric(1)
  ))) < 1e-12,
  "As variaveis numericas do treino nao ficaram centradas em zero."
)

reduced_configs <- data.frame(
  id = c("test_svm_linear", "test_svm_rbf"),
  kernel = c("linear", "radial"),
  cost = c(1, 1),
  gamma = c(NA_real_, 0.05),
  stringsAsFactors = FALSE
)

SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
fitted_pipeline <- fit_svm(
  training_data, reduced_configs[1L, , drop = FALSE],
  seed_context = "teste_probabilidade"
)
probability <- predict_disease_probability(fitted_pipeline, test_data)
SEED_ALLOCATOR <<- NULL
assert_true(
  length(probability) == nrow(test_data) &&
    all(is.finite(probability)) &&
    all(probability >= 0 & probability <= 1),
  "O SVM nao produziu probabilidades validas."
)

result_1 <- run_reduced_tuning(heart_data, reduced_configs, reduced_folds)
result_2 <- run_reduced_tuning(heart_data, reduced_configs, reduced_folds)
assert_true(
  identical(result_1, result_2),
  "Duas execucoes do tuning SVM com a mesma seed produziram resultados diferentes."
)

SEED_ALLOCATOR <<- new_seed_allocator(MASTER_SEED)
nested_result <- nested_repeated_cv(
  heart_data, reduced_configs,
  outer_folds = 2L, outer_repeats = 1L,
  inner_folds = 2L, inner_repeats = 1L,
  seed = MASTER_SEED
)
assert_true(
  nrow(nested_result) == 2L &&
    all(COMMON_METRICS %in% names(nested_result)),
  "A validacao aninhada reduzida nao produziu a estrutura esperada."
)

paired_result <- run_paired_5x2cv(
  heart_data, VARIAVEL_ALVO,
  configs_a = reduced_configs[1L, , drop = FALSE],
  configs_b = reduced_configs[2L, , drop = FALSE],
  fit_fn = fit_svm,
  predict_prob_fn = predict_disease_probability,
  tune_fn = tune_svm,
  seed = DIETTERICH_SEED,
  inner_folds = 2L,
  inner_repeats = 1L
)
assert_true(
  all(c("MCC", "F1") %in% names(paired_result$tests)) &&
    length(paired_result$selected_a) == 10L &&
    length(paired_result$selected_b) == 10L,
  "O 5x2cv reduzido nao produziu a estrutura esperada."
)
SEED_ALLOCATOR <<- NULL

cat(paste0(
  "OK: imputacao e padronizacao treinadas dentro do fold; probabilidades ",
  paste0(
    "validas; duas execucoes reduzidas numericamente identicas; CV aninhada ",
    "e 5x2cv compativeis.\n"
  )
))
