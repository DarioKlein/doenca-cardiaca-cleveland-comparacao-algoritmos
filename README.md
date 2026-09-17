# Predição de doença cardíaca com aprendizado de máquina

Projeto de Iniciação Científica (PIBIC 2026) que compara Naive Bayes, Árvore
de Decisão, Random Forest e SVM linear na classificação binária de doença
cardíaca. O repositório contém uma análise exploratória original e uma
avaliação complementar mais rigorosa, baseada em validação cruzada aninhada.

> Este é um estudo acadêmico retrospectivo. Os modelos não foram validados
> para diagnóstico ou tomada de decisão clínica.

## Resultado principal

Na avaliação complementar da base Cleveland, o Naive Bayes obteve o maior MCC
médio (`0,6667`), seguido por SVM (`0,6524`), Random Forest (`0,6354`) e Árvore
de Decisão (`0,5504`). As seis comparações pareadas bilaterais de MCC foram
avaliadas com o teste t corrigido de Nadeau–Bengio e correção de Holm. Nenhuma
foi significativa a `α = 0,05`; o menor p-valor ajustado foi `0,4381`.

Portanto, **H0 não foi rejeitada** na análise complementar da Cleveland. Isso
significa ausência de evidência suficiente de diferença estatística sob este
protocolo, e não prova de igualdade entre os algoritmos. A hipótese direcional
de que a Random Forest apresentaria o melhor desempenho também não foi
corroborada: ela não liderou o MCC na Cleveland.

| Algoritmo | Acurácia | F1 | MCC | ROC-AUC |
|---|---:|---:|---:|---:|
| **Naive Bayes** | **0,8328 ± 0,0304** | **0,8128 ± 0,0391** | **0,6667 ± 0,0646** | **0,9100 ± 0,0215** |
| Árvore de Decisão | 0,7745 ± 0,0566 | 0,7473 ± 0,0702 | 0,5504 ± 0,1155 | 0,8049 ± 0,0536 |
| Random Forest | 0,8161 ± 0,0545 | 0,7942 ± 0,0663 | 0,6354 ± 0,1104 | 0,9021 ± 0,0302 |
| SVM linear | 0,8250 ± 0,0512 | 0,8016 ± 0,0635 | 0,6524 ± 0,1052 | 0,8983 ± 0,0403 |

Os valores são média ± desvio-padrão dos 15 folds externos. O desvio-padrão é
descritivo e não é intervalo de confiança.

## Base Cleveland

