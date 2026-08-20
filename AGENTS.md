# Contexto do projeto — Heart Disease UCI

## Objetivo

Projeto de pesquisa para prever presença de doença cardíaca a partir do subconjunto **Cleveland** da base UCI Heart Disease (dataset 45). A classe original `num` é binarizada:

- `sem_doenca`: `num = 0`;
- `doenca`: `num > 0`.

O usuário quer comparar quatro algoritmos sob **o mesmo protocolo metodológico**:

1. Naive Bayes;
2. Árvore de Decisão;
3. Random Forest;
4. SVM.

O usuário prefere explicações em português, nomes semânticos em português para as variáveis e análise crítica de sugestões: não implementar uma “melhoria” apenas porque ela foi sugerida; primeiro verificar se é correta, necessária e adequada ao escopo.

## Estrutura atual

```text
src/
  common_evaluation.r       # Métricas, folds, limiar, 5x2cv e CSVs compartilhados
  heart_disease_data.r      # Importação, cache, validação e preparo da base
  naive_bayes.r             # Pipeline completo de Naive Bayes
  decision_trees.r          # Pipeline completo de Árvore de Decisão
  random_forest.r           # Pipeline completo de Random Forest
  svm.r                     # Pipeline completo de SVM
data/
  processed.cleveland.data  # Cache validado da base UCI (303 x 14)
models/
  modelo_naive_bayes_heart_disease.rds
  modelo_decision_tree_heart_disease.rds
results/
  *_resultados_folds.csv
  *_ranking_hiperparametros.csv
  *_matriz_confusao_agregada.csv
  saida_execucao.log
docs/
  DOCUMENTACAO_NAIVE_BAYES.md
README.md
```

