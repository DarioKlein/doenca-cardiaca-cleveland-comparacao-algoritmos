# Naive Bayes

## Implementação

O protocolo complementar compara duas configurações do pacote `naivebayes`:

| Identificador | Laplace | Densidade numérica |
|---|---:|---|
| `gaussiano` | 1 | Distribuição gaussiana |
| `kde` | 1 | Estimativa por kernel, `adjust = 1` |

Os valores ausentes são tratados pelo próprio algoritmo. A implementação não
remove registros e não utiliza informações do teste externo durante o ajuste.

## Validação aninhada

O script `src/nested/run_naive_bayes.r` usa 5 folds externos repetidos 3 vezes
e 3 folds internos. Em cada um dos 15 conjuntos de treino externos, as duas
configurações são comparadas pela média interna do MCC. A vencedora é reajustada
no treino externo completo e avaliada no teste externo intocado.

O custo é `15 × (2 × 3 + 1) = 105` ajustes: 90 internos e 15 reajustes
externos. Foram produzidas 909 previsões OOF, uma para cada registro em cada
repetição.

## Resultado complementar

Execução concluída em 7 de setembro de 2026. A configuração gaussiana foi
selecionada em 13 folds externos e a KDE em 2. Os valores abaixo são média ±
desvio-padrão dos 15 folds externos.

| Métrica | Resultado |
|---|---:|
| Acurácia | 0,8328 ± 0,0304 |
| Sensibilidade | 0,7989 ± 0,0813 |
| Especificidade | 0,8618 ± 0,0470 |
| Precisão | 0,8335 ± 0,0432 |
| F1 | 0,8128 ± 0,0391 |
| **MCC** | **0,6667 ± 0,0646** |
| ROC-AUC | 0,9100 ± 0,0215 |
| Brier Score | 0,1325 ± 0,0184 |
| Log Loss | 0,5170 ± 0,0876 |
| Acurácia balanceada | 0,8303 ± 0,0331 |
| Tempo total por fold externo | 0,0526 ± 0,0200 s |

As métricas OOF reunidas por repetição foram:

| Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8350 | 0,8162 | 0,6671 | 0,9055 |
| 2 | 0,8317 | 0,8132 | 0,6605 | 0,9070 |
| 3 | 0,8317 | 0,8132 | 0,6605 | 0,9043 |

O Naive Bayes liderou descritivamente o MCC na Cleveland. No teste pareado,
sua diferença média foi `0,1163` contra a Árvore (`p Holm = 0,4381`), `0,0314`
contra a Random Forest (`p Holm = 1,0000`) e `0,0144` contra a SVM
(`p Holm = 1,0000`). Portanto, a liderança não foi estatisticamente
significativa no protocolo adotado.

## Relação com a análise exploratória

Na avaliação antiga, não aninhada, a configuração gaussiana foi selecionada e
obteve MCC `0,6694`. O MCC complementar de `0,6667` é muito próximo, o que
mantém a interpretação anterior sem depender da mesma CV para selecionar e
avaliar hiperparâmetros.

## Arquivos

Os oito CSVs começam com `naive_bayes_ncv_` e ficam em
`results/cleveland_ncv_5x3_inner3_v1/csvs/`. O manifesto registra 105 ajustes,
versão do R, horários e assinaturas. Os checkpoints RDS permitem retomar a
execução e não são modelos finais de diagnóstico.