O subconjunto Cleveland da base [Heart Disease, da UCI Machine Learning
Repository](https://archive.ics.uci.edu/dataset/45/heart+disease) possui 303
registros, 13 preditores, 164 casos `sem_doenca` e 139 casos `doenca`. A classe
original foi binarizada desta forma:

- `sem_doenca`: `num = 0`;
- `doenca`: `num > 0`.

Há quatro ausências em `vasos_principais` e duas em `thal`. Na Random Forest e
na SVM, as modas são aprendidas somente no conjunto de treino correspondente.
Na SVM, média e desvio-padrão das variáveis numéricas também são aprendidos
somente no treino. Naive Bayes e `rpart` utilizam o tratamento de ausências dos
respectivos pacotes. Nenhum registro foi removido.

## Desenho experimental

### Avaliação complementar — protocolo principal para inferência

O protocolo `cleveland_ncv_5x3_inner3_v1` usa:

- 5 folds externos estratificados, repetidos com 3 sementes;
- 3 folds internos estratificados em cada conjunto de treino externo;
- as mesmas partições para todos os algoritmos;
- seleção interna pela maior média de MCC;
- desempate por F1, ROC-AUC e identificador da configuração;
- reajuste no treino externo completo e avaliação uma única vez no teste
  externo intocado;
- limiar de classificação fixo em `0,5`;
- 15 resultados externos pareados e 909 previsões OOF por algoritmo.

As sementes, partições e assinaturas dos dados e do código ficam registradas
nos manifestos. Imputação e padronização são refeitas dentro de cada treino,
evitando que o fold de validação ou teste informe o pré-processamento.

### Configurações avaliadas

| Algoritmo | Grade |
|---|---|
| Naive Bayes | Gaussiano e KDE; `laplace = 1`; KDE com `adjust = 1`. |
| Árvore de Decisão | Gini; `cp` 0,005, 0,01 ou 0,02; profundidade 3 ou 5. |
| Random Forest | 300 ou 500 árvores; `mtry` 3 ou 4. |
| SVM | Kernel linear; custo 0,1, 1 ou 10. |

### Custo computacional da avaliação complementar

Cada configuração é ajustada em 3 folds internos para cada um dos 15 folds
externos. Depois da seleção, há um reajuste externo por fold.

| Algoritmo | Configurações | Ajustes internos | Reajustes externos | Total |
|---|---:|---:|---:|---:|
| Naive Bayes | 2 | 90 | 15 | 105 |
| Árvore de Decisão | 6 | 270 | 15 | 285 |
| Random Forest | 4 | 180 | 15 | 195 |
| SVM | 3 | 135 | 15 | 150 |
| **Projeto Cleveland complementar** |  | **675** | **60** | **735** |

Na execução de 7 de setembro de 2026, todos os quatro algoritmos terminaram em
poucos segundos na Cleveland. Os tempos servem para auditoria desta máquina,
não para comparação universal de eficiência.

## Resultados completos da avaliação complementar

| Métrica | Naive Bayes | Árvore | Random Forest | SVM |
|---|---:|---:|---:|---:|
| Acurácia | **0,8328 ± 0,0304** | 0,7745 ± 0,0566 | 0,8161 ± 0,0545 | 0,8250 ± 0,0512 |
| Sensibilidade | **0,7989 ± 0,0813** | 0,7363 ± 0,1103 | 0,7843 ± 0,1087 | 0,7797 ± 0,1009 |
| Especificidade | 0,8618 ± 0,0470 | 0,8068 ± 0,0810 | 0,8433 ± 0,0763 | **0,8636 ± 0,0688** |
| Precisão | 0,8335 ± 0,0432 | 0,7689 ± 0,0722 | 0,8154 ± 0,0736 | **0,8341 ± 0,0729** |
| F1 | **0,8128 ± 0,0391** | 0,7473 ± 0,0702 | 0,7942 ± 0,0663 | 0,8016 ± 0,0635 |
| MCC | **0,6667 ± 0,0646** | 0,5504 ± 0,1155 | 0,6354 ± 0,1104 | 0,6524 ± 0,1052 |
| ROC-AUC | **0,9100 ± 0,0215** | 0,8049 ± 0,0536 | 0,9021 ± 0,0302 | 0,8983 ± 0,0403 |
| Brier | 0,1325 ± 0,0184 | 0,1767 ± 0,0363 | 0,1299 ± 0,0181 | **0,1293 ± 0,0292** |
| Log Loss | 0,5170 ± 0,0876 | 0,6652 ± 0,4527 | **0,4095 ± 0,0443** | 0,4103 ± 0,0838 |
| Acurácia balanceada | **0,8303 ± 0,0331** | 0,7715 ± 0,0585 | 0,8138 ± 0,0566 | 0,8216 ± 0,0530 |

Em Brier e Log Loss, valores menores são melhores. Os destaques são apenas
descritivos.

### Comparações pareadas de MCC

| Par, diferença A − B | Diferença média | IC marginal de 95% | p bruto | p Holm |
|---|---:|---:|---:|---:|
| Naive Bayes − Árvore | 0,1163 | [-0,0124; 0,2450] | 0,0730 | 0,4381 |
| Naive Bayes − Random Forest | 0,0314 | [-0,0859; 0,1486] | 0,5753 | 1,0000 |
| Naive Bayes − SVM | 0,0144 | [-0,0692; 0,0980] | 0,7174 | 1,0000 |
| Árvore − Random Forest | -0,0849 | [-0,1828; 0,0129] | 0,0838 | 0,4381 |
| Árvore − SVM | -0,1019 | [-0,2382; 0,0344] | 0,1310 | 0,5241 |
| Random Forest − SVM | -0,0170 | [-0,1180; 0,0841] | 0,7240 | 1,0000 |

Os intervalos são marginais, enquanto a decisão familiar usa os p-valores
ajustados por Holm. Como os folds de validação cruzada se sobrepõem, o teste
aplica a correção de variância de Nadeau–Bengio, com razão média
teste/treino de aproximadamente `0,25` e 14 graus de liberdade. Com somente 15
avaliações e 303 participantes, o poder estatístico é limitado.

## Relação com a análise exploratória anterior

Os scripts em `src/` preservam a primeira avaliação 5-fold × 3, não aninhada.
Ela produziu MCCs de `0,6694`, `0,5561`, `0,6428` e `0,6562` para Naive Bayes,
Árvore, Random Forest e SVM, respectivamente. A avaliação aninhada produziu
`0,6667`, `0,5504`, `0,6354` e `0,6524`. A proximidade e a manutenção do ranking
indicam que o novo desenho não alterou bruscamente a interpretação descritiva;
ele separou corretamente seleção e avaliação e acrescentou uma inferência
pareada apropriada ao desenho.

A base Kaggle permanece como análise descritiva na pasta irmã `Kaggle`. Ela
não recebeu a validação aninhada devido ao custo computacional, especialmente
da SVM. Seus números não entram no teste de hipótese complementar da Cleveland.

## Como reproduzir

Execute a partir da pasta `Clevand`:

```powershell
Rscript src/nested/prepare_experiment.r
Rscript src/nested/run_naive_bayes.r
Rscript src/nested/run_decision_trees.r
Rscript src/nested/run_random_forest.r
Rscript src/nested/run_svm.r
Rscript src/nested/validate_results.r
Rscript src/nested/statistical_analysis.r
Rscript src/nested/compare_models.r
```

O primeiro script baixa a base UCI pelo identificador `45`, prepara os dados e
congela folds e sementes. Os quatro seguintes podem ser executados
separadamente. A validação deve passar antes da análise estatística. A última
etapa gera 11 gráficos de métricas e um gráfico das comparações pareadas.

Arquivos `.rds` são utilizados localmente para o instantâneo preparado e para
checkpoints de retomada, mas não representam um modelo final para uso clínico e
estão ignorados pelo Git.

Para reproduzir apenas a etapa exploratória preservada:

```powershell
Rscript src/naive_bayes.r
Rscript src/decision_trees.r
Rscript src/random_forest.r
Rscript src/svm.r
Rscript src/compare_models.r
```

## Estrutura principal

```text
src/
  *.r                         # análise exploratória preservada
  nested/
    prepare_experiment.r      # dados, folds e sementes congelados
    run_*.r                   # quatro avaliações aninhadas
    validate_results.r        # integridade e pareamento
    statistical_analysis.r    # teste corrigido e Holm
    compare_models.r          # gráficos complementares
docs/
  DOCUMENTACAO_*.md
  RELATORIO_COMPLETO_PROJETO.md
results/
  csvs/ e imagens/            # resultados exploratórios
  cleveland_ncv_5x3_inner3_v1/
    csvs/                     # métricas internas, externas e OOF
    inferencia/               # comparações pareadas de MCC
    imagens/                  # gráficos e diagnósticos
    manifest/                 # versões, assinaturas e auditoria
    partitions/               # folds e sementes
```

## Dependências

- R 4.5.1 na execução registrada;
- `ucimlrepo`;
- `naivebayes`;
- `rpart`;
- `ranger`;
- `e1071`.

Os scripts pressupõem que os pacotes já estejam instalados e não executam
`install.packages()` automaticamente.

## Limitações

- A Cleveland contém apenas 303 registros e não representa validação externa.
- A correção de Nadeau–Bengio é uma aproximação para a dependência dos folds.
- Quinze avaliações fornecem poder limitado para diferenças pequenas.
- O teste formal foi executado somente na Cleveland; a Kaggle é descritiva.
- O limiar `0,5` não foi otimizado por custos clínicos.
- As grades são pequenas e a SVM avaliada usa apenas kernel linear.
- Não foram avaliadas calibração clínica, utilidade decisória ou transporte
  para outros hospitais e populações.

## Documentação

- [Relatório completo](docs/RELATORIO_COMPLETO_PROJETO.md)
- [Naive Bayes](docs/DOCUMENTACAO_NAIVE_BAYES.md)
- [Árvore de Decisão](docs/DOCUMENTACAO_DECISION_TREES.md)
- [Random Forest](docs/DOCUMENTACAO_RANDOM_FOREST.md)
- [SVM linear](docs/DOCUMENTACAO_SVM.md)
