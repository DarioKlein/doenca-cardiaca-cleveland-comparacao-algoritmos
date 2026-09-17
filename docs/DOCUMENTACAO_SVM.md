# SVM linear

## Implementação

A implementação usa `e1071::svm`, classificação C, kernel linear e custos
`0,1`, `1` e `10`. Os valores ausentes de `vasos_principais` e `thal` são
substituídos por modas aprendidas no treino. As variáveis numéricas são
padronizadas com médias e desvios-padrão aprendidos no mesmo treino. O pacote
recebe `scale = FALSE` porque a transformação já foi feita explicitamente.

## Validação aninhada

O script `src/nested/run_svm.r` usa 5 folds externos repetidos 3 vezes e 3
folds internos. Cada custo é comparado pelo MCC médio interno; o vencedor é
reajustado no treino externo completo e avaliado no teste externo.

O custo é `15 × (3 × 3 + 1) = 150` ajustes: 135 internos e 15 reajustes
externos. Foram produzidas 909 previsões OOF.

## Resultado complementar

Execução concluída em 7 de setembro de 2026. O custo 1 foi selecionado com
maior frequência, mas os três custos venceram ao menos três folds.

| Configuração | Frequência |
|---|---:|
| Custo 0,1 | 3 |
| Custo 1 | 7 |
| Custo 10 | 5 |

| Métrica | Média ± DP dos 15 folds externos |
|---|---:|
| Acurácia | 0,8250 ± 0,0512 |
| Sensibilidade | 0,7797 ± 0,1009 |
| Especificidade | 0,8636 ± 0,0688 |
| Precisão | 0,8341 ± 0,0729 |
| F1 | 0,8016 ± 0,0635 |
| **MCC** | **0,6524 ± 0,1052** |
| ROC-AUC | 0,8983 ± 0,0403 |
| Brier Score | 0,1293 ± 0,0292 |
| Log Loss | 0,4103 ± 0,0838 |
| Acurácia balanceada | 0,8216 ± 0,0530 |
| Tempo total por fold externo | 0,1493 ± 0,0310 s |

As métricas OOF reunidas por repetição foram:

| Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8284 | 0,8074 | 0,6538 | 0,8905 |
| 2 | 0,8350 | 0,8134 | 0,6674 | 0,8979 |
| 3 | 0,8119 | 0,7897 | 0,6204 | 0,8870 |

A SVM ficou em segundo lugar descritivo no MCC e teve a maior especificidade e
precisão. As comparações com NB, Árvore e RF tiveram, respectivamente,
`p Holm = 1,0000`, `0,5241` e `1,0000`; nenhuma diferença foi significativa.

## Relação com a análise exploratória

A avaliação antiga selecionou globalmente custo 1 e obteve MCC `0,6562`. O
resultado aninhado foi `0,6524`, mantendo praticamente a mesma interpretação e
mostrando que custos diferentes podem ser selecionados em amostras de treino
distintas.

## Arquivos

Os oito CSVs começam com `svm_ncv_` e ficam em
`results/cleveland_ncv_5x3_inner3_v1/csvs/`. O manifesto registra 150 ajustes.
