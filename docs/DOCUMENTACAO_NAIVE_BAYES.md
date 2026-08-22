# Naive Bayes

## Configuracoes

O script `src/naive_bayes.r` compara Naive Bayes Gaussiano e KDE. Ambos usam
`laplace = 1`; o KDE usa `adjust = 1`. Os valores ausentes sao tratados pelo
algoritmo.

## Validacao

Cada uma das duas configuracoes e ajustada em 5 folds por 3 repeticoes:

`2 configuracoes x 5 folds x 3 repeticoes = 30 ajustes`.

Em cada repeticao, as previsoes fora da amostra dos cinco folds sao reunidas e
as metricas sao calculadas sobre os 303 pacientes. A configuracao e escolhida
pelo MCC medio das tres repeticoes.

## Resultados oficiais

Execucao realizada pelo pesquisador em **22/08/2026**. Os 30 ajustes e as 909
predicoes fora da amostra foram conferidos nos CSVs.

A configuracao selecionada foi o **Naive Bayes Gaussiano**, com `laplace = 1`.
Ela obteve MCC medio de 0,6694, contra 0,6562 do KDE.

| Metrica | Media ± DP |
|---|---:|
| Acuracia | 0,8361 ± 0,0050 |
| Sensibilidade | 0,8010 ± 0,0042 |
| Especificidade | 0,8659 ± 0,0061 |
| Precisao | 0,8350 ± 0,0069 |
| F1 | 0,8176 ± 0,0053 |
| MCC | 0,6694 ± 0,0102 |
| ROC-AUC | 0,9056 ± 0,0008 |
| Brier Score | 0,1319 ± 0,0011 |
| Log Loss | 0,5164 ± 0,0051 |
| Acuracia balanceada | 0,8334 ± 0,0050 |
| Tempo da configuracao por repeticao | 0,0351 ± 0,0361 s |

| Repeticao | Acuracia | F1 | MCC | ROC-AUC |
|---:|---:|---:|---:|---:|
| 1 | 0,8350 | 0,8162 | 0,6671 | 0,9055 |
| 2 | 0,8416 | 0,8235 | 0,6805 | 0,9063 |
| 3 | 0,8317 | 0,8132 | 0,6605 | 0,9048 |

Os valores mostram baixa variacao entre as repeticoes, especialmente na
ROC-AUC. O tempo representa os cinco ajustes da configuracao em cada repeticao,
nao o tempo total do script.

## Arquivos

Os cinco CSVs oficiais ficam em `results/csvs/` e usam o prefixo
`naive_bayes_cv_`. Nenhum novo RDS foi criado por este protocolo.
