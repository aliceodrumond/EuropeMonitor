# Europe Client Monitor

Site para clientes com três superfícies iniciais:

- Monitor de Atividade
- Monitor de Inflação
- ECB speakers

O site lê arquivos estáticos em `public/data/`. O R é responsável por atualizar
esses arquivos diariamente.

## Fluxo Diário

No diretório do projeto:

```powershell
& 'C:\Program Files\R\R-4.3.1\bin\Rscript.exe' 'R\run_daily_update.R'
```

Esse comando gera:

- `public/data/activity_series.csv`
- `public/data/inflation_series.csv`
- `public/data/ecb_speakers.csv`
- `public/data/metadata.json`

Também grava cópias tratadas em `data/processed/`.

## Estrutura

- `app/`: site React/vinext.
- `R/`: pipeline diário.
- `config/series_catalog.csv`: catálogo de séries e fontes planejadas.
- `data/raw/`: espaço para dados baixados sem tratamento.
- `data/processed/`: bases tratadas.
- `public/data/`: arquivos consumidos pelo site.

## Adicionar Séries e Gráficos

1. Inclua a série no `config/series_catalog.csv`.
2. Adicione a coleta/tratamento no script R do domínio.
3. Garanta que o CSV final tenha as colunas:

```text
date,chart_id,series_id,series_name,country,value,axis,unit,source
```

4. Se for um gráfico novo, registre o `chart_id` em `app/page.tsx`.

## Rodar o Site

O projeto usa o starter Sites/vinext e espera Node.js `>=22.13.0`.

```powershell
npm install
npm run dev
npm run build
```

Nesta sessão, `node`, `npm` e `git` não estavam disponíveis no PATH, então a
validação completa do site e a publicação ainda dependem de habilitar esses
executáveis no ambiente.
