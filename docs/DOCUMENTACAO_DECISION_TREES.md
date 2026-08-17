# Análise de Doença Cardíaca — Árvore de Decisão

## Objetivo

Este experimento prevê a presença de doença cardíaca na base **Heart Disease — Cleveland** do [UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/45/heart+disease). O arquivo utilizado contém 303 pacientes.

A variável-alvo original `num` foi convertida para:

- `sem_doenca`: `num = 0`;
- `doenca`: `num > 0`.

O modelo avaliado é uma Árvore de Decisão de classificação, com comparação entre os critérios de divisão Gini e ganho de informação.

## Arquivos relacionados

| Caminho | Finalidade |
|---|---|
| `src/decision_trees.r` | Pipeline completo da árvore: ajuste, validação, métricas, testes estatísticos e salvamento. |
| `src/heart_disease_data.r` | Carregamento, cache, validação e preparação da base Cleveland. |
| `src/common_evaluation.r` | Folds, métricas, seleção de limiar, 5x2cv e geração dos CSVs. |
| `models/modelo_decision_tree_heart_disease.rds` | Modelo final treinado com todos os dados. |
| `results/decision_trees_*.csv` | Resultados por fold, ranking de hiperparâmetros e matriz de confusão agregada. |

## Biblioteca

O algoritmo usa o pacote `rpart`:

```r
rpart::rpart(..., method = "class")
```

Ele constrói árvores de classificação e permite controlar a complexidade pelos parâmetros:

| Parâmetro | Papel |
|---|---|
| `criterio_divisao` | Critério usado para escolher cada divisão: `gini` ou `information`. |
| `cp` | Parâmetro de complexidade; valores maiores favorecem árvores mais podadas e simples. |
| `minsplit` | Número mínimo de observações para tentar dividir um nó. |
| `maxdepth` | Profundidade máxima permitida à árvore. |

`xval = 0` é intencional: a validação cruzada é controlada externamente pelo pipeline, não pela validação interna do `rpart`.

## Dados e tratamento de ausências

As variáveis preditoras usam nomes em português, como `idade`, `colesterol_serico`, `frequencia_cardiaca_maxima`, `vasos_principais` e `talassemia`.

Existem seis valores ausentes na base: quatro em `vasos_principais` e dois em `talassemia`. Eles são mantidos. O `rpart` lida com ausências por meio de **surrogate splits**: quando a variável principal de uma divisão está ausente, a árvore pode usar outra variável que se comporte de maneira semelhante para decidir o caminho do paciente. Não é feita imputação global antes dos folds, evitando vazamento de informação.

## Protocolo de avaliação

A avaliação principal usa validação cruzada estratificada aninhada:

- camada externa: 10-fold estratificado, repetido 5 vezes, totalizando 50 folds externos;
- camada interna: 5-fold estratificado, repetido 3 vezes;
- em cada fold externo, hiperparâmetros e limiar são selecionados somente usando os dados de treino;
- a avaliação no fold externo permanece independente da seleção.

O limiar de decisão é escolhido a partir das probabilidades out-of-fold do treino interno, maximizando MCC; F1 e proximidade de 0,5 são usados em desempates.

As métricas reportadas são média ± desvio-padrão nos 50 folds externos. Esse DP descreve a variabilidade entre folds sobrepostos, não o erro-padrão de amostras independentes; ele não deve ser usado diretamente para formar intervalos de confiança.

## Métricas

| Métrica | Resultado da execução local |
|---|---:|
| Accuracy | 0,7848 ± 0,0701 |
| Sensitivity | 0,7091 ± 0,1181 |
| Specificity | 0,8488 ± 0,0935 |
| Precision | 0,8088 ± 0,1022 |
| F1 | 0,7489 ± 0,0848 |
| MCC | 0,5732 ± 0,1440 |
| ROC-AUC | 0,8202 ± 0,0653 |
| PR-AUC | 0,7828 ± 0,0854 |
| Balanced Accuracy | 0,7789 ± 0,0715 |
| NPV | 0,7810 ± 0,0778 |

## Matriz de confusão agregada

| Real \ Predito | Sem doença | Doença |
|---|---:|---:|
| Sem doença | 696 | 124 |
| Doença | 202 | 493 |

Essa matriz soma 1.515 predições (303 pacientes × 5 repetições). Cada paciente contribui cinco vezes; portanto, ela é uma agregação descritiva, não a matriz de um único conjunto de teste.

## Configuração final selecionada

Após o ajuste final em todos os dados, a configuração vencedora foi:

```text
Árvore com Gini
cp = 0,02
minsplit = 20
profundidade máxima = 5
limiar = 0,688
```

O modelo final correspondente foi salvo em `models/modelo_decision_tree_heart_disease.rds`.

## Comparação entre critérios de divisão

O script compara árvores com Gini e com ganho de informação por 5x2cv. Em cada metade de treino, cada família ajusta seus próprios hiperparâmetros e limiar. Assim, a comparação não usa a metade de teste para escolher configurações.

| Métrica | Teste | Estatística | Graus de liberdade | p-valor | Conclusão (α = 0,05) |
|---|---|---:|---|---:|---|
| MCC | Dietterich 5x2cv | t = -0,9391 | 5 | 0,39079 | Não há evidência de diferença significativa. |
| F1 | Dietterich 5x2cv | t = -0,8868 | 5 | 0,41581 | Não há evidência de diferença significativa. |
| F1 | Alpaydın 5x2cv | F = 0,5610 | 10 e 5 | 0,79588 | Não há evidência complementar de diferença significativa. |

As diferenças médias foram `-0,0164` para MCC e `0,0060` para F1, ambas calculadas como Gini menos ganho de informação. Os resultados não sustentam uma superioridade estatística de um critério sobre o outro nesta base.

O teste de Dietterich foi originalmente derivado para taxa de erro; o uso com MCC e F1 é uma extensão prática, interpretada com cautela.

## Tempo de execução

Na execução oficial realizada na máquina do usuário, o pipeline completo levou **304,15 segundos**.

Esse tempo inclui download/leitura da base, validação cruzada aninhada, ajuste final, testes 5x2cv, geração de CSVs e salvamento do modelo. Ele pode variar conforme computador, versões de pacotes e disponibilidade do cache local.

## Como executar

Na raiz do projeto:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\decision_trees.r
```

Os resultados oficiais a serem incluídos nesta documentação devem sempre vir de execução realizada na máquina do usuário. Ao executar novamente após alguma alteração explicitamente solicitada, envie a saída do terminal para atualização deste documento.
