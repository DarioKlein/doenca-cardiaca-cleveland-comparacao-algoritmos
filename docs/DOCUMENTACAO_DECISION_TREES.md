# Árvore de Decisão

## Implementação

A implementação usa `rpart`, critério de Gini, `minsplit = 20` e `xval = 0`.
A grade possui seis combinações: `cp` igual a 0,005, 0,01 ou 0,02 e
profundidade máxima igual a 3 ou 5. Os valores ausentes podem ser tratados
pelas divisões substitutas do `rpart`.

## Validação aninhada

O script `src/nested/run_decision_trees.r` usa 5 folds externos repetidos 3
vezes e 3 folds internos. Cada configuração é ranqueada pelo MCC médio interno;
somente a selecionada é reajustada no treino externo completo e avaliada no
teste externo.

O custo é `15 × (6 × 3 + 1) = 285` ajustes: 270 internos e 15 reajustes
externos. Foram produzidas 909 previsões OOF.

## Resultado complementar

Execução concluída em 7 de setembro de 2026. As seleções nos 15 folds foram:

| Configuração | Frequência |
|---|---:|
| `cp = 0,005`, profundidade 3 | 8 |
| `cp = 0,005`, profundidade 5 | 5 |
| `cp = 0,01`, profundidade 5 | 1 |
| `cp = 0,02`, profundidade 5 | 1 |

| Métrica | Média ± DP dos 15 folds externos |
|---|---:|
| Acurácia | 0,7745 ± 0,0566 |
| Sensibilidade | 0,7363 ± 0,1103 |
| Especificidade | 0,8068 ± 0,0810 |
| Precisão | 0,7689 ± 0,0722 |
| F1 | 0,7473 ± 0,0702 |
| **MCC** | **0,5504 ± 0,1155** |
| ROC-AUC | 0,8049 ± 0,0536 |
| Brier Score | 0,1767 ± 0,0363 |
| Log Loss | 0,6652 ± 0,4527 |
| Acurácia balanceada | 0,7715 ± 0,0585 |
| Tempo total por fold externo | 0,1250 ± 0,0246 s |

As métricas OOF reunidas por repetição foram:

| Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,7921 | 0,7692 | 0,5805 | 0,7891 |
| 2 | 0,7756 | 0,7463 | 0,5468 | 0,8095 |
| 3 | 0,7558 | 0,7338 | 0,5082 | 0,8065 |

A Árvore apresentou o menor MCC médio e maior variabilidade. Mesmo assim, não
houve diferença significativa após Holm: Árvore − Random Forest teve
`p = 0,4381`, Árvore − SVM `p = 0,5241` e Naive Bayes − Árvore `p = 0,4381`.
O modelo permanece útil como baseline interpretável, mas a simplicidade da
árvore isolada limita sua flexibilidade preditiva.

## Relação com a análise exploratória

A avaliação antiga selecionou uma única configuração global (`cp = 0,01`,
profundidade 5) e obteve MCC `0,5561`. Na avaliação aninhada, a configuração
varia por treino externo e o MCC médio foi `0,5504`, mantendo a mesma conclusão
descritiva.

## Arquivos

Os oito CSVs começam com `decision_trees_ncv_` e ficam em
`results/cleveland_ncv_5x3_inner3_v1/csvs/`. O manifesto registra 285 ajustes.
