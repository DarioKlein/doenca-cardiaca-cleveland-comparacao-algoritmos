# =============================================================================
# Funcoes comuns de avaliacao para os modelos da base UCI Heart Disease
# =============================================================================
# Este arquivo concentra rotinas independentes do algoritmo: reamostragem
# estratificada, metricas binarias, escolha de limiar, resumos e o calculo do
# teste 5x2cv de Dietterich. Cada script de modelo deve definir previamente
# POSITIVE_CLASS e NEGATIVE_CLASS e garantir que o pacote withr esteja instalado.

COMMON_METRICS <- c(
  "Accuracy", "Sensitivity", "Specificity", "Precision",
  "F1", "MCC", "ROC_AUC", "PR_AUC", "Balanced_Accuracy", "NPV"
)

stratified_fold_ids <- function(y, k) {
  y <- factor(y)
  if (any(table(y) < k)) {
    stop("Cada classe precisa ter pelo menos k observacoes para a CV.")
  }

  fold_id <- integer(length(y))
  for (class_name in levels(y)) {
    index <- which(y == class_name)
    # sample(vetor_numerico_de_tamanho_1) interpreta o valor como 1:valor.
    # sample.int() evita esse comportamento e funciona para qualquer tamanho.
    index <- index[sample.int(length(index), length(index))]
    fold_id[index] <- rep_len(sample(seq_len(k)), length(index))
  }
  fold_id
}

make_repeated_folds <- function(y, k, repeats, seed) {
  # O seed e local a esta funcao: os folds sao reprodutiveis sem alterar o
  # estado do RNG de quem a chamou.
  withr::with_seed(seed, {
    folds <- vector("list", k * repeats)
    fold_names <- character(k * repeats)
    counter <- 1L
    for (repeat_id in seq_len(repeats)) {
      ids <- stratified_fold_ids(y, k)
      for (fold_id in seq_len(k)) {
        folds[[counter]] <- which(ids == fold_id)
        fold_names[counter] <- sprintf("rep%02d_fold%02d", repeat_id, fold_id)
        counter <- counter + 1L
      }
    }
    names(folds) <- fold_names
    folds
  })
}

roc_auc <- function(truth, probability, positive_class = POSITIVE_CLASS) {
  positive <- truth == positive_class
  n_positive <- sum(positive)
  n_negative <- length(positive) - n_positive
  if (n_positive == 0L || n_negative == 0L) return(NA_real_)

  ranks <- rank(probability, ties.method = "average")
  (sum(ranks[positive]) - n_positive * (n_positive + 1) / 2) /
    (n_positive * n_negative)
}

pr_auc <- function(truth, probability, positive_class = POSITIVE_CLASS) {
  positive <- truth == positive_class
  n_positive <- sum(positive)
  if (n_positive == 0L) return(NA_real_)

  ordered <- order(probability, decreasing = TRUE)
  sorted_probability <- probability[ordered]
  sorted_positive <- as.integer(positive[ordered])

  # Observacoes com a mesma probabilidade pertencem ao mesmo degrau da curva
  # PR; isso impede que o PR-AUC dependa da ordem das linhas em caso de empate.
  is_threshold_end <- c(diff(sorted_probability) != 0, TRUE)
  true_positives <- cumsum(sorted_positive)[is_threshold_end]
  false_positives <- cumsum(1L - sorted_positive)[is_threshold_end]
  precision <- true_positives / (true_positives + false_positives)
  recall <- true_positives / n_positive

  # Average Precision: area nao interpolada sob a curva precisao-recall.
  sum(c(recall[1L], diff(recall)) * precision)
}

