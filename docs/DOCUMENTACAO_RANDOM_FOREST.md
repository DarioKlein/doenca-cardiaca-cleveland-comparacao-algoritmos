# Analise de Doencas Cardiacas - Random Forest

## Objetivo

Este documento registra a avaliacao do modelo Random Forest para prever a presenca de doenca cardiaca na base **Heart Disease UCI - subconjunto Cleveland**. A classe original `num` foi binarizada em:

- `sem_doenca`: `num = 0`;
- `doenca`: `num > 0`.

Os resultados desta pagina foram obtidos na execucao realizada pelo usuario em sua propria maquina.

## Arquivos relacionados

- Script do modelo: `src/random_forest.r`;
- Funcoes de avaliacao compartilhadas: `src/common_evaluation.r`;
- Importacao e preparo dos dados: `src/heart_disease_data.r`;
- Modelo final: `models/modelo_random_forest_heart_disease.rds`;
- Resultados detalhados: arquivos CSV em `results/`.

## Dados e pre-processamento

A base Cleveland possui 303 registros: 164 da classe `sem_doenca` e 139 da classe `doenca`.

Havia seis valores ausentes, todos em variaveis categoricas:

- `vasos_principais`: 4;
- `talassemia`: 2.

A imputacao usa a **moda aprendida exclusivamente nos dados de treino de cada fold**. A mesma moda e depois aplicada aos dados de validacao ou teste daquele fold, sem recalcular estatisticas fora do treino. Assim, evita-se vazamento de informacao entre treino e avaliacao.

## Familias e grade de hiperparametros

Foram comparadas duas familias implementadas pelo pacote `ranger`:

- Random Forest com criterio de Gini (`splitrule = "gini"`);
- Random Forest Extra-Trees (`splitrule = "extratrees"`).

Na segunda familia, `extratrees` altera a regra de escolha dos cortes, com uma
divisao aleatoria candidata por variavel (`num.random.splits = 1`). O bootstrap
e mantido (`replace = TRUE`, `sample.fraction = 1`), assim como o tratamento dos
fatores. Portanto, esta familia deve ser interpretada como **Random Forest com
regra de divisao extremamente aleatorizada**, e nao como uma reproducao literal
do algoritmo Extra-Trees canonico sem bagging.

A grade teve 36 configuracoes, combinando as duas familias com:

| Hiperparametro | Valores |
|---|---|
| `num.trees` | 500, 1000 |
| `mtry` | 3, 4, 6 |
| `min.node.size` | 1, 5, 10 |

Os modelos produzem probabilidades para a classe `doenca`. O limiar de classificacao tambem e ajustado dentro do treino, usando as predicoes out-of-fold do ajuste interno. A selecao prioriza MCC, seguida de F1, ROC-AUC e criterios deterministas de desempate.

## Protocolo de avaliacao

A estimativa principal de generalizacao usa validacao cruzada estratificada aninhada:

- camada externa: 10 folds, repetidos 5 vezes (50 folds externos);
- camada interna: 5 folds, repetidos 3 vezes;
- em cada fold externo, a imputacao, os hiperparametros e o limiar sao definidos apenas a partir do treino externo;
- classe positiva: `doenca`;
- semente-base: `20260804L`.

O criterio principal de selecao e o **MCC**. F1 e ROC-AUC sao usados nos desempates e tambem reportados como medidas complementares. O limiar e escolhido por `select_threshold()`, que avalia os cortes relevantes das probabilidades out-of-fold; nao e usada uma grade arbitraria de limiares.

Depois da avaliacao externa, o modelo destinado a novas previsoes e escolhido
com todos os 303 registros por uma CV estratificada 10-fold repetida 5 vezes.
Essa etapa final usa mais reamostragens do que o ajuste interno 5-fold repetido
3 vezes, pois nao existe nela um fold externo reservado para estimar desempenho.
Naive Bayes e Arvore de Decisao adotam a mesma distincao. A estimativa oficial de
generalizacao continua sendo exclusivamente a dos 50 folds externos.

## Paralelismo e reprodutibilidade

O `ranger` foi mantido com `num.threads = 1L`. O paralelismo e aplicado ao conjunto de configuracoes do tuning, com um cluster PSOCK via `doParallel` e `foreach`. O padrao e 12 workers, limitado automaticamente ao numero de nucleos logicos detectados menos um. O valor pode ser ajustado pela variavel de ambiente `RF_TUNING_WORKERS`. O cluster e encerrado ao final mesmo se ocorrer erro.

Essa foi uma excecao deliberada a preferencia inicial por execucao sequencial:
a versao single-thread levou aproximadamente 42 minutos e o volume total da
grade alcanca 34.271 ajustes do `ranger`. O paralelismo muda apenas a forma de
executar configuracoes independentes, nao o que cada configuracao calcula.

As sementes de cada ajuste sao derivadas de uma chave deterministica que identifica a configuracao, o resample e as linhas de treino. A chave e transformada em inteiro por hash deterministico (`digest::digest2int()`); se necessario, ha resolucao deterministica de colisao. Isso evita depender de somas ou concatenacoes ingenuas de inteiros e torna o resultado reprodutivel ao repetir o script com a mesma semente, dados e versoes de pacotes. Nesta execucao foram alocadas 34.271 sementes deterministicas, sem colisao a resolver.

A execucao oficial registrada anteriormente nao imprimiu as versoes dos pacotes.
A versao atual do script passa a registrar no terminal e no RDS as versoes de R,
`ranger`, `withr`, `digest`, `foreach` e `doParallel`, para que futuras execucoes
possam ser auditadas sem estimar esse dado retrospectivamente.

## Resultados de generalizacao

