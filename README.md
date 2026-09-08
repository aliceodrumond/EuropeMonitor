# Macro Europe Monitor

Site para clientes com tres superficies iniciais:

- Monitor de Atividade
- Monitor de Inflacao
- ECB speakers

O site le arquivos estaticos em `public/data/`. O R e responsavel por atualizar
esses arquivos diariamente.

## Fluxo Diario

No diretorio do projeto:

```powershell
& 'C:\Program Files\R\R-4.3.1\bin\Rscript.exe' 'R\run_daily_update.R'
```

Esse comando gera:

- `public/data/activity_series.csv`
- `public/data/inflation_series.csv`
- `public/data/ecb_speakers.csv`
- `public/data/metadata.json`

Tambem grava copias tratadas em `data/processed/`.

Esse unico comando atualiza as tres abas:

- ECB Speakers: `R/fetch_ecb_speakers.R`
- Activity Monitor: `R/fetch_activity.R`
- Inflation Monitor: `R/fetch_inflation.R`

Os CSVs de series incluem `source` e `source_url`, preenchidos a partir de
`config/series_catalog.csv`. Ao adicionar ou trocar uma fonte, atualize o
catalogo primeiro; o pipeline R aplica esses metadados automaticamente aos CSVs
publicos usados pelos graficos.

A aba ECB Speakers e atualizada por `R/fetch_ecb_speakers.R` a partir de
`https://www.econostream-media.com/news/topic/centralbank`. O script extrai
headline, resumo, data e link dos artigos, classifica a fala como hawkish,
dovish ou neutral por palavras-chave e preserva um fallback local caso a pagina
esteja temporariamente indisponivel.

## Estrutura

- `app/`: site React/vinext.
- `R/`: pipeline diario.
- `config/series_catalog.csv`: catalogo de series, fontes e URLs oficiais.
- `data/raw/`: espaco para dados baixados sem tratamento.
- `data/processed/`: bases tratadas.
- `public/data/`: arquivos consumidos pelo site.

## Adicionar Series e Graficos

1. Inclua a serie no `config/series_catalog.csv`.
2. Adicione a coleta/tratamento no script R do dominio.
3. Garanta que o CSV final tenha as colunas:

```text
date,chart_id,series_id,series_name,country,value,axis,unit,source,source_url
```

4. Se for um grafico novo, registre o `chart_id` em `app/page.tsx`.

Observacao: as series de PMI da SP Global estao linkadas a fonte oficial, mas
exigem feed licenciado ou importacao manual de CSV para substituir os valores
mockados por dados reais.

O Flash PMI da area do euro pode ser incluído em
`data/raw/flash_pmi_euro_area.csv`, com as colunas:

```text
date,composite,manufacturing,services
```

Os valores devem vir do release mensal oficial HCOB / S&P Global. O pipeline
adiciona as tres series "Europe Flash" aos respectivos graficos de PMI.

## Rodar o Site

O projeto usa o starter Sites/vinext e espera Node.js `>=22.13.0`.

```powershell
npm install
npm run dev
npm run build
```

Se `node` e `npm` nao estiverem no PATH, use o caminho instalado diretamente:

```powershell
$env:Path = 'C:\Program Files\nodejs;' + $env:Path
& 'C:\Program Files\nodejs\npm.cmd' run build
```

## Monitoramento de Acesso

O site suporta Cloudflare Web Analytics sem contar acessos internos. Para ativar:

1. Crie um site em Cloudflare Web Analytics para `legacy-europe-monitor.pages.dev`.
2. Configure o token no ambiente de build como `CF_WEB_ANALYTICS_TOKEN`.
3. Rebuild/deploy do site.

Para excluir seus proprios acessos, abra uma vez em cada computador/celular:

```text
https://legacy-europe-monitor.pages.dev/?internal=1
```

Isso grava `legacyMonitorInternal=1` no `localStorage` daquele navegador e o
script do Cloudflare Web Analytics deixa de carregar naquele dispositivo. Para
voltar a contar um navegador como externo, abra:

```text
https://legacy-europe-monitor.pages.dev/?external=1
```