binary_metrics <- function(truth, probability, threshold,
                           positive_class = POSITIVE_CLASS,
                           negative_class = NEGATIVE_CLASS) {
  truth <- factor(truth, levels = c(negative_class, positive_class))
  predicted <- factor(
    ifelse(probability >= threshold, positive_class, negative_class),
    levels = c(negative_class, positive_class)
  )

  tp <- sum(predicted == positive_class & truth == positive_class)
  tn <- sum(predicted == negative_class & truth == negative_class)
  fp <- sum(predicted == positive_class & truth == negative_class)
  fn <- sum(predicted == negative_class & truth == positive_class)

  sensitivity <- if ((tp + fn) == 0L) NA_real_ else tp / (tp + fn)
  specificity <- if ((tn + fp) == 0L) NA_real_ else tn / (tn + fp)
  precision <- if ((tp + fp) == 0L) NA_real_ else tp / (tp + fp)
  npv <- if ((tn + fn) == 0L) NA_real_ else tn / (tn + fn)
  balanced_accuracy <- if (is.na(sensitivity) || is.na(specificity)) NA_real_ else {
    (sensitivity + specificity) / 2
  }
  f1 <- if (is.na(precision) || is.na(sensitivity) || (precision + sensitivity) == 0) {
    NA_real_
  } else {
    2 * precision * sensitivity / (precision + sensitivity)
  }

  # Converter antes de multiplicar evita overflow de inteiros em R.
  mcc_denominator <- sqrt(prod(as.numeric(c(
    tp + fp, tp + fn, tn + fp, tn + fn
  ))))
  # Para uma matriz de confusao degenerada, adotamos a convencao MCC = 0.
  mcc <- if (mcc_denominator == 0) 0 else {
    (tp * tn - fp * fn) / mcc_denominator
  }

  c(
    Accuracy = (tp + tn) / (tp + tn + fp + fn),
    Sensitivity = sensitivity,
    Specificity = specificity,
    Precision = precision,
    F1 = f1,
    MCC = mcc,
    ROC_AUC = roc_auc(truth, probability, positive_class),
    PR_AUC = pr_auc(truth, probability, positive_class),
    Balanced_Accuracy = balanced_accuracy,
    NPV = npv,
    TP = tp, TN = tn, FP = fp, FN = fn
  )
}

mean_without_na <- function(x) {
  if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
}

sd_without_na <- function(x) {
  if (sum(!is.na(x)) < 2L) NA_real_ else stats::sd(x, na.rm = TRUE)
}

candidate_thresholds <- function(probability) {
  if (any(!is.finite(probability))) {
    stop("As probabilidades devem ser finitas para selecionar o limiar.")
  }

  sorted_unique <- sort(unique(probability))
  margin <- .Machine$double.eps * max(1, max(abs(sorted_unique)))
  if (length(sorted_unique) == 1L) {
    return(c(sorted_unique - margin, sorted_unique + margin))
  }

  midpoints <- (sorted_unique[-1L] + sorted_unique[-length(sorted_unique)]) / 2
  c(sorted_unique[1L] - margin, midpoints, sorted_unique[length(sorted_unique)] + margin)
}

select_threshold <- function(oof_predictions, positive_class = POSITIVE_CLASS) {
  truth <- oof_predictions$truth
  probability <- oof_predictions$probability
  threshold_grid <- candidate_thresholds(probability)
  positive <- truth == positive_class
  n_positive <- sum(positive)
  n_negative <- length(positive) - n_positive

  # Calcula todas as matrizes de confusao em O(n), acumulando grupos de
  # probabilidades unicas em vez de reavaliar os dados para cada limiar.
  sorted_unique <- sort(unique(probability))
  group <- match(probability, sorted_unique)
  positive_by_group <- tabulate(group[positive], nbins = length(sorted_unique))
  total_by_group <- tabulate(group, nbins = length(sorted_unique))
  negative_by_group <- total_by_group - positive_by_group

  tp <- c(n_positive, n_positive - cumsum(positive_by_group))
  fp <- c(n_negative, n_negative - cumsum(negative_by_group))
  fn <- n_positive - tp
  tn <- n_negative - fp

  predicted_positive <- tp + fp
  sensitivity <- if (n_positive == 0L) rep(NA_real_, length(tp)) else tp / n_positive
  specificity <- if (n_negative == 0L) rep(NA_real_, length(tp)) else tn / n_negative
  precision <- ifelse(predicted_positive == 0L, NA_real_, tp / predicted_positive)
  f1 <- ifelse(
    is.na(precision) | is.na(sensitivity) | (precision + sensitivity) == 0,
    NA_real_, 2 * precision * sensitivity / (precision + sensitivity)
  )
  mcc_denominator <- sqrt(
    as.numeric(tp + fp) * as.numeric(tp + fn) *
      as.numeric(tn + fp) * as.numeric(tn + fn)
  )
  mcc <- ifelse(mcc_denominator == 0, 0, (tp * tn - fp * fn) / mcc_denominator)
  npv <- ifelse((tn + fn) == 0, NA_real_, tn / (tn + fn))
  balanced_accuracy <- ifelse(
    is.na(sensitivity) | is.na(specificity), NA_real_, (sensitivity + specificity) / 2
  )
  # Essas duas metricas nao variam com o limiar. Calcula-las separadamente
  # deixa explicito que cada uma e obtida uma unica vez e apenas reciclada na
  # tabela de cortes candidatos.
  roc_auc_value <- roc_auc(truth, probability, positive_class)
  pr_auc_value <- pr_auc(truth, probability, positive_class)
  scores <- data.frame(
    threshold = threshold_grid,
    Accuracy = (tp + tn) / (tp + tn + fp + fn),
    Sensitivity = sensitivity,
    Specificity = specificity,
    Precision = precision,
    F1 = f1,
    MCC = mcc,
    ROC_AUC = roc_auc_value,
    PR_AUC = pr_auc_value,
    Balanced_Accuracy = balanced_accuracy,
    NPV = npv,
    TP = tp, TN = tn, FP = fp, FN = fn
  )

  # MCC e F1 definem o ranking. Em empate, o limiar mais proximo de 0.5 e
  # neutro e nao favorece artificialmente a ordem crescente da grade.
  valid_mcc <- ifelse(is.na(scores$MCC), -Inf, scores$MCC)
  valid_f1 <- ifelse(is.na(scores$F1), -Inf, scores$F1)
  best_mcc <- max(valid_mcc)
  tied_mcc <- which(valid_mcc == best_mcc)
  best_f1 <- max(valid_f1[tied_mcc])
  tied_f1 <- tied_mcc[valid_f1[tied_mcc] == best_f1]
  best <- tied_f1[which.min(abs(scores$threshold[tied_f1] - 0.5))]
  stopifnot(length(threshold_grid) == length(tp))

  list(threshold = scores$threshold[best], threshold_scores = scores)
}

