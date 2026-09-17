# Relatório completo do projeto: comparação de algoritmos para classificação de doença cardíaca

> Documento de consolidação metodológica e de resultados — atualizado em 7 de setembro de 2026.
>
> Este arquivo reúne as decisões tomadas, as alterações realizadas no projeto, o protocolo experimental, o pré-processamento, as configurações avaliadas, as métricas, os resultados das bases Cleveland e Kaggle, a interpretação das hipóteses, a comparação com a literatura e as limitações. Os números apresentados foram lidos dos CSVs oficiais existentes no projeto.

## 1. Resumo executivo

O projeto compara quatro algoritmos clássicos de aprendizado de máquina para classificação binária de doença cardíaca:

1. Naive Bayes;
2. Árvore de Decisão;
3. Random Forest;
4. Support Vector Machine (SVM) com kernel linear.

Os mesmos algoritmos, grades de hiperparâmetros, sementes, folds, limiar de classificação e métricas foram aplicados a duas bases:

- **Cleveland Heart Disease**, com 303 registros e 13 variáveis preditoras;
- **Cardiovascular Disease Dataset do Kaggle**, com 70.000 registros originais e 68.610 após a limpeza de medidas fisiologicamente implausíveis.

O estudo passou a ter duas camadas. A etapa exploratória preservada usa validação cruzada estratificada de 5 folds repetida 3 vezes nas duas bases. A avaliação complementar da Cleveland usa os mesmos 5 folds × 3 repetições no ciclo externo e 3 folds no ciclo interno. Nela, a seleção por MCC ocorre exclusivamente dentro do treino externo, antes da avaliação no teste externo intocado.

Os principais resultados foram:

- na avaliação complementar da Cleveland, o **Naive Bayes** apresentou o melhor desempenho descritivo, com acurácia média por fold de `0,8328`, MCC de `0,6667` e ROC-AUC de `0,9100`;
- na base Kaggle, a **Random Forest com 500 árvores e mtry 3** apresentou o maior MCC (`0,4607`) e a maior acurácia (`0,7300`), mas sua vantagem sobre a SVM foi muito pequena;
- a Árvore de Decisão apresentou menor capacidade discriminativa nas duas bases, especialmente segundo a ROC-AUC;
- os resultados são compatíveis com valores encontrados em estudos publicados para essas bases;
- os algoritmos são cientificamente defensáveis como comparação acadêmica e como *baselines*, mas os resultados não representam validação clínica;
- as seis comparações pareadas de MCC na Cleveland foram analisadas pelo teste t corrigido de Nadeau–Bengio, com correção de Holm; nenhuma foi significativa (`menor p Holm = 0,4381`);
- por isso, **H0 não foi rejeitada na análise complementar da Cleveland**, e a hipótese direcional de superioridade da Random Forest não foi corroborada. A Kaggle permanece descritiva.

## 2. Contexto, pergunta e objetivos

### 2.1 Pergunta de pesquisa

Como Naive Bayes, Árvore de Decisão, Random Forest e SVM se comportam na classificação de doença cardíaca quando avaliados sob um mesmo protocolo, e como esse comportamento muda ao passar de uma base pequena para uma base com dezenas de milhares de registros?

### 2.2 Objetivo geral

Comparar o desempenho preditivo e o custo computacional de quatro algoritmos de aprendizado de máquina na classificação de doença cardíaca utilizando as bases Cleveland e Cardiovascular Disease Dataset do Kaggle.

### 2.3 Objetivos específicos

- implementar os quatro algoritmos com código legível e variáveis em português;
- aplicar o mesmo protocolo de avaliação aos quatro algoritmos;
- evitar vazamento de dados no pré-processamento aprendido;
- calcular métricas de classificação, discriminação, calibração e tempo;
- observar a estabilidade dos resultados nos 15 folds externos e nas três repetições;
- comparar o comportamento dos algoritmos em uma base pequena e em uma base muito maior;
- verificar se os resultados são compatíveis com trabalhos publicados;
- testar formalmente as diferenças de MCC na Cleveland e avaliar descritivamente a Kaggle;
- produzir CSVs e gráficos reutilizáveis na apresentação dos resultados.

## 3. Hipóteses do estudo

As hipóteses originalmente formuladas foram:

> **H0:** Não existe diferença estatisticamente significativa de desempenho entre os algoritmos estudados para a classificação de doenças cardíacas.

> **H1:** O algoritmo Random Forest apresentará melhor desempenho entre os algoritmos estudados para a classificação de doenças cardíacas.

Essas duas proposições não são alternativas estatísticas perfeitamente complementares. É possível existir diferença entre algoritmos e, ao mesmo tempo, o melhor algoritmo ser Naive Bayes ou SVM, em vez de Random Forest. Para a interpretação estatística, as proposições foram separadas assim:

- **H0:** não existe diferença estatisticamente significativa de desempenho entre os algoritmos;
- **H1a:** existe diferença estatisticamente significativa entre pelo menos dois algoritmos;
- **H1b, direcional:** espera-se que a Random Forest apresente o melhor desempenho médio.

O MCC foi definido como métrica primária para testar essas hipóteses, pois também orienta a seleção interna das configurações. As demais métricas são complementares.

### 3.1 Conclusão atual sobre as hipóteses

Com o protocolo complementar da Cleveland:

- foram comparados os 15 MCCs externos pareados de cada algoritmo;
- aplicou-se o teste t corrigido de Nadeau–Bengio e correção de Holm às seis comparações bilaterais;
- nenhum par foi significativo a `α = 0,05`; o menor p-valor ajustado foi `0,4381`;
- **H0 não foi rejeitada**;
- isso não prova igualdade ou equivalência, mas indica evidência insuficiente de diferença sob a amostra e o desenho utilizados;
- **H1 direcional não foi corroborada**, pois o Naive Bayes, e não a Random Forest, teve o maior MCC médio na Cleveland (`0,6667` contra `0,6354`);
- na Kaggle descritiva, a Random Forest obteve MCC `0,4607`, contra `0,4591` da SVM, diferença de apenas `0,0016`.

Uma formulação segura para o relatório científico é:

> Na avaliação complementar da Cleveland, nenhuma das seis comparações pareadas de MCC permaneceu significativa após a correção de Holm. Portanto, a hipótese nula não foi rejeitada. O Naive Bayes apresentou o maior MCC médio, enquanto a Random Forest ficou em terceiro lugar; logo, a expectativa direcional de superioridade da Random Forest não foi corroborada. A Kaggle permanece uma análise descritiva, na qual Random Forest e SVM tiveram resultados muito próximos.

## 4. Alterações e decisões realizadas no projeto

O projeto foi simplificado para permanecer compreensível, reprodutível e executável em computador pessoal. As principais alterações foram:

1. substituição da avaliação anterior, mais pesada e baseada em validação aninhada, por validação cruzada estratificada 5-fold repetida 3 vezes;
2. redução da quantidade de configurações e ajustes para uma grade pequena e justificável;
3. centralização da criação dos folds, cálculo de métricas, seleção de configuração e exportação dos resultados em um arquivo compartilhado;
4. adoção dos mesmos folds e sementes nos quatro algoritmos;
5. geração e armazenamento de previsões OOF para auditoria;
6. conversão de nomes de variáveis e funções para português;
7. redução de comentários repetitivos e validações excessivas;
8. remoção dos testes unitários, conforme o escopo acadêmico e a solicitação de simplificação;
9. remoção de instalação automática de pacotes;
10. importação da base Cleveland diretamente pelo identificador `45` do repositório UCI;
11. separação dos resultados em `results/csvs/` e `results/imagens/`;
12. criação de um script que gera um gráfico PNG independente para cada métrica;
13. replicação dos quatro experimentos na base Kaggle;
14. criação de limpeza específica para os valores fisiologicamente implausíveis da base Kaggle;
15. inclusão de paralelismo entre folds na base Kaggle, usando dois processos;
16. preservação de uma única thread dentro de cada ajuste de Random Forest na base Kaggle, evitando paralelismo aninhado;
17. registro das limitações da comparação temporal e da validação não aninhada;
18. exclusão de `AGENTS.md` pelo `.gitignore`, por ser um arquivo local de orientação de desenvolvimento;
19. reintrodução, somente na Cleveland, de uma avaliação complementar aninhada com ciclo interno de 3 folds;
20. congelamento de folds, sementes e assinaturas para auditoria;
21. inclusão do teste t corrigido de Nadeau–Bengio e da correção de Holm para as seis comparações de MCC.

