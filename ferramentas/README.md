# Ferramentas locais

| Arquivo | Para quê |
| --- | --- |
| `servir.py` | Compila e serve o build web em `localhost:8080`, com fallback de SPA |

```bash
python ferramentas/servir.py                 # compila e serve
python ferramentas/servir.py --sem-build     # só serve
python ferramentas/servir.py --porta 9000
```

Contra a API publicada:

```bash
cd planner
flutter build web --release --base-href=/ --no-web-resources-cdn \
  --dart-define=PLANNER_FONTE=http --dart-define=PLANNER_API=/api
```

O proxy `/api` só existe no projeto Pages; localmente, para falar com a API,
compile com `PLANNER_API=https://minhasemana.pages.dev/api` (ou rode
`wrangler pages dev` na pasta `planner` para ter a Function local).
O cookie é `SameSite=Strict`, então o login local funciona mas a sessão não
persiste entre origens diferentes — use o domínio publicado para testar login.