metrics_by_resample <- function(oof_predictions, threshold,
                                positive_class = POSITIVE_CLASS,
                                negative_class = NEGATIVE_CLASS) {
  result <- lapply(split(oof_predictions, oof_predictions$resample), function(prediction) {
    binary_metrics(
      prediction$truth, prediction$probability, threshold,
      positive_class = positive_class, negative_class = negative_class
    )
  })
  output <- as.data.frame(do.call(rbind, result))
  output$resample <- rownames(output)
  rownames(output) <- NULL
  output
}

summarize_metrics <- function(metrics_data, metrics = COMMON_METRICS) {
  data.frame(
    Metrica = metrics,
    Media = vapply(metrics, function(metric) mean_without_na(metrics_data[[metric]]), numeric(1)),
    DP = vapply(metrics, function(metric) sd_without_na(metrics_data[[metric]]), numeric(1)),
    row.names = NULL
  )
}

save_evaluation_artifacts <- function(prefix, outer_results, tuning_table,
                                      results_directory = "results",
                                      negative_class = NEGATIVE_CLASS,
                                      positive_class = POSITIVE_CLASS) {
  confusion_matrix <- matrix(
    c(sum(outer_results$TN), sum(outer_results$FP),
      sum(outer_results$FN), sum(outer_results$TP)),
    nrow = 2L, byrow = TRUE,
    dimnames = list(Real = c(negative_class, positive_class),
                    Predito = c(negative_class, positive_class))
  )
  dir.create(results_directory, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(outer_results, file.path(results_directory, paste0(prefix, "_resultados_folds.csv")), row.names = FALSE)
  utils::write.csv(tuning_table, file.path(results_directory, paste0(prefix, "_ranking_hiperparametros.csv")), row.names = FALSE)
  utils::write.csv(as.data.frame.matrix(confusion_matrix),
                   file.path(results_directory, paste0(prefix, "_matriz_confusao_agregada.csv")), row.names = TRUE)
}

summarize_dietterich_5x2cv <- function(differences) {
  if (anyNA(differences)) {
    return(list(
      mean_difference = NA_real_, statistic = NA_real_, df = 5L,
      p_value = NA_real_, reason = "undefined_f1"
    ))
  }

  # Teste t 5x2cv original de Dietterich: usa a primeira diferenca e as
  # cinco estimativas de variancia; nao e um t-test pareado comum entre folds.
  mean_difference_by_repeat <- rowMeans(differences)
  variance_by_repeat <- rowSums((differences - mean_difference_by_repeat)^2)
  denominator <- sqrt(mean(variance_by_repeat))
  if (!is.finite(denominator) || denominator == 0) {
    return(list(
      mean_difference = mean(differences), statistic = NA_real_, df = 5L,
      p_value = NA_real_, reason = "zero_variance"
    ))
  }

  statistic <- differences[1L, 1L] / denominator
  list(
    mean_difference = mean(differences), statistic = statistic, df = 5L,
    p_value = 2 * stats::pt(abs(statistic), df = 5L, lower.tail = FALSE),
    reason = NULL
  )
}

summarize_alpaydin_5x2cv <- function(differences) {
  if (anyNA(differences)) {
    return(list(
      f_statistic = NA_real_, df1 = 10L, df2 = 5L,
      p_value = NA_real_, reason = "undefined_f1"
    ))
  }

  # F-test combinado 5x2cv de Alpaydin (1999). Ao contrario do t-test de
  # Dietterich, ele usa as dez diferencas observadas (5 repeticoes x 2 folds).
  mean_difference_by_repeat <- rowMeans(differences)
  variance_by_repeat <- rowSums((differences - mean_difference_by_repeat)^2)
  denominator <- 2 * sum(variance_by_repeat)
  if (!is.finite(denominator) || denominator == 0) {
    return(list(
      f_statistic = NA_real_, df1 = 10L, df2 = 5L,
      p_value = NA_real_, reason = "zero_variance"
    ))
  }

  f_statistic <- sum(differences^2) / denominator
  list(
    f_statistic = f_statistic,
    df1 = 10L,
    df2 = 5L,
    p_value = stats::pf(f_statistic, df1 = 10L, df2 = 5L, lower.tail = FALSE),
    reason = NULL
  )
}

run_paired_5x2cv <- function(data, target_variable, configs_a, configs_b,
                              fit_fn, predict_prob_fn, tune_fn, seed,
                              inner_folds, inner_repeats,
                              metrics = c("MCC", "F1")) {
  metrics <- unique(metrics)
  differences <- stats::setNames(
    lapply(metrics, function(metric) matrix(NA_real_, nrow = 5L, ncol = 2L)),
    metrics
  )
  outer_splits <- withr::with_seed(seed, {
    lapply(seq_len(5L), function(i) stratified_fold_ids(data[[target_variable]], k = 2L))
  })
  selected_a <- character(10L)
  selected_b <- character(10L)
  selection_counter <- 1L

  for (repeat_id in seq_len(5L)) {
    split_id <- outer_splits[[repeat_id]]
    for (fold_id in seq_len(2L)) {
      test_index <- which(split_id == fold_id)
      training_data <- data[-test_index, , drop = FALSE]
      test_data <- data[test_index, , drop = FALSE]
      inner_splits <- make_repeated_folds(
        training_data[[target_variable]], k = inner_folds, repeats = inner_repeats,
        seed = seed + repeat_id * 100L + fold_id * 10L
      )
      tuning_a <- tune_fn(training_data, configs_a, inner_splits)
      tuning_b <- tune_fn(training_data, configs_b, inner_splits)
      probability_a <- predict_prob_fn(fit_fn(training_data, tuning_a$config), test_data)
      probability_b <- predict_prob_fn(fit_fn(training_data, tuning_b$config), test_data)
      if (anyNA(probability_a) || anyNA(probability_b)) {
        stop("Um modelo retornou probabilidade NA no teste 5x2cv.")
      }
      metrics_a <- binary_metrics(test_data[[target_variable]], probability_a, tuning_a$threshold)
      metrics_b <- binary_metrics(test_data[[target_variable]], probability_b, tuning_b$threshold)
      for (metric in metrics) {
        value_a <- as.numeric(metrics_a[metric])
        value_b <- as.numeric(metrics_b[metric])
        if (is.na(value_a) || is.na(value_b)) {
          warning(sprintf("5x2cv: %s indefinido na repeticao %d, metade %d.", metric, repeat_id, fold_id))
        }
        differences[[metric]][repeat_id, fold_id] <- value_a - value_b
      }
      selected_a[selection_counter] <- tuning_a$config$id
      selected_b[selection_counter] <- tuning_b$config$id
      selection_counter <- selection_counter + 1L
    }
  }

  tests <- lapply(differences, function(metric_differences) {
    list(
      dietterich = summarize_dietterich_5x2cv(metric_differences),
      alpaydin = summarize_alpaydin_5x2cv(metric_differences)
    )
  })
  # Campos de compatibilidade mantem os scripts legados focados em F1; os
  # resultados completos por metrica ficam em tests$MCC e tests$F1.
  primary <- tests[["F1"]]
  list(
    differences = differences, tests = tests,
    mean_difference = primary$dietterich$mean_difference,
    statistic = primary$dietterich$statistic, df = primary$dietterich$df,
    p_value = primary$dietterich$p_value, reason = primary$dietterich$reason,
    alpaydin_f_statistic = primary$alpaydin$f_statistic,
    alpaydin_df1 = primary$alpaydin$df1, alpaydin_df2 = primary$alpaydin$df2,
    alpaydin_p_value = primary$alpaydin$p_value,
    alpaydin_reason = primary$alpaydin$reason,
    selected_a = selected_a, selected_b = selected_b
  )
}