Não é salvo um modelo final para implantação. A avaliação complementar usa arquivos RDS locais para congelar os dados preparados e manter checkpoints de cada fold; esses arquivos servem à retomada e à reprodutibilidade, não constituem um instrumento de diagnóstico. Ajustar um modelo final em todos os dados seria uma etapa experimental adicional e só deve ocorrer quando houver finalidade definida.

## 5. Organização do projeto

Após a expansão do estudo, a área de trabalho foi dividida em duas pastas:

```text
TesteGPT/
  Clevand/
    src/
      nested/
    docs/
    results/
      csvs/
      imagens/
      cleveland_ncv_5x3_inner3_v1/
  Kaggle/
    dataset/
    src/
    docs/
    results/
      csvs/
      imagens/
```

O nome da pasta `Clevand` foi mantido como existe no projeto. No texto científico, o nome correto da base é **Cleveland**.

### 5.1 Arquivos de código da Cleveland

- `src/heart_disease_data.r`: importa a base pelo repositório UCI, renomeia e tipa as variáveis e cria a classe binária;
- `src/common_evaluation.r`: cria os folds, calcula métricas, executa a CV repetida, seleciona configurações e salva os CSVs;
- `src/naive_bayes.r`: configura e avalia o Naive Bayes;
- `src/decision_trees.r`: configura e avalia a Árvore de Decisão;
- `src/random_forest.r`: configura e avalia a Random Forest;
- `src/svm.r`: configura e avalia a SVM linear;
- `src/compare_models.r`: lê os resumos e gera os gráficos comparativos da etapa exploratória;
- `src/nested/prepare_experiment.r`: importa a Cleveland, congela dados, partições e sementes da avaliação complementar;
- `src/nested/run_*.r`: executa os quatro algoritmos sob validação cruzada aninhada;
- `src/nested/validate_results.r`: verifica integridade, cobertura OOF e pareamento;
- `src/nested/statistical_analysis.r`: executa as seis comparações pareadas de MCC;
- `src/nested/compare_models.r`: gera gráficos das métricas externas e da inferência.

### 5.2 Arquivos de código da Kaggle

- `src/cardiovascular_data.r`: carrega o CSV local, aplica as regras fixas de limpeza, renomeia e tipa as variáveis;
- `src/common_evaluation.r`: versão com suporte a paralelismo entre folds;
- os demais scripts cumprem as mesmas funções das versões Cleveland.

## 6. Base Cleveland

### 6.1 Origem e tamanho

A base é obtida de [Heart Disease, UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/45/heart+disease) por meio de:

```r
base_uci <- ucimlrepo::fetch_ucirepo(id = 45)
```

Foram utilizados:

- 303 registros;
- 13 variáveis preditoras;
- 164 registros da classe `sem_doenca`;
- 139 registros da classe `doenca`.

A classe original `num` foi transformada da seguinte maneira:

- `num = 0` → `sem_doenca`;
- `num > 0` → `doenca`.

Portanto, os diferentes graus originais de doença foram reunidos em uma única classe positiva.

### 6.2 Variáveis utilizadas

| Nome no projeto | Significado | Tratamento |
|---|---|---|
| `idade` | Idade em anos | Numérica |
| `sexo` | Sexo registrado na base | Fator com níveis 0 e 1 |
| `tipo_dor_toracica` | Tipo de dor torácica | Fator com níveis 1 a 4 |
| `pressao_arterial_repouso` | Pressão arterial em repouso | Numérica |
| `colesterol_serico` | Colesterol sérico | Numérica |
| `glicemia_jejum` | Glicemia de jejum acima de 120 mg/dL | Fator binário |
| `eletrocardiograma_repouso` | Resultado do eletrocardiograma em repouso | Fator com níveis 0 a 2 |
| `frequencia_cardiaca_maxima` | Frequência cardíaca máxima | Numérica |
| `angina_induzida_exercicio` | Angina induzida por exercício | Fator binário |
| `depressao_segmento_st` | Depressão do segmento ST induzida por exercício | Numérica |
| `inclinacao_segmento_st` | Inclinação do segmento ST | Fator com níveis 1 a 3 |
| `vasos_principais` | Número de vasos principais coloridos por fluoroscopia | Fator com níveis 0 a 3 |
| `talassemia` | Categoria de talassemia | Fator com níveis 3, 6 e 7 |

Um identificador sequencial `id_registro` é criado somente para rastrear as previsões e não participa do treinamento.

### 6.3 Valores ausentes e pré-processamento

Existem seis valores ausentes:

- quatro em `vasos_principais`;
- dois em `talassemia`.

O tratamento depende do algoritmo:

- **Naive Bayes:** utiliza o tratamento oferecido pelo pacote `naivebayes`;
- **Árvore de Decisão:** utiliza as divisões substitutas do `rpart`;
- **Random Forest:** aprende a moda de cada variável ausente somente nos quatro folds de treino e aplica essas modas ao fold de teste;
- **SVM:** também aprende as modas apenas no treino. Depois calcula média e desvio-padrão das variáveis numéricas exclusivamente no treino e aplica a transformação ao teste.

Esse desenho impede que estatísticas do fold de teste sejam usadas na preparação do treino.

Não foi aplicada remoção adicional de valores extremos. Com somente 303 registros, exclusões não justificadas reduziriam ainda mais a amostra e poderiam produzir resultados artificialmente favoráveis.

## 7. Base Kaggle

### 7.1 Origem e tamanho

