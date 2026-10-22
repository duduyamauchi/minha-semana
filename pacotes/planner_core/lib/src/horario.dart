/// Horário e duração — Dart puro, sem dependência de Flutter ou `intl`.
///
/// O planejador guarda o horário como texto `HH:mm` (formato do HTML original)
/// e a duração como minutos inteiros. Manter os dois separados é o que permite
/// editar a duração sem reinterpretar texto livre: antes, "3h30" morava dentro
/// do campo de observações.
library;

/// Utilitários de horário no formato `HH:mm`.
abstract final class Horario {
  static const _minutosPorDia = 24 * 60;

  /// Lê `HH:mm` (aceita `H:mm`) e a forma só com dígitos (`745`, `0745`).
  ///
  /// A segunda forma existe porque o campo do editor só deixa digitar números e
  /// dois-pontos: quem digita "745" quer 07:45, e recusar isso seria uma
  /// validação que atrapalha em vez de proteger.
  static int? minutos(String? texto) {
    if (texto == null) return null;
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;

    if (!limpo.contains(':')) {
      if (!RegExp(r'^\d{3,4}$').hasMatch(limpo)) return null;
      final numero = limpo.padLeft(4, '0');
      return _validar(
        int.parse(numero.substring(0, 2)),
        int.parse(numero.substring(2)),
      );
    }

    final partes = limpo.split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    return _validar(h, m);
  }

  static int? _validar(int? h, int? m) {
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// Formata minutos desde a meia-noite como `HH:mm`, dando a volta no dia.
  static String formatar(int minutosDoDia) {
    final normalizado = minutosDoDia % _minutosPorDia;
    final positivo = normalizado < 0 ? normalizado + _minutosPorDia : normalizado;
    final h = positivo ~/ 60;
    final m = positivo % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Normaliza texto livre para `HH:mm`, ou `null` se inválido.
  static String? normalizar(String? texto) {
    final valor = minutos(texto);
    return valor == null ? null : formatar(valor);
  }

  /// Soma uma duração a um horário, sem estourar o dia.
  static String somar(String horario, int? duracaoMinutos) {
    final inicio = minutos(horario);
    if (inicio == null || duracaoMinutos == null) return horario;
    return formatar(inicio + duracaoMinutos);
  }

  /// Verdadeiro quando [texto] é um horário válido.
  static bool valido(String? texto) => minutos(texto) != null;
}
