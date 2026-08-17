# Análise de Doença Cardíaca — Naive Bayes

## Objetivo

Este projeto estima a presença de doença cardíaca a partir da base **Heart Disease — Cleveland**, do [UCI Machine Learning Repository](https://archive.ics.uci.edu/dataset/45/heart+disease). O desfecho é binário:

- `sem_doenca`: valor original `num = 0`;
- `doenca`: valores originais `num = 1`, `2`, `3` ou `4`.

O experimento avalia duas famílias do mesmo algoritmo: Naive Bayes Gaussiano e Naive Bayes com estimação de densidade por kernel (KDE). A comparação é feita sem usar os dados de teste para escolher hiperparâmetros ou limiar de decisão.

## Arquivos

| Arquivo | Responsabilidade |
|---|---|
| `src/naive_bayes.R` | Ajusta, seleciona e avalia o Naive Bayes; apresenta os resultados e salva o modelo final. |
| `src/heart_disease_data.R` | Importa o subconjunto Cleveland, traduz os nomes das variáveis e prepara a classe-alvo. É compartilhado por todos os algoritmos. |
| `src/common_evaluation.R` | Funções reutilizáveis de reamostragem, métricas, seleção de limiar, resumos e cálculo do teste 5x2cv. |
| `models/modelo_naive_bayes_heart_disease.rds` | Modelo final treinado em todos os dados, acompanhado da configuração, limiar e metadados necessários para novas predições. |

## Bibliotecas

| Biblioteca | Uso no projeto |
|---|---|
| `naivebayes` | Implementação do modelo por `naivebayes::naive_bayes()`. Suporta versões Gaussianas e KDE, suavização de Laplace e ajuste de largura de banda. |
| `withr` | Executa a geração de folds com uma semente local (`withr::with_seed()`), sem alterar o estado global do gerador aleatório. |
| `utils` (R base) | Download da base UCI, leitura do CSV e extração do ZIP de contingência. |
| `stats` (R base) | Desvio-padrão e distribuição t para o teste 5x2cv. |

O script **não instala pacotes automaticamente**. Antes da primeira execução, instale manualmente as dependências:

```r
install.packages(c("naivebayes", "withr"))
```

## Dados e pré-processamento

O código usa deliberadamente `processed.cleveland.data`, isto é, o subconjunto Cleveland com **303 pacientes**. A URL histórica é tentada primeiro; se estiver indisponível, o script baixa o ZIP oficial da UCI e extrai o mesmo arquivo. Essa escolha fixa a versão da base e torna o estudo reproduzível.

As colunas usadas no código recebem nomes semânticos em português. A primeira coluna da tabela mostra a abreviação original da UCI, apenas para facilitar a consulta da documentação da base.

| UCI original | Nome usado no código | Significado |
|---|---|---|
| `age` | `idade` | Idade do paciente, em anos. |
| `sex` | `sexo` | Sexo codificado pela base. |
| `cp` | `tipo_dor_toracica` | Tipo de dor torácica. |
| `trestbps` | `pressao_arterial_repouso` | Pressão arterial em repouso. |
| `chol` | `colesterol_serico` | Colesterol sérico, em mg/dl. |
| `fbs` | `glicemia_jejum` | Glicemia de jejum acima de 120 mg/dl. |
| `restecg` | `eletrocardiograma_repouso` | Resultado do eletrocardiograma em repouso. |
| `thalach` | `frequencia_cardiaca_maxima` | Frequência cardíaca máxima atingida. |
| `exang` | `angina_induzida_exercicio` | Presença de angina induzida por exercício. |
| `oldpeak` | `depressao_segmento_st` | Depressão do segmento ST induzida por exercício. |
| `slope` | `inclinacao_segmento_st` | Inclinação do segmento ST no pico do exercício. |
| `ca` | `vasos_principais` | Quantidade de vasos principais visualizados por fluoroscopia. |
| `thal` | `talassemia` | Resultado do exame de talassemia. |
| `num` | `classe_doenca` | Variável-alvo: ausência (`0`) ou presença (`1` a `4`) de doença. |

As variáveis categóricas são convertidas para fator. Existem seis valores ausentes na base: quatro em `vasos_principais` e dois em `talassemia`. Eles são mantidos: o pacote `naivebayes` ignora apenas a contribuição da variável ausente para aquele paciente. Assim, não se descartam seis prontuários inteiros nem se faz imputação antes dos folds, o que poderia introduzir vazamento de informação.

## Protocolo experimental

### Avaliação principal: validação cruzada aninhada

A avaliação de generalização usa **10-fold estratificado repetido 5 vezes**. Em cada fold externo, aproximadamente 90% dos registros (272–273 pacientes) são usados para treino e 10% (30–31) para teste. Como há cinco repetições, são produzidas 50 avaliações externas.

Dentro de cada treino externo, ocorre uma validação interna **5-fold estratificada repetida 3 vezes**, usada exclusivamente para escolher a configuração e o limiar de classificação. Portanto, o fold externo de teste não influencia nenhuma escolha do modelo.

Esta estratégia é preferível a uma única divisão 70/30 para uma base de 303 registros: todos os pacientes participam de testes em diferentes repetições, e o resultado é apresentado como média ± desvio-padrão. O desvio-padrão dos 50 folds descreve **variabilidade entre folds**, não o erro-padrão de 50 amostras independentes; os folds compartilham dados de treino e cada paciente aparece no teste uma vez por repetição. Portanto, ele não é usado para construir intervalos de confiança. Os folds repetidos também não são tratados como observações independentes para o teste estatístico.

### Configurações avaliadas

O ajuste compara:

- Naive Bayes **Gaussiano**, com `laplace = 0.5`, `1` e `2`;
- Naive Bayes com **KDE**, com os mesmos valores de `laplace` e `adjust = 0.5`, `1` e `1.5`.

A suavização de Laplace reduz o risco de probabilidades nulas para categorias raras. No KDE, `adjust` controla a largura de banda; valores maiores produzem curvas mais suavizadas.

### Limiar de decisão

As probabilidades preditas não são automaticamente convertidas usando apenas o corte 0,5. Para cada configuração, o código reúne as predições fora da amostra (out-of-fold) do treino interno e procura o limiar que maximiza:

1. MCC;
2. F1, em caso de empate no MCC;
3. proximidade de 0,5, se MCC e F1 empatarem.

O cálculo avalia todos os cortes relevantes entre probabilidades distintas, incluindo as possibilidades de prever todos os casos como positivos ou negativos. Assim, o limiar não depende de uma grade arbitrária.

O MCC é mantido como critério primário porque considera os quatro elementos da matriz de confusão e permanece informativo com classes desbalanceadas. Ele trata falsos negativos e falsos positivos de forma simétrica. Caso o estudo passe a exigir uma política clínica explícita — por exemplo, sensibilidade mínima de 0,90 — esse novo objetivo deve ser definido previamente e selecionado apenas com as predições da validação interna, nunca no fold externo de teste.

### Teste estatístico entre famílias

Após a avaliação principal, o script executa o teste t **5x2cv de Dietterich (1998)**, com F1 como métrica primária. Em cada uma das cinco repetições, a base é dividida em duas metades: uma é usada para treino e a outra para teste, alternando-se as metades. Dentro de cada metade de treino, a configuração e o limiar são novamente selecionados.

O teste compara os pipelines completos Gaussiano e KDE. Ele é mais apropriado que um t-test pareado comum sobre os folds repetidos, pois os conjuntos de treino entre folds compartilham observações. O teste de Dietterich foi originalmente derivado para taxa de erro; seu uso com F1 é uma extensão usual. Como evidência complementar, o script também reporta o **F-test combinado 5x2cv de Alpaydın (1999)**, que utiliza as dez diferenças de F1, sem substituir o resultado de Dietterich.

## Métricas de avaliação

Todas as métricas usam `doenca` como classe positiva.

| Métrica | Interpretação |
|---|---|
| Acurácia | Proporção total de classificações corretas. |
| Sensibilidade (recall) | Proporção de pacientes com doença corretamente identificados. |
| Especificidade | Proporção de pacientes sem doença corretamente identificados. |
| Precisão | Entre os casos previstos como doença, proporção realmente doente. |
| F1 | Média harmônica entre precisão e sensibilidade. |
| MCC | Correlação de Matthews; resumo robusto mesmo quando há desequilíbrio de classes. É o critério primário de seleção. |
| ROC-AUC | Capacidade de ordenar casos com e sem doença ao longo de todos os limiares. |
| PR-AUC | Área precisão-recall; verificação complementar do desempenho da classe positiva. |
| Acurácia balanceada | Média entre sensibilidade e especificidade. |
| NPV | Entre os casos previstos como sem doença, proporção realmente sem doença. |

Além das métricas, o terminal exibe a matriz de confusão agregada dos 50 folds externos e a frequência de seleção de cada configuração. Essa matriz é descritiva: ela soma 1.515 predições (303 pacientes × 5 repetições), portanto cada paciente contribui cinco vezes; não é a matriz de confusão de um único experimento com 303 pacientes.

## Funções reutilizáveis (`common_evaluation.R`)

| Função | Finalidade |
|---|---|
| `stratified_fold_ids()` | Atribui cada registro a um fold, preservando a proporção das classes. |
| `make_repeated_folds()` | Cria folds estratificados repetidos e reprodutíveis. |
| `roc_auc()` | Calcula ROC-AUC por postos, com tratamento de empates. |
| `pr_auc()` | Calcula Average Precision/PR-AUC; agrupa probabilidades empatadas para resultado determinístico. |
| `binary_metrics()` | Calcula todas as métricas binárias e os valores TP, TN, FP e FN. |
| `mean_without_na()` e `sd_without_na()` | Calculam média e desvio-padrão sem eliminar silenciosamente resultados totalmente indefinidos. |
| `candidate_thresholds()` | Gera todos os limiares de decisão relevantes para um vetor de probabilidades. |
| `select_threshold()` | Escolhe o limiar por MCC, F1 e proximidade de 0,5. |
| `metrics_by_resample()` | Calcula as métricas separadamente para cada reamostragem. |
| `summarize_metrics()` | Produz a tabela de média ± desvio-padrão das métricas comuns. |
| `summarize_dietterich_5x2cv()` | Calcula a estatística t, graus de liberdade e p-valor do teste 5x2cv. |
| `summarize_alpaydin_5x2cv()` | Calcula o F-test combinado 5x2cv de Alpaydın como evidência complementar. |

Essas funções deverão ser usadas pelos scripts de SVM, Random Forest e Decision Tree para que todos os modelos sejam avaliados pela mesma regra.

## Funções específicas do Naive Bayes (`naive_bayes.R`)

| Função | Finalidade |
|---|---|
| `ensure_package()` | Verifica se uma dependência existe e informa o comando de instalação manual quando necessário. |
| `report_execution_time()` | Mede e imprime o tempo total da execução. |
| `fit_naive_bayes()` | Ajusta uma configuração Gaussiana ou KDE do Naive Bayes. |
| `predict_disease_probability()` | Obtém a probabilidade da classe `doenca`. |
| `evaluate_config_cv()` | Gera predições out-of-fold para uma configuração em uma lista de folds. |
| `tune_naive_bayes()` | Avalia configurações internas, seleciona o limiar e escolhe a melhor pelo MCC. |
| `config_description()` | Formata a descrição legível da configuração selecionada. |
| `nested_repeated_cv()` | Executa a avaliação externa aninhada e registra a configuração escolhida em cada fold. |
| `dietterich_5x2cv()` | Ajusta e compara as famílias Gaussiana e KDE dentro do protocolo 5x2cv. |

## Resultados obtidos

Os valores abaixo foram produzidos pelo pipeline reprodutível, com a semente `20260804`, no subconjunto Cleveland de 303 pacientes. São médias ± desvios-padrão nos 50 folds externos; não representam uma única divisão fixa treino/teste.

| Métrica | Resultado |
|---|---:|
| Acurácia | 0,8224 ± 0,0641 |
| Sensibilidade | 0,7649 ± 0,1043 |
| Especificidade | 0,8707 ± 0,0845 |
| Precisão | 0,8413 ± 0,0878 |
| F1 | 0,7962 ± 0,0763 |
| MCC | 0,6473 ± 0,1299 |
| ROC-AUC | 0,9017 ± 0,0587 |
| PR-AUC | 0,8966 ± 0,0668 |

A configuração escolhida no ajuste final com todos os dados foi:

```text
Naive Bayes com KDE; laplace = 0.5; adjust = 1.5; limiar = 0.469
```

### Matriz de confusão agregada

| Real \ Predito | Sem doença | Doença |
|---|---:|---:|
| Sem doença | 714 | 106 |
| Doença | 163 | 532 |

Essa tabela contém 1.515 predições agregadas (303 pacientes × 5 repetições) e é apenas descritiva; não equivale à matriz de confusão de uma única divisão treino/teste.

### Comparação estatística entre KDE e Gaussiano

| Teste | Estatística | Graus de liberdade | p-valor | Conclusão (α = 0,05) |
|---|---:|---|---:|---|
| Dietterich 5x2cv | `t = -0,4870` | 5 | 0,64683 | Não há evidência de diferença significativa em F1. |
| Alpaydın 5x2cv (complementar) | `F = 1,1445` | 10 e 5 | 0,46832 | Não há evidência complementar de diferença significativa em F1. |

A diferença média de F1 entre KDE e Gaussiano foi `-0,0140`. A configuração KDE acima é usada como modelo final porque venceu o ajuste final por MCC; isso não equivale a afirmar superioridade estatística sobre o Gaussiano.

O tempo total registrado nesta execução foi **71,34 segundos**. Esse valor pode variar conforme computador, versão do R, rede e cache do download da UCI.

## Como executar

No diretório do projeto, execute:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\naive_bayes.R
```

O terminal exibirá as etapas da análise, as métricas, a matriz de confusão agregada, a seleção final, o resultado do 5x2cv e o tempo total. Ao final, o arquivo em `models/modelo_naive_bayes_heart_disease.rds` é atualizado; tabelas detalhadas são salvas em `results/`.

## Próximos modelos

Para garantir comparação justa, os scripts de SVM, Random Forest e Decision Tree devem:

1. usar o mesmo subconjunto Cleveland e a mesma definição da classe positiva;
2. importar `common_evaluation.R`;
3. usar a mesma estrutura de validação cruzada aninhada e as mesmas sementes;
4. escolher hiperparâmetros e limiar somente dentro dos dados de treino de cada fold;
5. reportar as métricas da avaliação externa com média ± desvio-padrão;
6. comparar modelos com procedimento estatístico apropriado, e não com t-test pareado comum entre folds.
