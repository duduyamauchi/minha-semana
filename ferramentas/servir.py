"""Servidor local do Minha Semana.

Serve `planner/build/web` em http://localhost:8080, com *fallback* para
`index.html` — sem isso, `/dia/qua` (rota sem `#`) devolve 404 e o app não abre
pelo link compartilhado.

Uso:
    python ferramentas/servir.py                 # porta 8080
    python ferramentas/servir.py --porta 9000
    python ferramentas/servir.py --sem-build     # já existe build/web
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import socketserver
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
WEB = RAIZ / "planner" / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    """Arquivos estáticos com fallback de SPA e cabeçalhos de segurança."""

    protocol_version = "HTTP/1.1"

    def end_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self) -> None:  # noqa: N802 (API do http.server)
        caminho = self.translate_path(self.path)
        if not os.path.exists(caminho) or os.path.isdir(caminho):
            if not Path(caminho).suffix:
                self.path = "/index.html"
        super().do_GET()

    def log_message(self, formato: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), formato % args))


def principal() -> int:
    parser = argparse.ArgumentParser(description="Serve o build web do Minha Semana.")
    parser.add_argument("--porta", type=int, default=8080)
    parser.add_argument("--sem-build", action="store_true", help="não recompilar antes de servir")
    args = parser.parse_args()

    if not args.sem_build:
        print("Compilando (flutter build web)...")
        resultado = subprocess.run(
            ["flutter", "build", "web", "--release", "--base-href=/", "--no-web-resources-cdn"],
            cwd=RAIZ / "planner",
        )
        if resultado.returncode != 0:
            return resultado.returncode

    if not (WEB / "index.html").exists():
        print(f"Build ausente em {WEB}. Rode sem --sem-build.", file=sys.stderr)
        return 1

    handler = functools.partial(Handler, directory=str(WEB))
    # Concorrente: o navegador abre várias conexões ao mesmo tempo (fonte,
    # ícone, CanvasKit). Num servidor de thread única o build "não carrega".
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", args.porta), handler) as servidor:
        print(f"Minha Semana em http://localhost:{args.porta} (Ctrl+C para parar)")
        try:
            servidor.serve_forever()
        except KeyboardInterrupt:
            print("\nEncerrado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(principal())
