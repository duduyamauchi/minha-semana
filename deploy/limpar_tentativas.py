"""Limpa o contador de tentativas de login.

Os testes de ponta a ponta exercitam senha errada de propósito; sem limpar, uma
segunda execução encontraria o bloqueio de 15 minutos em vez da mensagem de
credencial inválida. Este script zera as falhas sem tocar em mais nada.

Uso:
    python deploy/limpar_tentativas.py

Lê a connection string de `~/.segredos/minha-semana/neon_uri_direto.txt` ou de
`DATABASE_URL`. Se nenhuma existir, sai com 0 e avisa — o teste continua, apenas
pode encontrar o bloqueio.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> int:
    caminho = Path(os.path.expanduser("~")) / ".segredos" / "minha-semana" / "neon_uri_direto.txt"
    uri = os.environ.get("DATABASE_URL")
    if not uri and caminho.exists():
        uri = caminho.read_text(encoding="utf-8").strip()
    if not uri:
        print("sem connection string: contador de tentativas não foi limpo")
        return 0

    try:
        import psycopg
    except ImportError:
        print("psycopg ausente: contador de tentativas não foi limpo")
        return 0

    try:
        with psycopg.connect(uri, connect_timeout=20) as conn, conn.cursor() as cur:
            cur.execute("delete from tentativas_login where not sucesso")
            removidas = cur.rowcount
            conn.commit()
        print(f"tentativas de login falhas removidas: {removidas}")
    except Exception as erro:  # noqa: BLE001 — limpeza best-effort
        print(f"não foi possível limpar tentativas: {erro}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