Foi utilizado o arquivo `dataset/cardio_train.csv`, proveniente do [Cardiovascular Disease Dataset](https://www.kaggle.com/datasets/sulianova/cardiovascular-disease-dataset/data).

Distribuição original:

- 70.000 registros;
- 35.021 com `cardio = 0`;
- 34.979 com `cardio = 1`.

Mapeamento da classe:

- `cardio = 0` → `sem_doenca`;
- `cardio = 1` → `doenca`.

O identificador `id` é preservado como `id_registro` para auditoria, mas não é usado como preditor.

### 7.2 Variáveis utilizadas

| Nome no projeto | Coluna original | Significado | Tratamento |
|---|---|---|---|
| `idade` | `age` | Idade registrada em dias | Convertida para anos por `age / 365,25` |
| `sexo` | `gender` | Sexo | Fator com níveis 1 e 2 |
| `altura` | `height` | Altura em centímetros | Numérica |
| `peso` | `weight` | Peso em quilogramas | Numérica |
| `pressao_sistolica` | `ap_hi` | Pressão arterial sistólica | Numérica |
| `pressao_diastolica` | `ap_lo` | Pressão arterial diastólica | Numérica |
| `colesterol` | `cholesterol` | Categoria de colesterol | Fator com níveis 1 a 3 |
| `glicose` | `gluc` | Categoria de glicose | Fator com níveis 1 a 3 |
| `fumante` | `smoke` | Indicador de tabagismo | Fator binário |
| `consumo_alcool` | `alco` | Indicador de consumo de álcool | Fator binário |
| `atividade_fisica` | `active` | Indicador de atividade física | Fator binário |

### 7.3 Validações estruturais mantidas

Apesar da simplificação geral, foram mantidas validações mínimas necessárias para impedir a execução sobre um arquivo incompatível:

- conferência dos nomes e da ordem das 13 colunas originais;
- confirmação de ausência de valores ausentes inesperados;
- confirmação de que `cardio` contém somente 0 e 1.

Essas verificações não são pré-processamento estatístico e não utilizam informação do alvo para escolher registros.

### 7.4 Limpeza de medidas implausíveis

São preservados somente os registros que atendem simultaneamente às seguintes regras fixas:

- idade entre 18 e 100 anos;
- altura entre 120 e 220 cm;
- peso entre 30 e 250 kg;
- pressão sistólica entre 70 e 250 mmHg;
- pressão diastólica entre 40 e 150 mmHg;
- pressão sistólica maior que a pressão diastólica.

Contagens de violações individuais, com sobreposição entre regras:

| Regra violada | Registros |
|---|---:|
| Idade fora de 18–100 | 0 |
| Altura fora de 120–220 | 53 |
| Peso fora de 30–250 | 7 |
| Pressão sistólica fora de 70–250 | 229 |
| Pressão diastólica fora de 40–150 | 1.034 |
| Pressão sistólica menor ou igual à diastólica | 1.236 |

As contagens não podem ser somadas, pois um mesmo registro pode violar mais de uma regra.

Resultado da limpeza:

- 1.390 registros removidos;
- 68.610 registros preservados;
- 34.669 registros `sem_doenca`;
- 33.941 registros `doenca`.

Entre os registros removidos havia 352 negativos e 1.038 positivos. Isso deve ser registrado como característica da limpeza, pois houve maior remoção proporcional na classe positiva. Entretanto, as regras foram definidas por plausibilidade fisiológica e não pelo desempenho dos modelos.

Não foram eliminadas linhas apenas por compartilharem as mesmas características. Pacientes diferentes podem apresentar os mesmos valores clínicos, e o identificador original é diferente. Também não foi aplicado SMOTE ou outro balanceamento artificial, pois as classes já são aproximadamente equilibradas.

### 7.5 Pré-processamento por algoritmo

- Naive Bayes, Árvore e Random Forest recebem as variáveis numéricas em suas unidades e as categóricas como fatores;
- não há valores ausentes após o carregamento e a limpeza;
- a SVM aprende médias e desvios-padrão das variáveis numéricas somente nos folds de treino e os aplica ao fold de teste;
- a limpeza por limites fisiológicos é fixa, não aprende parâmetros com o alvo e é aplicada antes da divisão dos folds.

## 8. Protocolo experimental

### 8.1 Camada exploratória preservada

O protocolo original das duas bases usa validação cruzada estratificada de 5 folds, repetida 3 vezes, com sementes `20260804`, `20260805` e `20260806`, mesmos folds entre algoritmos, classe positiva `doenca` e limiar `0,5`. As previsões OOF dos cinco folds são reunidas em cada repetição. A mesma validação participa da seleção da configuração e da estimativa do desempenho; por isso, essa camada é exploratória e pode conter otimismo de seleção.

Na Cleveland, os folds possuem 60 ou 61 pacientes. Na Kaggle, cada fold possui 13.722 registros. A camada exploratória gera 909 previsões OOF por algoritmo na Cleveland e 205.830 na Kaggle.

### 8.2 Avaliação complementar aninhada da Cleveland

O protocolo `cleveland_ncv_5x3_inner3_v1` mantém 5 folds externos × 3 repetições e acrescenta 3 folds internos em cada treino externo:

1. o conjunto de teste externo é separado e não participa da seleção;
2. cada configuração é avaliada nos 3 folds internos;
3. seleciona-se a maior média interna de MCC;
4. empates são resolvidos por F1, ROC-AUC e identificador;
5. a configuração escolhida é reajustada no treino externo completo;
6. o modelo é avaliado uma única vez no teste externo;
7. as 15 avaliações externas ficam pareadas entre os quatro algoritmos.

Toda imputação e toda padronização são aprendidas no treino vigente. O ciclo externo estima o desempenho do procedimento completo de seleção, enquanto o ciclo interno escolhe os hiperparâmetros.

### 8.3 Partições, sementes e auditoria

As partições externas, partições internas e sementes de cada ajuste foram geradas antes dos modelos e persistidas em CSV. Todos os algoritmos usam exatamente o mesmo plano externo. Os manifestos registram MD5 dos dados, partições, sementes e arquivos centrais de código, além de versão do R, início, fim e quantidade de ajustes.

Cada algoritmo produz 15 linhas de métricas externas e 909 previsões OOF (`303 × 3`). A validação automática confirma ausência de duplicação por repetição/registro, cobertura integral, probabilidades finitas no intervalo `[0,1]`, configurações válidas e correspondência exata com os folds congelados.

### 8.4 Quantidade de ajustes

Na camada exploratória são 225 ajustes por base. Na avaliação complementar da Cleveland, cada configuração é ajustada três vezes no ciclo interno de cada fold externo e há um reajuste externo:

| Algoritmo | Configurações | Ajustes internos | Reajustes externos | Total complementar |
|---|---:|---:|---:|---:|
| Naive Bayes | 2 | 90 | 15 | 105 |
| Árvore de Decisão | 6 | 270 | 15 | 285 |
| Random Forest | 4 | 180 | 15 | 195 |
| SVM | 3 | 135 | 15 | 150 |
| **Total** |  | **675** | **60** | **735** |

### 8.5 Paralelismo

A Cleveland é processada sequencialmente e cada Random Forest usa uma thread. Na Kaggle exploratória, dois processos PSOCK podem avaliar folds diferentes simultaneamente, mantendo uma thread dentro de cada Random Forest. O paralelismo altera o tempo de parede, mas não os folds ou as métricas.

## 9. Algoritmos e grades avaliadas

### 9.1 Naive Bayes

O algoritmo estima a probabilidade das classes a partir das distribuições das variáveis e assume independência condicional entre os preditores dado o desfecho. Foram avaliadas:

- configuração Gaussiana: `laplace = 1`, `usekernel = FALSE`;
- configuração KDE: `laplace = 1`, `usekernel = TRUE`, `adjust = 1`.

A correção de Laplace reduz problemas associados a combinações categóricas não observadas no treino.

### 9.2 Árvore de Decisão

Foi utilizado `rpart` para classificação com:

- critério Gini;
- `cp` em `0,005`, `0,01` ou `0,02`;
- profundidade máxima 3 ou 5;
- `minsplit = 20`;
- `xval = 0`, pois a validação é controlada pelo protocolo externo.

A combinação gera seis configurações. Árvores individuais são interpretáveis, mas possuem maior variância e menor capacidade de suavizar fronteiras de decisão.

### 9.3 Random Forest

Foi utilizado o pacote `ranger` em modo probabilístico com:

- 300 ou 500 árvores;
- `mtry` 3 ou 4;
- `min.node.size = 5`;
- critério Gini;
- fatores não ordenados tratados por ordenação;
- importância de variáveis desativada;
- uma thread por ajuste.

As quatro combinações de número de árvores e `mtry` foram avaliadas. A floresta reduz a variância de uma árvore individual por meio da agregação de muitas árvores construídas com amostras e subconjuntos de variáveis.

### 9.4 SVM

Foi utilizado `e1071::svm` com:

- classificação C;
- kernel linear;
- custos `0,1`, `1` e `10`;
- `scale = FALSE`, porque a padronização é feita explicitamente dentro de cada fold;
- `probability = TRUE` para produzir probabilidades;
- valores ajustados não preservados no objeto por `fitted = FALSE`.

O estudo avalia especificamente uma **SVM linear**. Os resultados não devem ser generalizados para kernels radial, polinomial ou outras versões da família SVM.

## 10. Métricas

Considere:

- `VP`: verdadeiros positivos;
- `VN`: verdadeiros negativos;
- `FP`: falsos positivos;
- `FN`: falsos negativos.

### 10.1 Acurácia

Proporção total de classificações corretas:

```text
(VP + VN) / (VP + VN + FP + FN)
```

É intuitiva, mas pode esconder diferenças entre a identificação dos positivos e dos negativos.

### 10.2 Sensibilidade

Proporção dos pacientes positivos identificados corretamente:

```text
VP / (VP + FN)
```

Quanto menor a sensibilidade, maior a proporção de positivos classificados incorretamente como `sem_doenca`.

### 10.3 Especificidade

Proporção dos negativos identificados corretamente:

```text
VN / (VN + FP)
```

### 10.4 Precisão

Proporção das previsões positivas que realmente pertencem à classe positiva:

```text
VP / (VP + FP)
```

### 10.5 F1

Média harmônica entre precisão e sensibilidade:

```text
2 × VP / (2 × VP + FP + FN)
```

### 10.6 MCC

Coeficiente de correlação de Matthews:

```text
(VP × VN - FP × FN) /
sqrt((VP + FP)(VP + FN)(VN + FP)(VN + FN))
```

Varia, em geral, de `-1` a `1`:

- `1`: classificação perfeita;
- `0`: ausência de associação melhor que acaso;
- `-1`: discordância completa.

É a métrica primária do projeto.

### 10.7 ROC-AUC

Mede a capacidade de ordenar um positivo acima de um negativo ao variar o limiar. É calculada diretamente pelos postos das probabilidades, com tratamento médio dos empates.

### 10.8 Acurácia balanceada

Média entre sensibilidade e especificidade:

```text
(sensibilidade + especificidade) / 2
```

### 10.9 Brier Score

Erro quadrático médio entre a probabilidade prevista e a classe observada codificada como 0 ou 1:

```text
média((probabilidade - classe)^2)
```

Valores menores são melhores. Essa métrica avalia a qualidade probabilística, não apenas a classe final.

### 10.10 Log Loss

Penaliza probabilidades incorretas, principalmente previsões erradas feitas com confiança elevada:

```text
-média(y × log(p) + (1 - y) × log(1 - p))
```

Valores menores são melhores. As probabilidades são limitadas numericamente para evitar logaritmo de zero.

### 10.11 Tempo de execução

O tempo armazenado no resumo representa o tempo médio necessário para avaliar uma configuração nos cinco folds de uma repetição. Ele não é necessariamente o tempo total do script.

O tempo depende de:

- processador;
- memória disponível;
- carga simultânea do computador;
- implementação do pacote;
- paralelismo;
- configuração do algoritmo;
- número de registros.

Por isso, o tempo é uma medida prática da execução observada, não uma propriedade universal do algoritmo.

## 11. Resultados da base Cleveland

As subseções 11.1 a 11.5 preservam os resultados da avaliação exploratória original. A subseção 11.6 apresenta a avaliação complementar aninhada e deve ser priorizada para a inferência estatística.

### 11.1 Configurações selecionadas

| Algoritmo | Configuração selecionada |
|---|---|
| Naive Bayes | Gaussiano, `laplace = 1` |
| Árvore de Decisão | `cp = 0,01`, profundidade máxima 5 |
| Random Forest | 500 árvores, `mtry = 4` |
| SVM | Kernel linear, custo 1 |

### 11.2 Resumo completo: média ± desvio-padrão

| Métrica | Naive Bayes | Árvore | Random Forest | SVM |
|---|---:|---:|---:|---:|
| Acurácia | **0,836084 ± 0,005041** | 0,779978 ± 0,001905 | 0,822882 ± 0,018177 | 0,829483 ± 0,006870 |
| Sensibilidade | **0,800959 ± 0,004154** | 0,741007 ± 0,014388 | 0,791367 ± 0,014388 | 0,791367 ± 0,007194 |
| Especificidade | **0,865854 ± 0,006098** | 0,813008 ± 0,012693 | 0,849593 ± 0,023085 | 0,861789 ± 0,018628 |
| Precisão | **0,835017 ± 0,006884** | 0,770743 ± 0,008641 | 0,817095 ± 0,024987 | 0,829505 ± 0,017685 |
| F1 | **0,817631 ± 0,005322** | 0,755468 ± 0,003950 | 0,803978 ± 0,018726 | 0,809863 ± 0,004845 |
| MCC | **0,669375 ± 0,010183** | 0,556127 ± 0,003708 | 0,642849 ± 0,036518 | 0,656207 ± 0,013794 |
| ROC-AUC | **0,905554 ± 0,000769** | 0,809192 ± 0,011860 | 0,897073 ± 0,005782 | 0,896912 ± 0,003476 |
| Brier | 0,131907 ± 0,001148 | 0,174437 ± 0,002507 | 0,129535 ± 0,003946 | **0,125562 ± 0,002360** |
| Log Loss | 0,516369 ± 0,005095 | 0,548690 ± 0,011357 | 0,407236 ± 0,009914 | **0,399012 ± 0,007264** |
| Acurácia balanceada | **0,833406 ± 0,004957** | 0,777008 ± 0,002074 | 0,820480 ± 0,017793 | 0,826578 ± 0,005822 |
| Tempo por configuração/repetição | 0,035061 ± 0,036126 s | **0,026312 ± 0,003970 s** | 0,238429 ± 0,003910 s | 0,060773 ± 0,003253 s |

Em Brier, Log Loss e tempo, valores menores são melhores. O destaque em negrito identifica o melhor valor descritivo, não uma superioridade estatisticamente comprovada.

### 11.3 Ranking de todas as configurações

| Algoritmo/configuração | Acurácia | MCC | ROC-AUC | Brier | Log Loss | Tempo médio (s) |
|---|---:|---:|---:|---:|---:|---:|
| NB Gaussiano | 0,836084 | 0,669375 | 0,905554 | 0,131907 | 0,516369 | 0,0351 |
| NB KDE | 0,829483 | 0,656163 | 0,900143 | 0,136440 | 0,514070 | 0,0365 |
| Árvore cp 0,01; profundidade 5 | 0,779978 | 0,556127 | 0,809192 | 0,174437 | 0,548690 | 0,0263 |
| Árvore cp 0,02; profundidade 5 | 0,777778 | 0,551385 | 0,805127 | 0,176197 | 0,553677 | 0,0240 |
| Árvore cp 0,005; profundidade 3 | 0,773377 | 0,542407 | 0,804666 | 0,177174 | 0,554054 | 0,0358 |
| Árvore cp 0,01; profundidade 3 | 0,772277 | 0,540167 | 0,803028 | 0,177654 | 0,555015 | 0,0274 |
| Árvore cp 0,02; profundidade 3 | 0,772277 | 0,540167 | 0,803028 | 0,177654 | 0,555015 | 0,0247 |
| Árvore cp 0,005; profundidade 5 | 0,771177 | 0,538786 | 0,807049 | 0,178518 | 0,670968 | 0,0234 |
| RF 500 árvores; mtry 4 | 0,822882 | 0,642849 | 0,897073 | 0,129535 | 0,407236 | 0,2384 |
| RF 300 árvores; mtry 4 | 0,820682 | 0,638383 | 0,893095 | 0,131672 | 0,412931 | 0,1544 |
| RF 300 árvores; mtry 3 | 0,818482 | 0,633861 | **0,898703** | **0,129093** | **0,406462** | 0,4648 |
| RF 500 árvores; mtry 3 | 0,812981 | 0,622835 | 0,897650 | 0,129617 | 0,407337 | 0,2329 |
| SVM custo 1 | 0,829483 | 0,656207 | 0,896912 | 0,125562 | 0,399012 | 0,0608 |
| SVM custo 0,1 | 0,819582 | 0,635993 | **0,899588** | **0,126765** | **0,397206** | 0,0928 |
| SVM custo 10 | 0,818482 | 0,633933 | 0,891472 | 0,129549 | 0,412955 | 0,1564 |

Os destaques dentro das alternativas mostram que a configuração selecionada por MCC nem sempre é a melhor em toda métrica complementar. Isso é esperado, pois o critério primário de seleção é o MCC.

### 11.4 Resultados por repetição das configurações selecionadas

| Algoritmo | Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---|---:|---:|---:|---:|---:|
| Naive Bayes | 1 | 0,834983 | 0,816176 | 0,667142 | 0,905510 |
| Naive Bayes | 2 | 0,841584 | 0,823529 | 0,680488 | 0,906343 |
| Naive Bayes | 3 | 0,831683 | 0,813187 | 0,660494 | 0,904808 |
| Árvore | 1 | 0,778878 | 0,758123 | 0,554492 | 0,796609 |
| Árvore | 2 | 0,778878 | 0,750929 | 0,553517 | 0,810800 |
| Árvore | 3 | 0,782178 | 0,757353 | 0,560371 | 0,820166 |
| Random Forest | 1 | 0,831683 | 0,811808 | 0,660474 | 0,902614 |
| Random Forest | 2 | 0,834983 | 0,817518 | 0,667211 | 0,897526 |
| Random Forest | 3 | 0,801980 | 0,782609 | 0,600861 | 0,891077 |
| SVM | 1 | 0,834983 | 0,813433 | 0,667364 | 0,893929 |
| SVM | 2 | 0,831683 | 0,811808 | 0,660474 | 0,900728 |
| SVM | 3 | 0,821782 | 0,804348 | 0,640784 | 0,896078 |

A terceira repetição da Random Forest apresentou redução de desempenho, explicando seu desvio-padrão maior na Cleveland.

### 11.5 Interpretação da Cleveland

- o Naive Bayes apresentou as maiores médias de acurácia, sensibilidade, especificidade, precisão, F1, MCC, ROC-AUC e acurácia balanceada;
- a SVM apresentou os menores Brier Score e Log Loss, indicando melhor resultado probabilístico entre os modelos selecionados;
- Random Forest e SVM ficaram próximas do Naive Bayes nas métricas de classificação;
- a Árvore de Decisão foi inferior, sobretudo na ROC-AUC;
- a diferença de acurácia entre Naive Bayes e SVM foi de aproximadamente 0,66 ponto percentual;
- a diferença entre Naive Bayes e Random Forest foi de aproximadamente 1,32 ponto percentual;
- a diferença entre Naive Bayes e Árvore foi de aproximadamente 5,61 pontos percentuais;
- essas diferenças são descritivas e não devem ser chamadas de estatisticamente significativas.

### 11.6 Avaliação complementar aninhada

A execução `cleveland_ncv_5x3_inner3_v1`, realizada em 7 de setembro de 2026, concluiu os 735 ajustes previstos. Cada resumo abaixo usa média e desvio-padrão dos 15 folds externos, e não das três métricas OOF agregadas por repetição.

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

As configurações selecionadas variaram entre os folds, como se espera quando a seleção é refeita em cada treino externo:

- Naive Bayes: Gaussiano em 13 folds e KDE em 2;
- Árvore: `cp = 0,005`, profundidade 3 em 8 folds; `cp = 0,005`, profundidade 5 em 5; outras duas configurações em 1 fold cada;
- Random Forest: as quatro configurações foram escolhidas entre 2 e 5 vezes;
- SVM: custo 0,1 em 3 folds, custo 1 em 7 e custo 10 em 5.

O ranking do MCC permaneceu igual ao da avaliação exploratória: Naive Bayes, SVM, Random Forest e Árvore. As diferenças entre o MCC antigo e o complementar foram pequenas: `-0,0026`, `-0,0038`, `-0,0075` e `-0,0057`, respectivamente. Assim, a reimplementação não mudou bruscamente a conclusão descritiva.

#### 11.6.1 Comparações pareadas de MCC

| Par, diferença A − B | Diferença média | IC marginal de 95% | p bruto | p Holm |
|---|---:|---:|---:|---:|
| Naive Bayes − Árvore | 0,1163 | [-0,0124; 0,2450] | 0,0730 | 0,4381 |
| Naive Bayes − Random Forest | 0,0314 | [-0,0859; 0,1486] | 0,5753 | 1,0000 |
| Naive Bayes − SVM | 0,0144 | [-0,0692; 0,0980] | 0,7174 | 1,0000 |
| Árvore − Random Forest | -0,0849 | [-0,1828; 0,0129] | 0,0838 | 0,4381 |
| Árvore − SVM | -0,1019 | [-0,2382; 0,0344] | 0,1310 | 0,5241 |
| Random Forest − SVM | -0,0170 | [-0,1180; 0,0841] | 0,7240 | 1,0000 |

O teste t corrigido usa a variância das 15 diferenças pareadas multiplicada por `1/15 + n_teste/n_treino`. A razão média teste/treino foi `0,2500`, e foram usados 14 graus de liberdade. A correção de Holm controla o erro familiar nas seis comparações. Nenhuma foi significativa a `α = 0,05`; consequentemente, H0 não foi rejeitada. Os intervalos acima são marginais e não simultâneos.

Essa conclusão não estabelece equivalência. O tamanho pequeno da Cleveland, a variabilidade entre folds e o total de 15 avaliações limitam o poder para detectar diferenças pequenas. Os diagnósticos das diferenças não mostraram assimetrias extremas, mas o teste continua sendo uma aproximação para reamostragem dependente.

## 12. Resultados da base Kaggle

### 12.1 Configurações selecionadas

| Algoritmo | Configuração selecionada |
|---|---|
| Naive Bayes | Gaussiano, `laplace = 1` |
| Árvore de Decisão | `cp = 0,005`, profundidade máxima 3 |
| Random Forest | 500 árvores, `mtry = 3` |
| SVM | Kernel linear, custo 10 |

### 12.2 Resumo completo: média ± desvio-padrão

| Métrica | Naive Bayes | Árvore | Random Forest | SVM |
|---|---:|---:|---:|---:|
| Acurácia | 0,719910 ± 0,000058 | 0,722674 ± 0,000139 | **0,729952 ± 0,000343** | 0,727790 ± 0,000190 |
| Sensibilidade | 0,622070 ± 0,000112 | 0,653448 ± 0,002075 | **0,689343 ± 0,000680** | 0,655638 ± 0,000236 |
| Especificidade | **0,815695 ± 0,000044** | 0,790447 ± 0,001778 | 0,769708 ± 0,000076 | 0,798427 ± 0,000308 |
| Precisão | **0,767677 ± 0,000052** | 0,753261 ± 0,000991 | 0,745578 ± 0,000204 | 0,761012 ± 0,000283 |
| F1 | 0,687245 ± 0,000082 | 0,699811 ± 0,000767 | **0,716359 ± 0,000458** | 0,704406 ± 0,000198 |
| MCC | 0,446606 ± 0,000112 | 0,448397 ± 0,000118 | **0,460702 ± 0,000669** | 0,459068 ± 0,000392 |
| ROC-AUC | 0,786859 ± 0,000017 | 0,749497 ± 0,001210 | **0,792792 ± 0,000856** | 0,790901 ± 0,000048 |
| Brier | 0,198304 ± 0,000013 | 0,195353 ± 0,000165 | **0,184613 ± 0,000341** | 0,187107 ± 0,000021 |
| Log Loss | 0,647599 ± 0,000079 | 0,578453 ± 0,000384 | **0,552013 ± 0,000875** | 0,561684 ± 0,000053 |
| Acurácia balanceada | 0,718882 ± 0,000059 | 0,721947 ± 0,000158 | **0,729526 ± 0,000346** | 0,727032 ± 0,000190 |
| Tempo por configuração/repetição | **0,3125 ± 0,2004 s** | 0,6826 ± 0,0581 s | 301,8479 ± 7,0332 s | 6.475,8312 ± 3.713,6640 s |

### 12.3 Ranking de todas as configurações

| Algoritmo/configuração | Acurácia | MCC | ROC-AUC | Brier | Log Loss | Tempo médio (s) |
|---|---:|---:|---:|---:|---:|---:|
| NB Gaussiano | 0,719910 | 0,446606 | 0,786859 | 0,198304 | 0,647599 | 0,3125 |
| NB KDE | 0,715348 | 0,443396 | 0,785157 | 0,211446 | 0,662209 | 0,1824 |
| Árvore cp 0,005; profundidade 3 | 0,722674 | **0,448397** | 0,749497 | 0,195353 | 0,578453 | 0,6826 |
| Árvore cp 0,005; profundidade 5 | **0,723923** | 0,448151 | **0,751777** | **0,194801** | **0,577326** | 0,8697 |
| Árvore cp 0,01; profundidade 3 | 0,713074 | 0,432280 | 0,710640 | 0,203265 | 0,596074 | 0,6321 |
| Árvore cp 0,01; profundidade 5 | 0,713074 | 0,432280 | 0,710640 | 0,203265 | 0,596074 | 0,8515 |
| Árvore cp 0,02; profundidade 3 | 0,713074 | 0,432280 | 0,710640 | 0,203265 | 0,596074 | 0,6613 |
| Árvore cp 0,02; profundidade 5 | 0,713074 | 0,432280 | 0,710640 | 0,203265 | 0,596074 | 0,7950 |
| RF 500 árvores; mtry 3 | 0,729952 | 0,460702 | 0,792792 | 0,184613 | 0,552013 | 301,8479 |
| RF 300 árvores; mtry 3 | 0,729456 | 0,459698 | 0,792440 | 0,184793 | 0,552540 | 182,2453 |
| RF 500 árvores; mtry 4 | 0,724574 | 0,449553 | 0,785983 | 0,188131 | 0,561767 | 378,2820 |
| RF 300 árvores; mtry 4 | 0,724340 | 0,449049 | 0,785612 | 0,188328 | 0,562526 | 239,6194 |
| SVM custo 10 | **0,727790** | **0,459068** | 0,790901 | 0,187107 | 0,561684 | 6.475,8312 |
| SVM custo 1 | 0,727775 | 0,459039 | 0,790903 | 0,187108 | 0,561681 | 1.762,8567 |
| SVM custo 0,1 | 0,727746 | 0,458961 | **0,790922** | **0,187093** | **0,561656** | 1.121,8555 |

Observações importantes:

- a árvore de profundidade 5 possui maior acurácia, F1 e ROC-AUC que a árvore selecionada, mas seu MCC é `0,000246` menor; por isso, o protocolo selecionou profundidade 3;
- a RF com 300 árvores e `mtry = 3` perde somente `0,001004` de MCC para a configuração de 500 árvores, enquanto reduz o tempo médio de aproximadamente 302 para 182 segundos;
- as três SVMs são praticamente indistinguíveis nas métricas;
- a SVM de custo 10 foi selecionada por uma vantagem de somente `0,000029` de MCC sobre custo 1 e `0,000107` sobre custo 0,1;
- essa vantagem mínima não compensa automaticamente o custo computacional muito maior;
- para uso prático futuro, a configuração de custo 0,1 ou 1 pode ser preferível por parcimônia, desde que qualquer mudança seja declarada e os resultados oficiais sejam recalculados.

### 12.4 Resultados por repetição das configurações selecionadas

| Algoritmo | Repetição | Acurácia | F1 | MCC | ROC-AUC |
|---|---:|---:|---:|---:|---:|
| Naive Bayes | 1 | 0,719851 | 0,687173 | 0,446491 | 0,786855 |
| Naive Bayes | 2 | 0,719910 | 0,687228 | 0,446614 | 0,786845 |
| Naive Bayes | 3 | 0,719968 | 0,687334 | 0,446714 | 0,786877 |
| Árvore | 1 | 0,722679 | 0,700112 | 0,448307 | 0,750505 |
| Árvore | 2 | 0,722810 | 0,700381 | 0,448530 | 0,749832 |
| Árvore | 3 | 0,722533 | 0,698939 | 0,448354 | 0,748155 |
| Random Forest | 1 | 0,729617 | 0,715898 | 0,460050 | 0,791869 |
| Random Forest | 2 | 0,729937 | 0,716365 | 0,460668 | 0,792947 |
| Random Forest | 3 | 0,730302 | 0,716813 | 0,461387 | 0,793559 |
| SVM | 1 | 0,727591 | 0,704179 | 0,458669 | 0,790930 |
| SVM | 2 | 0,727970 | 0,704543 | 0,459452 | 0,790845 |
| SVM | 3 | 0,727809 | 0,704495 | 0,459082 | 0,790927 |

### 12.5 Interpretação da Kaggle

- a Random Forest apresentou o melhor resultado descritivo na maioria das métricas;
- a Random Forest obteve maior sensibilidade, enquanto Naive Bayes obteve maior especificidade e precisão;
- isso indica que Naive Bayes é mais conservador ao atribuir a classe positiva e deixa de identificar mais positivos;
- Random Forest e SVM possuem desempenho muito próximo em acurácia, MCC e ROC-AUC;
- a diferença de acurácia entre Random Forest e SVM é de aproximadamente 0,22 ponto percentual;
- a diferença de MCC entre Random Forest e SVM é de apenas `0,0016`;
- a diferença de acurácia entre o primeiro e o último algoritmo é de aproximadamente 1,00 ponto percentual;
- a Árvore possui acurácia próxima das demais, mas ROC-AUC claramente inferior;
- a estabilidade entre repetições é muito alta devido ao grande tamanho amostral;
- a baixa variação não implica que diferenças pequenas sejam clinicamente importantes;
- com sensibilidade de `0,6893`, a Random Forest deixa de identificar aproximadamente 31% dos positivos no limiar 0,5, o que impede interpretar o modelo como ferramenta clínica autônoma.

## 13. Comparação entre as duas bases

Para manter protocolos equivalentes, a tabela entre bases usa a camada exploratória 5 × 3 em ambas. Os resultados aninhados da Cleveland não são misturados diretamente aos resultados não aninhados da Kaggle.

| Algoritmo | Acurácia Cleveland | Acurácia Kaggle | MCC Cleveland | MCC Kaggle | ROC-AUC Cleveland | ROC-AUC Kaggle |
|---|---:|---:|---:|---:|---:|---:|
| Naive Bayes | 0,8361 | 0,7199 | 0,6694 | 0,4466 | 0,9056 | 0,7869 |
| Árvore | 0,7800 | 0,7227 | 0,5561 | 0,4484 | 0,8092 | 0,7495 |
| Random Forest | 0,8229 | 0,7300 | 0,6428 | 0,4607 | 0,8971 | 0,7928 |
| SVM | 0,8295 | 0,7278 | 0,6562 | 0,4591 | 0,8969 | 0,7909 |

Os resultados da Kaggle são inferiores aos da Cleveland, apesar de a Kaggle possuir muito mais registros. Isso não é uma contradição. Quantidade de dados e quantidade de informação preditiva não são a mesma coisa.

A Cleveland possui variáveis clínicas mais diretamente relacionadas ao diagnóstico, como dor torácica, frequência cardíaca máxima, angina por exercício, segmento ST, vasos principais e talassemia. A Kaggle possui variáveis mais gerais, como altura, peso, hábitos e categorias de exames. Além disso, as bases têm populações, distribuições e definições do desfecho diferentes.

Consequentemente:

- a comparação mostra o comportamento dos algoritmos em dois contextos;
- ela não isola exclusivamente o efeito do aumento de 303 para 68.610 registros;
- não é correto afirmar que a perda de acurácia foi causada pelo aumento da base;
- também não é correto concluir que mais dados pioram necessariamente o modelo;
- a base maior produz estimativas mais estáveis, mas seu conjunto de variáveis pode impor um teto preditivo menor.

## 14. Por que os algoritmos apresentam resultados próximos

A proximidade entre algoritmos diferentes não é, por si só, indício de erro. Algoritmos distintos podem aprender fronteiras parecidas quando recebem as mesmas variáveis e quando o sinal disponível é relativamente simples ou limitado.

Uma análise exploratória das probabilidades OOF encontrou as seguintes correlações:

### 14.1 Cleveland

- Naive Bayes × Random Forest: `0,899`;
- Naive Bayes × SVM: `0,901`;
- Random Forest × SVM: `0,943`;
- os quatro algoritmos acertaram simultaneamente aproximadamente `70,3%` dos registros;
- os quatro erraram simultaneamente aproximadamente `9,13%` dos registros.

### 14.2 Kaggle

- Naive Bayes × Árvore: `0,842`;
- Naive Bayes × Random Forest: `0,899`;
- Naive Bayes × SVM: `0,951`;
- Árvore × Random Forest: `0,853`;
- Árvore × SVM: `0,847`;
- Random Forest × SVM: `0,907`;
- os quatro algoritmos acertaram simultaneamente aproximadamente `64,02%` dos registros;
- os quatro erraram simultaneamente aproximadamente `19,63%` dos registros.

Esses valores sugerem que os modelos exploram grande parte do mesmo sinal e encontram muitos casos fáceis e difíceis em comum. Na Kaggle, a elevada quantidade de erros compartilhados sugere limitação de informação, sobreposição entre as classes e possível ruído do desfecho. Essa análise é exploratória e não substitui as métricas oficiais.

## 15. Avaliação do pré-processamento

### 15.1 Cleveland

Não há evidência de que seja necessário remover registros ou aplicar uma limpeza mais agressiva. Os seis valores ausentes já recebem tratamento dentro dos folds quando necessário. A pequena amostra recomenda preservar dados e evitar decisões orientadas pela tentativa de aumentar acurácia.

### 15.2 Kaggle

A limpeza atual remove medidas claramente implausíveis, preserva 98,01% da base e mantém classes aproximadamente equilibradas. Não há justificativa para:

- aplicar SMOTE;
- remover observações apenas por repetirem combinações de atributos;
- excluir novos registros somente porque são difíceis de classificar;
- criar regras de limpeza escolhidas após observar qual delas aumenta a acurácia.

Novas transformações podem ser avaliadas como análise secundária, por exemplo:

- índice de massa corporal: `peso / altura²`;
- pressão de pulso: `pressao_sistolica - pressao_diastolica`;
- categorias clinicamente justificadas de pressão arterial;
- interações simples previamente definidas.

Essas novas variáveis mudariam o experimento. Elas deveriam ser documentadas, aplicadas de maneira idêntica aos quatro algoritmos e avaliadas em uma nova execução. Qualquer transformação que aprenda parâmetros nos dados deve ser ajustada apenas no treino de cada fold.

## 16. Comparação com resultados publicados

### 16.1 Cleveland

Um estudo que avaliou os mesmos tipos de algoritmos na Cleveland reportou:

- Árvore de Decisão: 77,86% de acurácia;
- Random Forest: 78,68%;
- Naive Bayes: 81,14%;
- SVM: 79,05%;
- ensemble proposto: 88,24%.

Na avaliação complementar deste projeto, os resultados foram 77,45%, 81,61%, 83,28% e 82,50%, respectivamente. Assim, permanecem próximos ou acima da faixa dos classificadores clássicos desse estudo. O ensemble publicado permanece superior em acurácia, mas a comparação não é direta porque os protocolos diferem.

Fonte: [A Reliable Machine Intelligence Model for Accurate Identification of Cardiovascular Diseases Using Ensemble Techniques](https://pmc.ncbi.nlm.nih.gov/articles/PMC8923755/).

Outro estudo reportou, na Cleveland, acurácia 0,84 e AUC 0,82 para um modelo desenvolvido manualmente, e acurácia 0,85 e AUC 0,93 para AutoML. O melhor resultado complementar deste projeto, acurácia média por fold de 0,8328 e ROC-AUC de 0,9100, também se encontra nessa faixa.

### 16.2 Kaggle

Um estudo com os mesmos 70.000 registros separou 14.000 para teste final. O modelo manual selecionado, uma árvore ajustada com *bagging*, obteve acurácia `0,74` e AUC `0,73`. O AutoML obteve acurácia `0,74` e AUC `0,80`.

Neste projeto, Random Forest e SVM obtiveram acurácias próximas de `0,73` e AUCs próximas de `0,79`. Portanto, os resultados são compatíveis com uma referência publicada que usou uma avaliação independente.

Fonte: [Physician-Friendly Machine Learning: A Case Study with Cardiovascular Disease Risk Prediction](https://doi.org/10.3390/jcm8071050).

### 16.3 Cuidados na comparação

Os números da literatura não constituem uma competição direta porque podem variar em:

- divisão entre treino e teste;
- versões e limpeza da base;
- tratamento de variáveis;
- seleção de atributos;
- balanceamento;
- hiperparâmetros;
- limiar de classificação;
- escolha de classe positiva;
- uso de validação simples, cruzada, aninhada ou teste externo;
- presença de ensembles e engenharia de atributos.

Portanto, o texto deve usar expressões como **compatível com**, **na mesma faixa** ou **competitivo em relação a**, e não afirmar superioridade sobre um estudo que utilizou outro protocolo.

Resultados publicados próximos de 90% ou 100% devem ser examinados com cautela, especialmente quando não há conjunto de teste independente, quando a seleção de atributos ocorre antes da validação ou quando registros relacionados aparecem simultaneamente no treino e no teste.

## 17. Os algoritmos são cientificamente defensáveis?

Sim, para o objetivo delimitado do PIBIC. Os quatro algoritmos:

- são métodos estabelecidos de aprendizado supervisionado;
- representam abordagens conceitualmente diferentes;
- são encontrados como classificadores individuais ou baselines na literatura;
- foram avaliados com as mesmas divisões e métricas;
- possuem grades pequenas, transparentes e reprodutíveis;
- na Cleveland complementar, a seleção interna foi separada da avaliação externa;
- a comparação inferencial reconheceu o pareamento e corrigiu dependência e multiplicidade;
- permitem discutir interpretabilidade, desempenho e custo computacional.

Entretanto, a defesa científica exige limitar a conclusão:

- o estudo compara **estas implementações e estas configurações**;
- a SVM avaliada é linear, não toda a família de SVMs;
- a grade é intencionalmente pequena por restrição computacional;
- não foram incluídos métodos como regressão logística, gradient boosting, XGBoost ou redes neurais;
- não há validação externa ou prospectiva;
- os modelos não devem ser apresentados como ferramentas diagnósticas prontas para uso clínico.

Os resultados podem ser considerados bons como *baselines* acadêmicos. Na Cleveland são competitivos com classificadores clássicos publicados. Na Kaggle, o desempenho é moderado, porém semelhante a referências metodologicamente razoáveis da mesma base.

## 18. Significância estatística

### 18.1 Procedimento executado

A inferência foi realizada apenas na avaliação complementar da Cleveland. O MCC foi definido como desfecho primário, e os quatro algoritmos compartilharam as mesmas 15 partições externas. Para cada um dos seis pares, calcularam-se as diferenças de MCC fold a fold e aplicou-se o teste t corrigido de Nadeau–Bengio.

O erro-padrão foi calculado como `sqrt((1/n + n_teste/n_treino) × variância_das_diferenças)`, com `n = 15`, razão média teste/treino aproximadamente `0,25` e 14 graus de liberdade. Os seis p-valores bilaterais foram ajustados pelo método de Holm. Não se tratou os folds como observações independentes.

### 18.2 O que pode ser afirmado

Nenhuma comparação foi significativa a `α = 0,05`. Os p-valores ajustados foram `0,4381`, `1,0000`, `1,0000`, `0,4381`, `0,5241` e `1,0000`. Assim, **H0 não foi rejeitada na Cleveland complementar**.

Não rejeitar H0 não prova que os algoritmos sejam iguais. Significa que o experimento não forneceu evidência suficiente de diferença estatística, considerando a correção pela dependência e pelas seis comparações. O Naive Bayes liderou descritivamente, mas sua vantagem também não foi significativa.

Na Kaggle, a análise continua descritiva. Não se deve extrapolar para ela o resultado inferencial da Cleveland.

### 18.3 Importância prática das diferenças observadas

Na Cleveland:

- Naive Bayes, SVM e Random Forest formam um grupo relativamente próximo;
- a Árvore fica de 4,16 a 5,83 pontos percentuais abaixo deles em acurácia na avaliação complementar;
- a distância de ROC-AUC entre Árvore e os três melhores é maior que as diferenças dentro do grupo superior.

Na Kaggle:

- Random Forest e SVM estão praticamente empatadas;
- todos os algoritmos estão dentro de aproximadamente um ponto percentual de acurácia;
- a vantagem de Random Forest sobre SVM é pequena demais para justificar, sozinha, uma conclusão forte;
- o tamanho elevado da amostra pode tornar diferenças muito pequenas estatisticamente detectáveis, mas isso não as torna automaticamente relevantes na prática.

### 18.4 Possíveis extensões futuras

Uma confirmação mais forte exigiria amostra externa independente ou mais repetições definidas previamente. Em um teste externo, McNemar pode comparar erros de classificação, DeLong pode comparar ROC-AUC e reamostragem pareada pode fornecer incerteza para MCC e F1. Qualquer extensão deve manter a seleção de hiperparâmetros e o pré-processamento separados da avaliação final.

Referências metodológicas:

- [Dietterich — Approximate Statistical Tests for Comparing Supervised Classification Learning Algorithms](https://pubmed.ncbi.nlm.nih.gov/9744903/);
- [Nadeau e Bengio — Inference for the Generalization Error](https://doi.org/10.1023/A:1024068626366);
- [Cawley e Talbot — On Over-fitting in Model Selection and Subsequent Selection Bias in Performance Evaluation](https://www.jmlr.org/papers/v11/cawley10a.html).

## 19. Limitações metodológicas

### 19.1 Dois níveis de evidência

A avaliação complementar da Cleveland é aninhada e separa seleção e teste externo. A avaliação exploratória antiga e toda a análise Kaggle permanecem não aninhadas: nelas, a mesma CV participa da seleção e do resumo. Esses resultados continuam úteis de forma descritiva, mas não entram na inferência complementar.

### 19.2 Apenas três repetições

Três repetições constituem um compromisso computacional. São suficientes para observar variação básica e manter o projeto executável, mas insuficientes para inferência robusta baseada somente nas repetições.

### 19.3 Cleveland pequena

Com 303 registros, pequenas mudanças nos folds podem alterar os resultados. Os desvios-padrão, especialmente o da Random Forest, demonstram essa sensibilidade.

### 19.4 Kaggle retrospectiva e pública

A base Kaggle não representa validação prospectiva em ambiente clínico real. Podem existir ruído do desfecho, erros de medição, limitações de documentação e vieses de seleção.

### 19.5 Ausência de validação externa

Não foi avaliada a capacidade de transportar o modelo para outro hospital, período, país ou população.

### 19.6 Limiar fixo

O limiar `0,5` facilita a comparação, mas não foi escolhido conforme custos clínicos de falsos negativos e falsos positivos. Outro limiar modificaria sensibilidade, especificidade, precisão, F1, MCC e acurácia, mas não a ROC-AUC.

### 19.7 Comparação temporal

A Kaggle utiliza dois processos para folds, enquanto a Cleveland é executada sequencialmente. Por isso, não se deve atribuir toda diferença de tempo apenas ao tamanho da base. Uma avaliação rigorosa de escalabilidade exigiria:

- mesmo computador;
- mesma carga do sistema;
- mesmo número de processos e threads;
- várias repetições temporais independentes;
- medição isolada de carregamento, pré-processamento, treino e predição.

### 19.8 Escopo dos algoritmos

As conclusões não abrangem toda combinação possível de hiperparâmetros, kernels, balanceamentos, seleção de atributos ou engenharia de variáveis.

## 20. Arquivos de resultados

Na camada exploratória, cada algoritmo produz cinco CSVs em `results/csvs/`:

1. `*_cv_resultados_configuracoes.csv`: uma linha por configuração e repetição, com métricas e tempo;
2. `*_cv_ranking_configuracoes.csv`: médias das configurações ordenadas pelo critério de seleção;
3. `*_cv_resultados_repeticoes.csv`: somente as três repetições da configuração selecionada;
4. `*_cv_resumo_modelo.csv`: média e desvio-padrão do modelo selecionado;
5. `*_cv_predicoes_oof.csv`: previsões fora da amostra do modelo selecionado.

Os prefixos são:

- `naive_bayes`;
- `decision_trees`;
- `random_forest`;
- `svm`.

O arquivo de previsões OOF contém:

- repetição;
- semente;
- configuração;
- fold;
- identificador do registro;
- classe real;
- probabilidade de doença;
- classe prevista.

Na avaliação complementar, cada algoritmo produz oito CSVs em `results/cleveland_ncv_5x3_inner3_v1/csvs/`:

1. `*_ncv_metricas_internas.csv`: uma linha por configuração e fold interno;
2. `*_ncv_ranking_interno.csv`: ranking dentro de cada treino externo;
3. `*_ncv_resultados_folds.csv`: métricas dos 15 testes externos;
4. `*_ncv_configuracoes_selecionadas.csv`: escolha de cada fold externo;
5. `*_ncv_frequencia_configuracoes.csv`: frequência das escolhas;
6. `*_ncv_predicoes_oof.csv`: 909 previsões externas;
7. `*_ncv_resumo_modelo.csv`: média e DP dos 15 folds externos;
8. `*_ncv_resultados_repeticoes_oof.csv`: métricas OOF reunidas por repetição.

O subdiretório `inferencia/` contém diferenças fold a fold, seis comparações pareadas e a decisão global. `manifest/` contém a validação de integridade, versões e assinaturas; `partitions/` contém os folds e as sementes. Checkpoints RDS são artefatos locais de retomada.

## 21. Gráficos

O script `src/compare_models.r` gera 11 imagens independentes:

1. acurácia;
2. sensibilidade;
3. especificidade;
4. precisão;
5. F1;
6. MCC;
7. ROC-AUC;
8. acurácia balanceada;
9. Brier Score;
10. Log Loss;
11. tempo.

Cada imagem possui:

- média de cada algoritmo;
- barra de erro correspondente a um desvio-padrão;
- mesma cor por algoritmo em todas as métricas;
- dimensão de 2.400 × 1.600 pixels;
- resolução de 240 dpi;
- escala entre 0 e 1 para as oito métricas de classificação e discriminação;
- indicação de que Brier, Log Loss e tempo são melhores quando menores.

As imagens comparativas das duas bases já existem. Os 11 gráficos da Kaggle foram gerados em 6 de setembro de 2026 a partir dos quatro resumos exploratórios oficiais. A Cleveland complementar acrescenta 11 gráficos de métricas, um gráfico das seis diferenças médias de MCC com intervalos marginais e 12 diagnósticos — série e Q-Q para cada par.

## 22. Dependências e ambiente

Dependências principais:

- R;
- `ucimlrepo`, somente para importar a Cleveland;
- `naivebayes`;
- `rpart`;
- `ranger`;
- `e1071`;
- `parallel`, incluído no próprio R.

Os scripts pressupõem que os pacotes já estejam instalados. Nenhum script executa `install.packages()`.

Uma execução registrada utilizou:

- R 4.5.1;
- plataforma `x86_64-w64-mingw32/x64`;
- Windows.

## 23. Como reproduzir

### 23.1 Cleveland

A partir da pasta `Clevand`, para reproduzir a avaliação complementar:

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

Os scripts `src/naive_bayes.r`, `src/decision_trees.r`, `src/random_forest.r`, `src/svm.r` e `src/compare_models.r` permanecem disponíveis para reproduzir a etapa exploratória original.

### 23.2 Kaggle

A partir da pasta `Kaggle`:

```powershell
Rscript src/naive_bayes.r
Rscript src/decision_trees.r
Rscript src/random_forest.r
Rscript src/svm.r
Rscript src/compare_models.r
```

Executar um script a partir de outra pasta pode impedir a localização dos arquivos relativos em `src/`, `dataset/` e `results/`.

A SVM da Kaggle é, de longe, a etapa mais demorada. Antes de repeti-la, deve-se confirmar que uma nova execução é realmente necessária. Alterar grade, sementes, folds, limiar, pré-processamento ou número de registros exige nova execução e atualização dos resultados.

## 24. Conclusões finais

1. Os quatro algoritmos são cientificamente adequados para uma comparação acadêmica em um projeto PIBIC.
2. O protocolo exploratório 5-fold repetido 3 vezes é um compromisso razoável entre informação e custo computacional.
3. A avaliação complementar aninhada da Cleveland separa seleção e avaliação e concluiu 735 ajustes em poucos segundos.
4. Na Cleveland, o Naive Bayes apresentou o melhor desempenho descritivo geral, com MCC externo médio de `0,6667`.
5. Na Kaggle, a Random Forest apresentou o melhor desempenho descritivo, mas ficou praticamente empatada com a SVM.
6. A Árvore de Decisão é mais interpretável, porém apresentou menor capacidade discriminativa.
7. A SVM da Kaggle apresentou custo computacional desproporcional à pequena diferença observada.
8. O pré-processamento atual é suficiente; não há justificativa para limpeza mais agressiva orientada por desempenho.
9. Os resultados complementares ficaram próximos dos exploratórios e mantiveram o mesmo ranking de MCC.
10. Nenhuma das seis comparações de MCC foi significativa após Holm; H0 não foi rejeitada na Cleveland complementar.
11. A não rejeição de H0 não demonstra equivalência entre os algoritmos.
12. A hipótese direcional de superioridade da Random Forest não foi corroborada.
13. A inferência não foi estendida à Kaggle por limitação computacional; seus resultados são descritivos.
14. Os resultados não validam uso clínico e não demonstram generalização externa.

## 25. Texto resumido reutilizável

> Foram avaliados Naive Bayes, Árvore de Decisão, Random Forest e SVM linear nas bases Cleveland e Cardiovascular Disease Dataset do Kaggle. A etapa exploratória usou validação cruzada estratificada de cinco folds repetida três vezes. Na Cleveland foi acrescentada validação cruzada aninhada, com os mesmos 5 × 3 folds no ciclo externo e três folds internos para seleção por MCC. O pré-processamento foi aprendido somente nos treinos. O Naive Bayes obteve o maior MCC externo médio na Cleveland (`0,6667`), seguido por SVM (`0,6524`), Random Forest (`0,6354`) e Árvore (`0,5504`). As seis diferenças pareadas de MCC foram analisadas pelo teste t corrigido de Nadeau–Bengio e por Holm; nenhuma foi significativa (`menor p ajustado = 0,4381`). H0 não foi rejeitada, sem que isso implique equivalência, e a hipótese direcional de superioridade da Random Forest não foi corroborada. Na Kaggle descritiva, Random Forest e SVM permaneceram muito próximas. O estudo não constitui validação clínica ou externa.

## 26. Referências principais

1. UCI Machine Learning Repository. [Heart Disease Dataset](https://archive.ics.uci.edu/dataset/45/heart+disease).
2. Kaggle. [Cardiovascular Disease Dataset](https://www.kaggle.com/datasets/sulianova/cardiovascular-disease-dataset/data).
3. Padmanabhan M, Yuan P, Chada G, Nguyen HV. [Physician-Friendly Machine Learning: A Case Study with Cardiovascular Disease Risk Prediction](https://doi.org/10.3390/jcm8071050). Journal of Clinical Medicine, 2019.
4. [A Reliable Machine Intelligence Model for Accurate Identification of Cardiovascular Diseases Using Ensemble Techniques](https://pmc.ncbi.nlm.nih.gov/articles/PMC8923755/).
5. Dietterich TG. [Approximate Statistical Tests for Comparing Supervised Classification Learning Algorithms](https://pubmed.ncbi.nlm.nih.gov/9744903/). Neural Computation, 1998.
6. Nadeau C, Bengio Y. [Inference for the Generalization Error](https://doi.org/10.1023/A:1024068626366). Machine Learning, 2003.
7. Cawley GC, Talbot NLC. [On Over-fitting in Model Selection and Subsequent Selection Bias in Performance Evaluation](https://www.jmlr.org/papers/v11/cawley10a.html). Journal of Machine Learning Research, 2010.
