# Arvore de Decisao

## Configuracoes

O script `src/decision_trees.r` usa criterio de Gini, `minsplit = 20`, `xval =
0`, tres valores de `cp` e duas profundidades maximas, totalizando seis
configuracoes. NAs usam as divisões substitutas do `rpart`.

## Validacao

`6 configuracoes x 5 folds x 3 repeticoes = 90 ajustes`.

Em cada repeticao, as previsoes fora da amostra dos cinco folds sao reunidas e
as metricas sao calculadas sobre os 303 pacientes. A configuracao e escolhida
pelo MCC medio das tres repeticoes.

## Resultados oficiais

Execucao realizada pelo pesquisador em **22/08/2026**. Os 90 ajustes e as 909
predicoes fora da amostra foram conferidos nos CSVs.

A configuracao selecionada usa `cp = 0,01` e profundidade maxima 5. Seu MCC
medio foi 0,5561; a segunda configuracao do ranking (`cp = 0,02`, profundidade
5) obteve 0,5514.

| Metrica | Media ± DP |
|---|---:|
| Acuracia | 0,7800 ± 0,0019 |
| Sensibilidade | 0,7410 ± 0,0144 |
| Especificidade | 0,8130 ± 0,0127 |
| Precisao | 0,7707 ± 0,0086 |
| F1 | 0,7555 ± 0,0039 |
| MCC | 0,5561 ± 0,0037 |
| ROC-AUC | 0,8092 ± 0,0119 |
| Brier Score | 0,1744 ± 0,0025 |
| Log Loss | 0,5487 ± 0,0114 |
| Acuracia balanceada | 0,7770 ± 0,0021 |
| Tempo da configuracao por repeticao | 0,0263 ± 0,0040 s |

| Repeticao | Acuracia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,7789 | 0,7581 | 0,5545 | 0,7966 |
| 2 | 0,7789 | 0,7509 | 0,5535 | 0,8108 |
| 3 | 0,7822 | 0,7574 | 0,5604 | 0,8202 |

A acuracia e o MCC foram estaveis entre as repeticoes. A ROC-AUC apresentou
variacao um pouco maior. O tempo representa os cinco ajustes da configuracao em
cada repeticao, nao o tempo total do script.

## Arquivos

Os cinco CSVs oficiais ficam em `results/csvs/` e usam o prefixo
`decision_trees_cv_`. Nenhum novo RDS foi criado por este protocolo.
