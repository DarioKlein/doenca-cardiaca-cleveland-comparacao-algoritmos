# Predição de Doença Cardíaca — UCI Cleveland

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `src/` | Scripts R dos modelos e módulos compartilhados. |
| `data/` | Cache validado da base Cleveland da UCI. |
| `models/` | Modelos finais salvos em formato `.rds`. |
| `results/` | Resultados por fold, rankings de hiperparâmetros, matrizes de confusão e logs. |
| `docs/` | Documentação metodológica dos algoritmos. |

## Execução

No diretório raiz do projeto:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\naive_bayes.r
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' src\decision_trees.r
```
