# SVM

## Configuracoes

O script `src/svm.r` usa kernel linear e custos 0,1, 1 e 10. Modas, medias e
desvios-padrao sao aprendidos novamente dentro de cada treino e aplicados ao
fold de teste.

## Validacao

`3 configuracoes x 5 folds x 3 repeticoes = 45 ajustes`.

Em cada repeticao, as previsoes fora da amostra dos cinco folds sao reunidas e
as metricas sao calculadas sobre os 303 pacientes. A configuracao e escolhida
pelo MCC medio das tres repeticoes.

## Resultados oficiais

Execucao realizada pelo pesquisador em **22/08/2026**. Os 45 ajustes e as 909
predicoes fora da amostra foram conferidos nos CSVs.

A configuracao selecionada foi a SVM linear com **custo 1**. Seu MCC medio foi
0,6562; custo 0,1 obteve 0,6360 e custo 10 obteve 0,6339.

| Metrica | Media ± DP |
|---|---:|
| Acuracia | 0,8295 ± 0,0069 |
| Sensibilidade | 0,7914 ± 0,0072 |
| Especificidade | 0,8618 ± 0,0186 |
| Precisao | 0,8295 ± 0,0177 |
| F1 | 0,8099 ± 0,0048 |
| MCC | 0,6562 ± 0,0138 |
| ROC-AUC | 0,8969 ± 0,0035 |
| Brier Score | 0,1256 ± 0,0024 |
| Log Loss | 0,3990 ± 0,0073 |
| Acuracia balanceada | 0,8266 ± 0,0058 |
| Tempo da configuracao por repeticao | 0,0608 ± 0,0033 s |

| Repeticao | Acuracia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8350 | 0,8134 | 0,6674 | 0,8939 |
| 2 | 0,8317 | 0,8118 | 0,6605 | 0,9007 |
| 3 | 0,8218 | 0,8043 | 0,6408 | 0,8961 |

Os resultados apresentaram baixa variacao entre as repeticoes. O tempo
representa os cinco ajustes da configuracao em cada repeticao, nao o tempo total
do script.

## Arquivos

Os cinco CSVs oficiais ficam em `results/csvs/` e usam o prefixo `svm_cv_`.
Nenhum novo RDS foi criado por este protocolo.
