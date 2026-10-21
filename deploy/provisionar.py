"""Provisiona o banco do Minha Semana.

Aplica o schema e cria (ou atualiza) o quadro, o vínculo de acesso e a
credencial da usuária. A senha é lida de um arquivo local ou gerada na hora —
nunca fica em SQL versionado.

Uso:
    python deploy/provisionar.py --senha-arquivo ~/.segredos/minha-semana/senha.txt
    python deploy/provisionar.py --gerar-senha
    python deploy/provisionar.py --apenas-schema

Pré-requisitos: `psycopg` instalado e a connection string em
`~/.segredos/minha-semana/neon_uri_direto.txt` (ou em `DATABASE_URL`).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import os
import secrets
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SCHEMA = RAIZ / "deploy" / "schema.sql"

# O runtime da Cloudflare recusa PBKDF2 acima de 100 mil iterações; este é o
# teto da plataforma e o mesmo valor que o Worker usa para conferir.
ITERACOES = 100_000
QUADRO_PADRAO = "00000000-0000-0000-0000-000000000001"


def caminho_segredo(nome: str) -> Path:
    return Path(os.path.expanduser("~")) / ".segredos" / "minha-semana" / nome


def ler_arquivo(caminho: Path) -> str:
    return caminho.read_text(encoding="utf-8").strip()


def conectar():
    try:
        import psycopg
    except ImportError:
        sys.exit("psycopg ausente: pip install 'psycopg[binary]'")

    uri = os.environ.get("DATABASE_URL")
    if not uri:
        arquivo = caminho_segredo("neon_uri_direto.txt")
        if not arquivo.exists():
            sys.exit(f"Connection string ausente em {arquivo} e DATABASE_URL não definida.")
        uri = ler_arquivo(arquivo)
    return psycopg.connect(uri, connect_timeout=30)


def derivar_hash(senha: str, salt: bytes, pepper: str) -> str:
    """PBKDF2-HMAC-SHA256(HMAC(senha, pepper), salt), como no Worker."""
    material = hmac.new(pepper.encode(), senha.encode(), hashlib.sha256).digest()
    bits = hashlib.pbkdf2_hmac("sha256", material, salt, ITERACOES, dklen=32)
    return base64.b64encode(bits).decode()


def principal() -> int:
    parser = argparse.ArgumentParser(description="Provisiona o banco do Minha Semana.")
    parser.add_argument("--apenas-schema", action="store_true", help="só aplica o schema")
    parser.add_argument("--usuario", default="sarah")
    parser.add_argument("--nome-quadro", default="Minha Semana")
    parser.add_argument("--quadro-id", default=QUADRO_PADRAO)
    parser.add_argument("--senha-arquivo", type=Path)
    parser.add_argument("--gerar-senha", action="store_true")
    args = parser.parse_args()

    with conectar() as conn, conn.cursor() as cur:
        print("Aplicando schema...")
        cur.execute(SCHEMA.read_text(encoding="utf-8"))
        conn.commit()
        print("Schema aplicado.")

        if args.apenas_schema:
            return 0

        cur.execute(
            """
            insert into quadros (id, nome) values (%s, %s)
            on conflict (id) do update set nome = excluded.nome
            """,
            (args.quadro_id, args.nome_quadro),
        )
        cur.execute(
            """
            insert into usuario_quadros (usuario_id, quadro_id, papel)
            values (%s, %s, 'proprietario')
            on conflict (usuario_id, quadro_id) do update set papel = 'proprietario'
            """,
            (args.usuario, args.quadro_id),
        )

        # Ordem: arquivo explícito, variável de ambiente, arquivo padrão; sem
        # nada disso, gera uma senha e grava no arquivo padrão.
        arquivo_senha = args.senha_arquivo
        if arquivo_senha:
            senha = ler_arquivo(arquivo_senha)
        elif os.environ.get("MINHA_SEMANA_SENHA"):
            senha = os.environ["MINHA_SEMANA_SENHA"]
        elif caminho_segredo("senha.txt").exists() and not args.gerar_senha:
            senha = ler_arquivo(caminho_segredo("senha.txt"))
        else:
            senha = secrets.token_urlsafe(12)
            destino = caminho_segredo("senha.txt")
            destino.parent.mkdir(parents=True, exist_ok=True)
            destino.write_text(senha, encoding="utf-8")
            print(f"Senha gerada e gravada em {destino}")

        if senha is not None:
            pepper_arquivo = caminho_segredo("pepper.txt")
            if not pepper_arquivo.exists():
                sys.exit(f"Pepper ausente em {pepper_arquivo}. Gere com: python -c \"import secrets;print(secrets.token_hex(32))\"")
            pepper = ler_arquivo(pepper_arquivo)
            salt = secrets.token_bytes(16)
            hash_b64 = derivar_hash(senha, salt, pepper)
            cur.execute(
                """
                insert into credenciais (usuario_id, hash, salt, iteracoes)
                values (%s, %s, %s, %s)
                on conflict (usuario_id) do update
                  set hash = excluded.hash, salt = excluded.salt,
                      iteracoes = excluded.iteracoes, trocado_em = now()
                """,
                (args.usuario, hash_b64, base64.b64encode(salt).decode(), ITERACOES),
            )
            print(f"Credencial de '{args.usuario}' gravada (PBKDF2, {ITERACOES} iterações).")

        conn.commit()

        cur.execute("select count(*) from atividades_concluidas")
        marcadas = cur.fetchone()[0]
        cur.execute("select count(*) from comodos")
        comodos = cur.fetchone()[0]
        cur.execute("select usuario_id, papel from usuario_quadros")
        vinculos = cur.fetchall()

    print(f"Estado atual: {marcadas} atividades marcadas, {comodos} cômodos, vínculos: {vinculos}")
    return 0


if __name__ == "__main__":
    raise SystemExit(principal())
