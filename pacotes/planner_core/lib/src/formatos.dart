import 'dart:convert';

/// Formatação de números e datas em português do Brasil.
///
/// Vive no núcleo (Dart puro) para que app, testes e um eventual backend usem a
/// mesma regra. Nenhum `intl` aqui: as necessidades são poucas e explícitas.
abstract final class Formatos {
  /// `1234` → `1.234`; usado para contadores grandes.
  static String inteiro(num valor) {
    final texto = valor.round().abs().toString();
    final partes = <String>[];
    for (var i = texto.length; i > 0; i -= 3) {
      partes.insert(0, texto.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valor < 0 ? '-' : ''}${partes.join('.')}';
  }

  /// Converte segundos em texto curto: `1 h 05 min`, `12 min`, `40 s`.
  static String duracao(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    final horas = d.inHours;
    final minutos = d.inMinutes.remainder(60);
    if (horas == 0) return '$minutos min';
    return minutos == 0 ? '$horas h' : '$horas h ${minutos.toString().padLeft(2, '0')} min';
  }

  /// `2026-10-21` → `21/10`.
  static String diaMes(String iso) {
    final data = DateTime.tryParse(iso);
    if (data == null) return iso;
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
  }

  /// Nome do dia da semana em português (segunda = 0).
  static String diaDaSemana(int indice) => const [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ][indice % 7];

  /// Data por extenso curta: `21 de outubro`.
  static String dataExtensa(DateTime data) => '${data.day} de ${_meses[data.month - 1]}';

  static const _meses = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  /// Série JSON legível, usada para exportar/importar backup.
  static String jsonBonito(Object? valor) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(valor);
  }
}