As metricas abaixo sao a media e o desvio-padrao entre os 50 folds externos.

| Metrica | Media | DP |
|---|---:|---:|
| Accuracy | 0,8137 | 0,0650 |
| Sensitivity | 0,7349 | 0,1182 |
| Specificity | 0,8805 | 0,0818 |
| Precision | 0,8474 | 0,0900 |
| F1 | 0,7806 | 0,0802 |
| MCC | 0,6323 | 0,1317 |
| ROC-AUC | 0,9002 | 0,0574 |
| PR-AUC | 0,8976 | 0,0616 |
| Balanced Accuracy | 0,8077 | 0,0671 |
| NPV | 0,8030 | 0,0772 |

O DP descreve a variabilidade entre folds sobrepostos. Ele nao e um erro-padrao de amostras independentes e nao deve ser usado diretamente para construir intervalos de confianca.

### Matriz de confusao agregada

A matriz agrega as 1.515 predicoes dos 50 folds externos: cada um dos 303 pacientes contribui cinco vezes. Portanto, ela e descritiva e nao representa um unico experimento independente.

| Real \ Predito | sem_doenca | doenca |
|---|---:|---:|
| sem_doenca | 722 | 98 |
| doenca | 184 | 511 |

## Configuracoes selecionadas nos folds externos

A configuracao mais frequentemente escolhida nos 50 folds externos foi Gini com 500 arvores, `mtry = 3` e `min.node.size = 10` (10 selecoes). A distribuicao das selecoes foi:

| Configuracao | Numero de folds |
|---|---:|
| Gini, 500 arvores, `mtry = 3`, node size = 10 | 10 |
| Gini, 1000 arvores, `mtry = 3`, node size = 10 | 6 |
| Extra-Trees, 500 arvores, `mtry = 3`, node size = 10 | 5 |
| Extra-Trees, 1000 arvores, `mtry = 3`, node size = 5 | 3 |
| Extra-Trees, 1000 arvores, `mtry = 4`, node size = 10 | 3 |
| Extra-Trees, 1000 arvores, `mtry = 6`, node size = 10 | 3 |
| Extra-Trees, 500 arvores, `mtry = 4`, node size = 10 | 3 |
| Gini, 1000 arvores, `mtry = 3`, node size = 5 | 3 |
| Cinco outras configuracoes | 2 cada |
| Quatro outras configuracoes | 1 cada |

Essa variacao entre folds e esperada em uma base pequena: a configuracao final e escolhida pelo ajuste realizado com todos os dados, enquanto o desempenho de generalizacao vem exclusivamente da camada externa.

## Configuracao final

No ajuste final com todos os dados, a configuracao vencedora foi:

| Item | Valor |
|---|---|
| Familia | Random Forest com Gini |
| Numero de arvores | 500 |
| `mtry` | 3 |
| `min.node.size` | 10 |
| Limiar | 0,545 |
| MCC medio no ajuste final | 0,6823 |
| DP do MCC no ajuste final | 0,1299 |
| F1 medio no ajuste final | 0,8082 |
| ROC-AUC medio no ajuste final | 0,9033 |

O modelo final salvo no arquivo RDS serve para novas previsoes. Ele nao substitui a estimativa de desempenho apresentada anteriormente, que e a da validacao externa aninhada.

## Comparacao entre as familias

As familias Gini e Extra-Trees foram comparadas pelo protocolo 5x2cv compartilhado. Em cada metade de treino, os hiperparametros e o limiar foram recalibrados internamente.

| Teste | Metrica | Estatistica | Graus de liberdade | p-valor |
|---|---|---:|---:|---:|
| Dietterich 5x2cv | MCC | t = 1,3112 | 5 | 0,24677 |
| Dietterich 5x2cv | F1 | t = 2,4254 | 5 | 0,05972 |
| F combinado de Alpaydin | MCC | F = 1,8790 | 10, 5 | 0,25210 |
| F combinado de Alpaydin | F1 | F = 2,8916 | 10, 5 | 0,12639 |

As diferencas medias A menos B foram -0,0019 para MCC e -0,0029 para F1, onde A e Gini e B e Extra-Trees. Em ambos os testes e para ambas as metricas, nao houve evidencia de diferenca estatisticamente significativa ao nivel de 5%.

O teste de Dietterich foi originalmente proposto para taxa de erro; seu uso com MCC e F1 deve ser interpretado como uma extensao pratica.

## Tempo de execucao

A execucao completa terminou em **456,00 segundos** (aproximadamente 7 minutos e 36 segundos), com 12 workers no tuning e uma thread interna por ajuste do `ranger`.

## Execucao

Execute a partir da raiz do projeto:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\random_forest.r
```

Os pacotes necessarios devem ser instalados manualmente, se ainda nao estiverem disponiveis:

```r
install.packages(c("ranger", "withr", "digest", "foreach", "doParallel"))
```

O script nao instala pacotes automaticamente.

Para ajustar o numero de workers no PowerShell, antes da execucao:

```powershell
$env:RF_TUNING_WORKERS = "8"
```

## Interpretacao

O modelo apresentou boa capacidade discriminativa pelas medias de ROC-AUC (0,9002) e PR-AUC (0,8976), com MCC medio de 0,6323. A especificidade media (0,8805) foi superior a sensibilidade media (0,7349), o que tambem se reflete nos 184 casos de `doenca` agregados classificados como `sem_doenca`.

Embora a familia Gini tenha sido selecionada para o modelo final, a comparacao 5x2cv nao encontrou evidencia de diferenca estatisticamente significativa em relacao a Extra-Trees. Logo, essa escolha representa o melhor resultado do procedimento de ajuste final, e nao uma demonstracao de superioridade estatistica entre as familias.
