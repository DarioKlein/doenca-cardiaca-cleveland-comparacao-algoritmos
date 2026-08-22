# Random Forest

## Configuracoes

O script `src/random_forest.r` usa `ranger`, criterio de Gini, 300 ou 500
arvores e `mtry` 3 ou 4. A execucao usa duas threads. As modas para valores
ausentes sao aprendidas novamente dentro de cada treino.

## Validacao

`4 configuracoes x 5 folds x 3 repeticoes = 60 ajustes`.

Em cada repeticao, as previsoes fora da amostra dos cinco folds sao reunidas e
as metricas sao calculadas sobre os 303 pacientes. A configuracao e escolhida
pelo MCC medio das tres repeticoes.

## Resultados oficiais

Execucao realizada pelo pesquisador em **22/08/2026**. Os 60 ajustes e as 909
predicoes fora da amostra foram conferidos nos CSVs.

A configuracao selecionada usa **500 arvores** e `mtry = 4`. Seu MCC medio foi
0,6428; a configuracao seguinte, com 300 arvores e `mtry = 4`, obteve 0,6384.

| Metrica | Media ± DP |
|---|---:|
| Acuracia | 0,8229 ± 0,0182 |
| Sensibilidade | 0,7914 ± 0,0144 |
| Especificidade | 0,8496 ± 0,0231 |
| Precisao | 0,8171 ± 0,0250 |
| F1 | 0,8040 ± 0,0187 |
| MCC | 0,6428 ± 0,0365 |
| ROC-AUC | 0,8971 ± 0,0058 |
| Brier Score | 0,1295 ± 0,0039 |
| Log Loss | 0,4072 ± 0,0099 |
| Acuracia balanceada | 0,8205 ± 0,0178 |
| Tempo da configuracao por repeticao | 0,1642 ± 0,0039 s |

| Repeticao | Acuracia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8317 | 0,8118 | 0,6605 | 0,9026 |
| 2 | 0,8350 | 0,8175 | 0,6672 | 0,8975 |
| 3 | 0,8020 | 0,7826 | 0,6009 | 0,8911 |

A terceira repeticao reduziu a media e explica o DP maior de MCC e acuracia. O
tempo representa os cinco ajustes da configuracao em cada repeticao, nao o
tempo total do script.

## Arquivos

Os cinco CSVs oficiais ficam em `results/csvs/` e usam o prefixo
`random_forest_cv_`. Nenhum novo RDS foi criado por este protocolo.
