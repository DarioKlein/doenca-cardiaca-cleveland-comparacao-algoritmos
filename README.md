# Predição de doença cardíaca com aprendizado de máquina

Projeto de Iniciação Científica (PIBIC 2026) que compara quatro algoritmos de
aprendizado de máquina na identificação de doença cardíaca a partir de dados
clínicos. O foco do trabalho é manter uma avaliação reprodutível, compreensível
e viável em computadores pessoais.

> Este projeto possui finalidade acadêmica. Os modelos não foram desenvolvidos
> nem validados para diagnóstico ou tomada de decisão clínica.

## Objetivo

Comparar o desempenho de:

1. Naive Bayes;
2. Árvore de Decisão;
3. Random Forest;
4. Support Vector Machine (SVM).

A comparação utiliza o mesmo conjunto de dados, os mesmos folds e as mesmas
métricas para todos os algoritmos. A classe original `num` foi transformada em
um problema binário:

- `sem_doenca`: `num = 0`;
- `doenca`: `num > 0`.

## Base de dados

O projeto utiliza o subconjunto Cleveland da base [Heart Disease, da UCI
Machine Learning Repository](https://archive.ics.uci.edu/dataset/45/heart+disease),
com 303 registros e 13 variáveis preditoras. A importação é feita diretamente
pelo identificador oficial da base:

```r
base_uci <- ucimlrepo::fetch_ucirepo(id = 45)
```

As variáveis receberam nomes em português para facilitar a leitura do código.
Existem seis valores ausentes: quatro em `vasos_principais` e dois em
`talassemia`.

- Naive Bayes e Árvore de Decisão usam o tratamento nativo dos respectivos
  pacotes.
- Random Forest e SVM aprendem a moda somente no fold de treino e aplicam o
  valor aprendido ao fold de teste.
- A padronização usada pela SVM também é calculada exclusivamente no treino.

Assim, informações do conjunto de teste não são utilizadas no
pré-processamento do treino.

## Metodologia de avaliação

Foi utilizada validação cruzada estratificada **5-fold repetida 3 vezes**:

- sementes `20260804`, `20260805` e `20260806`;
- mesmos folds para os quatro algoritmos;
- classe positiva `doenca`;
- limiar de classificação fixo em 0,5;
- métricas calculadas sobre as predições fora da amostra dos 303 pacientes;
- resultado apresentado como média ± desvio-padrão das três repetições.

A configuração de cada algoritmo é selecionada pela maior média de MCC, com
desempate por F1, ROC-AUC e identificador da configuração.

### Configurações avaliadas

| Algoritmo | Configurações |
|---|---|
| Naive Bayes | Gaussiano e KDE, ambos com `laplace = 1`. |
| Árvore de Decisão | Gini; `cp` de 0,005, 0,01 ou 0,02; profundidade máxima 3 ou 5. |
| Random Forest | 300 ou 500 árvores; `mtry` igual a 3 ou 4. |
| SVM | Kernel linear; custo igual a 0,1, 1 ou 10. |

### Custo computacional

| Algoritmo | Configurações | Folds | Repetições | Ajustes |
|---|---:|---:|---:|---:|
| Naive Bayes | 2 | 5 | 3 | 30 |
| Árvore de Decisão | 6 | 5 | 3 | 90 |
| Random Forest | 4 | 5 | 3 | 60 |
| SVM | 3 | 5 | 3 | 45 |
| **Total** |  |  |  | **225** |

Esse protocolo substitui avaliações anteriores mais pesadas e permite que o
projeto seja executado com rapidez na base Cleveland. O custo deverá ser medido
novamente quando o estudo for aplicado à base futura de aproximadamente 70 mil
registros.

## Resultados oficiais

Os valores abaixo foram obtidos nas execuções realizadas pelo pesquisador. O
desvio-padrão representa a variação descritiva entre as três repetições.

| Algoritmo | Acurácia | Sensibilidade | Especificidade | Precisão | F1 | MCC | ROC-AUC |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Naive Bayes** | **0,8361 ± 0,0050** | **0,8010 ± 0,0042** | **0,8659 ± 0,0061** | **0,8350 ± 0,0069** | **0,8176 ± 0,0053** | **0,6694 ± 0,0102** | **0,9056 ± 0,0008** |
| Árvore de Decisão | 0,7800 ± 0,0019 | 0,7410 ± 0,0144 | 0,8130 ± 0,0127 | 0,7707 ± 0,0086 | 0,7555 ± 0,0039 | 0,5561 ± 0,0037 | 0,8092 ± 0,0119 |
| Random Forest | 0,8229 ± 0,0182 | 0,7914 ± 0,0144 | 0,8496 ± 0,0231 | 0,8171 ± 0,0250 | 0,8040 ± 0,0187 | 0,6428 ± 0,0365 | 0,8971 ± 0,0058 |
| SVM | 0,8295 ± 0,0069 | 0,7914 ± 0,0072 | 0,8618 ± 0,0186 | 0,8295 ± 0,0177 | 0,8099 ± 0,0048 | 0,6562 ± 0,0138 | 0,8969 ± 0,0035 |

### Métricas probabilísticas e tempo

Em Brier Score e Log Loss, valores menores indicam probabilidades mais bem
ajustadas. O tempo é a média necessária para avaliar uma configuração nos cinco
folds de uma repetição, não o tempo total do script.

| Algoritmo | Acurácia balanceada | Brier Score | Log Loss | Tempo médio |
|---|---:|---:|---:|---:|
| Naive Bayes | **0,8334** | 0,1319 | 0,5164 | 0,0351 s |
| Árvore de Decisão | 0,7770 | 0,1744 | 0,5487 | **0,0263 s** |
| Random Forest | 0,8205 | 0,1295 | 0,4072 | 0,1642 s |
| SVM | 0,8266 | **0,1256** | **0,3990** | 0,0608 s |

### Configurações selecionadas

| Algoritmo | Configuração selecionada |
|---|---|
| Naive Bayes | Gaussiano, `laplace = 1`. |
| Árvore de Decisão | `cp = 0,01`, profundidade máxima 5. |
| Random Forest | 500 árvores, `mtry = 4`. |
| SVM | Kernel linear, custo 1. |

### Interpretação

O Naive Bayes apresentou o melhor resultado descritivo geral, com as maiores
médias de acurácia, F1, MCC e ROC-AUC. A SVM ficou próxima nas métricas de
classificação e apresentou os menores Brier Score e Log Loss. A Random Forest
também obteve desempenho competitivo, enquanto a Árvore de Decisão apresentou
resultados inferiores, mas mantém como vantagem a interpretação mais direta de
suas regras.

Essas diferenças não devem ser interpretadas como prova de superioridade
estatística. A validação é repetida simples, não aninhada, e a mesma CV participa
da escolha da configuração e da estimativa de desempenho. Isso pode gerar algum
otimismo nos resultados.

## Métricas calculadas

- Acurácia;
- Sensibilidade;
- Especificidade;
- Precisão;
- F1;
- Matthews Correlation Coefficient (MCC);
- ROC-AUC;
- Acurácia balanceada;
- Brier Score;
- Log Loss;
- Tempo de execução.

O MCC é a métrica principal de seleção porque considera simultaneamente os
quatro componentes da matriz de confusão e permanece informativo mesmo quando
há desequilíbrio entre as classes.

## Dependências

- R;
- `ucimlrepo`;
- `naivebayes`;
- `rpart`;
- `ranger`;
- `e1071`.

Os scripts pressupõem que esses pacotes já estejam instalados e não executam
`install.packages()` automaticamente.

## Como executar

Execute os comandos a partir da raiz do projeto:

```powershell
Rscript src/naive_bayes.r
Rscript src/decision_trees.r
Rscript src/random_forest.r
Rscript src/svm.r
Rscript src/compare_models.r
```

Os quatro primeiros scripts avaliam os algoritmos e salvam os resultados
numéricos. O último lê os resumos oficiais e gera os gráficos comparativos.

## Estrutura do projeto

```text
src/
  heart_disease_data.r   # Importação e preparação da base
  common_evaluation.r    # Folds, métricas e funções compartilhadas
  naive_bayes.r          # Avaliação do Naive Bayes
  decision_trees.r       # Avaliação da Árvore de Decisão
  random_forest.r        # Avaliação da Random Forest
  svm.r                  # Avaliação da SVM
  compare_models.r       # Gráficos comparativos
docs/
  DOCUMENTACAO_NAIVE_BAYES.md
  DOCUMENTACAO_DECISION_TREES.md
  DOCUMENTACAO_RANDOM_FOREST.md
  DOCUMENTACAO_SVM.md
results/
  csvs/                  # Tabelas geradas pelas execuções
  imagens/               # Gráficos comparativos em PNG
```

Cada algoritmo produz cinco arquivos CSV:

- resultados de todas as configurações;
- ranking das configurações;
- resultados das três repetições;
- resumo do modelo selecionado;
- predições fora da amostra.

O script de comparação gera um PNG separado para cada métrica, com média,
desvio-padrão, cores consistentes e resolução de 2400 × 1600 pixels a 240 dpi.

## Documentação detalhada

- [Naive Bayes](docs/DOCUMENTACAO_NAIVE_BAYES.md)
- [Árvore de Decisão](docs/DOCUMENTACAO_DECISION_TREES.md)
- [Random Forest](docs/DOCUMENTACAO_RANDOM_FOREST.md)
- [SVM](docs/DOCUMENTACAO_SVM.md)

## Limitações

- A base Cleveland possui apenas 303 registros.
- A escolha de configuração e a estimativa de desempenho usam a mesma
  validação cruzada.
- As três repetições não são amostras independentes; portanto, o desvio-padrão
  não deve ser convertido diretamente em intervalo de confiança.
- Os resultados ainda precisam ser avaliados na base maior planejada para a
  continuidade da pesquisa.
- O estudo avalia desempenho preditivo acadêmico e não validade clínica.

## Reprodutibilidade

Os folds são estratificados e determinados por sementes fixas. Todos os
algoritmos recebem as mesmas divisões, e qualquer imputação ou padronização é
aprendida apenas no conjunto de treino. Essas decisões permitem repetir o
experimento e comparar os modelos sob o mesmo protocolo.