Execute os scripts a partir da raiz:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\naive_bayes.r
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\decision_trees.r
```

Não mover scripts novamente sem atualizar os caminhos em `source(file.path("src", ...))` e os caminhos de saída (`data/`, `models/`, `results/`).

## Base e variáveis

O projeto usa intencionalmente `processed.cleveland.data`, não um carregador genérico do `ucimlrepo`, porque isso fixa o subconjunto Cleveland com 303 pacientes. `heart_disease_data.r` tenta usar o cache; se necessário, baixa da UCI, valida que o conteúdo é 303 x 14 e grava o cache.

As variáveis recebem nomes em português:

`idade`, `sexo`, `tipo_dor_toracica`, `pressao_arterial_repouso`, `colesterol_serico`, `glicemia_jejum`, `eletrocardiograma_repouso`, `frequencia_cardiaca_maxima`, `angina_induzida_exercicio`, `depressao_segmento_st`, `inclinacao_segmento_st`, `vasos_principais`, `talassemia`.

A variável-alvo é `classe_doenca`. Há 6 valores ausentes: 4 em `vasos_principais` e 2 em `talassemia`.

- Naive Bayes (`naivebayes`) trata os NAs nativamente.
- Árvore (`rpart`) usa surrogate splits.
- Para SVM e Random Forest, criar imputação **dentro de cada fold de treino**, aplicando-a ao teste sem recalcular estatísticas no teste. SVM também precisa de escala calculada no treino.

## Protocolo obrigatório de avaliação

Manter o mesmo protocolo nos quatro algoritmos:

- Classe positiva: `doenca`.
- Semente-base: `20260804L`.
- Avaliação principal: validação cruzada estratificada aninhada externa **10-fold repetida 5 vezes** (50 folds externos).
- Ajuste interno: CV estratificada **5-fold repetida 3 vezes**.
- Hiperparâmetros e limiar são escolhidos apenas no treino de cada fold externo.
- Critério de seleção: MCC; desempates por F1, ROC-AUC e configuração determinística/parcimoniosa quando aplicável.
- Resultados principais: média ± DP dos 50 folds externos.

O DP é **variabilidade entre folds sobrepostos**, não erro-padrão de amostras independentes. Não construir intervalos de confiança diretamente a partir desses 50 valores. A matriz de confusão agregada contém 1.515 predições (303 pacientes x 5 repetições), logo é descritiva, não uma matriz de um único experimento.

## Métricas comuns

Implementadas em `src/common_evaluation.r`:

- Accuracy;
- Sensitivity (recall da classe `doenca`);
- Specificity;
- Precision;
- F1;
- MCC (métrica primária de seleção);
- ROC-AUC;
- PR-AUC / Average Precision;
- Balanced Accuracy;
- NPV.

`select_threshold()` testa todos os cortes relevantes nas probabilidades out-of-fold e escolhe por MCC, F1 e proximidade de 0,5. Não substituir por uma grade arbitrária de limiares.

## Comparação estatística

`run_paired_5x2cv()` é a função compartilhada que compara duas famílias/configurações do mesmo algoritmo. Ela:

- gera as cinco divisões 50/50 com `withr::with_seed()`;
- ajusta cada família apenas na metade de treino;
- recalibra hiperparâmetros e limiar dentro dessa metade;
- reporta Dietterich 5x2cv e F-test combinado de Alpaydın;
- calcula os testes para MCC e F1.

O teste de Dietterich foi originalmente derivado para taxa de erro; o uso com F1/MCC deve ser descrito como extensão prática. Não usar t-test pareado comum entre os folds repetidos.

## Naive Bayes

Arquivo: `src/naive_bayes.r`.

Pacotes: `naivebayes`, `withr`.

Famílias comparadas:

- Gaussiano;
- KDE.

Grade histórica: `laplace = 0.5, 1, 2`; no KDE, `adjust = 0.5, 1, 1.5`.

Resultado da última execução completa antes das mudanças mais recentes:

| Métrica | Média ± DP |
|---|---:|
| Accuracy | 0,8224 ± 0,0641 |
| Sensitivity | 0,7649 ± 0,1043 |
| Specificity | 0,8707 ± 0,0845 |
| F1 | 0,7962 ± 0,0763 |
| MCC | 0,6473 ± 0,1299 |
| ROC-AUC | 0,9017 ± 0,0587 |
| PR-AUC | 0,8966 ± 0,0668 |

Configuração final anterior: KDE, `laplace = 0.5`, `adjust = 1.5`, limiar `0.469`.

Comparação anterior KDE vs. Gaussiano em F1: Dietterich `p = 0,64683`; Alpaydın `p = 0,46832`. Não houve evidência de diferença significativa.

## Árvore de Decisão

Arquivo: `src/decision_trees.r`.

Pacotes: `rpart`, `withr`.

Famílias comparadas:

- critério de Gini;
- ganho de informação (`information`).

Hiperparâmetros: `cp`, `minsplit`, `maxdepth`; `xval = 0` é intencional, porque a validação já é feita externamente pelo pipeline. O `minbucket` permanece no padrão do `rpart` (`round(minsplit / 3)`) para evitar uma grade excessivamente grande.

Resultado da última execução completa **antes** da ampliação da grade de `cp`:

| Métrica | Média ± DP |
|---|---:|
| Accuracy | 0,7855 ± 0,0694 |
| Sensitivity | 0,7091 ± 0,1190 |
| Specificity | 0,8499 ± 0,0943 |
| F1 | 0,7494 ± 0,0842 |
| MCC | 0,5750 ± 0,1423 |
| ROC-AUC | 0,8215 ± 0,0642 |
| PR-AUC | 0,7876 ± 0,0845 |

Configuração final anterior: Gini, `cp = 0.001`, `minsplit = 20`, profundidade máxima `3`, limiar `0.688`.

Comparação anterior Gini vs. informação em F1: Dietterich `p = 0,50911`; Alpaydın `p = 0,79692`. Não houve evidência de diferença significativa.

## Estado importante: reexecução necessária

Após as execuções acima, foram implementadas melhorias que exigem reexecutar os dois scripts antes de tratar modelos/RDS/CSVs como resultados finais:

- métricas novas: Balanced Accuracy e NPV;
- 5x2cv compartilhado, agora reportando MCC e F1;
- schema padronizado dos RDS;
- CSVs salvos em `results/`;
- cache validado da base;
- Árvore: grade de `cp` ampliada para `0.001, 0.005, 0.01, 0.02, 0.05` e desempate por parcimônia;
- tempo de execução formatado de modo mais simples.

Portanto, os números acima são referências históricas, não resultados finais após a última refatoração. Ao reexecutar, atualizar `docs/DOCUMENTACAO_NAIVE_BAYES.md` e criar documentação equivalente para a árvore.

## Regra para resultados oficiais

Os resultados oficiais que serão incluídos nos Markdown de documentação em `docs/` devem vir **somente das execuções realizadas pelo usuário no computador dele**. O fluxo combinado é:

1. o usuário executa o script na própria máquina;
2. envia a saída completa do terminal ao assistente;
3. o assistente registra esses valores no Markdown correspondente.

Não inventar, estimar, substituir ou publicar no Markdown resultados de uma execução feita em outro ambiente. Resultados locais anteriores podem ser mantidos apenas como referência histórica, claramente identificados como tal.

## Próximos passos recomendados

1. Reexecutar Naive Bayes e Árvore de Decisão com a versão atual.
2. Registrar os novos resultados e atualizar documentação.
3. Executar o SVM e registrar os resultados oficiais enviados pelo usuário.
4. Depois dos quatro modelos, criar `src/compare_models.r` para comparação pareada, baseline da classe majoritária e correção de múltiplas comparações (por exemplo, Holm). Não antecipar esse script antes de todos os modelos existirem.
5. Implementar importância por permutação dentro dos folds externos para comparação justa entre todos os algoritmos; não usar apenas importância interna de Gini da árvore/Random Forest como ranking geral.

## Decisões que não devem ser alteradas sem justificativa

- Não trocar CV aninhada por uma divisão única 70/30.
- Não remover os seis pacientes com NA, nem imputar usando a base inteira antes dos folds.
- Não instalar pacotes automaticamente via `install.packages()` dentro dos scripts.
- Não criar IC a partir dos 50 folds como se fossem independentes.
- Não usar um t-test pareado comum sobre folds repetidos.
- Não adicionar um limiar clínico fixo, como sensibilidade >= 0,90, sem uma exigência clínica explícita do estudo.
- Não paralelizar por padrão: priorizar reprodutibilidade e clareza; avaliar apenas se o tempo se tornar impeditivo.
- Exceção acionada para Random Forest: a execução sequencial levou cerca de 42 minutos. O tuning de configurações usa `doParallel`/`foreach`, enquanto cada `ranger` permanece com uma thread e sementes determinísticas por tarefa. Essa autorização é específica do Random Forest; o SVM deve ser medido e justificado separadamente antes de receber paralelismo.

## Convenções de implementação

- Usar `apply_patch` para alterações em arquivos.
- Manter comentários e mensagens do terminal em português sem acentos quando o script já segue esse padrão.
- Nunca sobrescrever ou apagar resultados existentes sem autorização explícita.
- Não alterar algoritmos existentes, hiperparâmetros, pré-processamento, métricas ou protocolo de avaliação sem solicitação explícita do usuário.
- Não criar Random Forest, SVM, comparadores, gráficos ou qualquer novo algoritmo sem solicitação explícita do usuário.
- Toda mudança que altere grade de hiperparâmetros, pré-processamento, métrica ou seed torna os resultados anteriores históricos e requer nova execução/documentação.
