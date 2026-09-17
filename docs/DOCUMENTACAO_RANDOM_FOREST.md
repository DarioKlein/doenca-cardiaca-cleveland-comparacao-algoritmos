# Random Forest

## Implementação

A implementação usa `ranger`, árvores com critério de Gini, `min.node.size =
5`, 300 ou 500 árvores e `mtry` igual a 3 ou 4. Cada ajuste usa uma thread para
manter a execução determinística e evitar paralelismo aninhado. As modas de
`vasos_principais` e `thal` são aprendidas somente no treino correspondente.

## Validação aninhada

O script `src/nested/run_random_forest.r` usa 5 folds externos repetidos 3
vezes e 3 folds internos. A seleção é feita pelo MCC médio interno e o teste
externo permanece intocado até o reajuste final daquele fold.

O custo é `15 × (4 × 3 + 1) = 195` ajustes: 180 internos e 15 reajustes
externos. Foram produzidas 909 previsões OOF.

## Resultado complementar

Execução concluída em 7 de setembro de 2026. A seleção variou entre todas as
configurações, mostrando que a amostra pequena não determina um único conjunto
de hiperparâmetros com grande estabilidade.

| Configuração | Frequência |
|---|---:|
| 300 árvores, `mtry = 3` | 4 |
| 300 árvores, `mtry = 4` | 2 |
| 500 árvores, `mtry = 3` | 5 |
| 500 árvores, `mtry = 4` | 4 |

| Métrica | Média ± DP dos 15 folds externos |
|---|---:|
| Acurácia | 0,8161 ± 0,0545 |
| Sensibilidade | 0,7843 ± 0,1087 |
| Especificidade | 0,8433 ± 0,0763 |
| Precisão | 0,8154 ± 0,0736 |
| F1 | 0,7942 ± 0,0663 |
| **MCC** | **0,6354 ± 0,1104** |
| ROC-AUC | 0,9021 ± 0,0302 |
| Brier Score | 0,1299 ± 0,0181 |
| Log Loss | 0,4095 ± 0,0443 |
| Acurácia balanceada | 0,8138 ± 0,0566 |
| Tempo total por fold externo | 0,4816 ± 0,1553 s |

As métricas OOF reunidas por repetição foram:

| Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8416 | 0,8222 | 0,6806 | 0,9000 |
| 2 | 0,8185 | 0,8000 | 0,6340 | 0,8972 |
| 3 | 0,7888 | 0,7681 | 0,5742 | 0,8927 |

A Random Forest ficou abaixo de Naive Bayes e SVM no MCC médio. Nenhuma
diferença foi significativa: NB − RF teve `p Holm = 1,0000`, Árvore − RF
`p Holm = 0,4381` e RF − SVM `p Holm = 1,0000`. Assim, a hipótese direcional de
superioridade da Random Forest não foi corroborada na Cleveland complementar.

## Relação com a análise exploratória

A avaliação antiga selecionou 500 árvores e `mtry = 4`, com MCC `0,6428`. A
avaliação aninhada obteve `0,6354` e revelou seleção variável entre folds. A
pequena redução é compatível com a separação entre escolha de hiperparâmetros e
avaliação externa.

## Arquivos

Os oito CSVs começam com `random_forest_ncv_` e ficam em
`results/cleveland_ncv_5x3_inner3_v1/csvs/`. O manifesto registra 195 ajustes.
