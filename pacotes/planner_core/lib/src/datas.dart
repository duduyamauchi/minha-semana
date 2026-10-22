/// Datas do calendário — Dart puro, sem `intl` e sem Flutter.
///
/// O planejador trabalha com duas noções de tempo que não se confundem:
///
/// * o **dia da semana** (`seg`…`dom`), que é a chave do template;
/// * a **data** (`2026-10-21`), que é a chave das marcações.
///
/// A mesma rotina de quarta vale para todas as quartas; o que muda de uma
/// semana para outra é o que foi feito em cada data. Por isso as marcações são
/// por data e o plano continua semanal.
library;

/// Uma data sem hora, no fuso local.
///
/// Guardar `DateTime` com hora faria duas datas "iguais" diferirem por
/// milissegundos e quebraria a chave do mapa de marcações.
class Datas {
  const Datas._();

  /// Data de hoje, sem hora.
  static DateTime hoje([DateTime? agora]) {
    final d = agora ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  /// Normaliza qualquer `DateTime` para o dia, sem hora.
  static DateTime dia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `2026-10-21`.
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Lê `yyyy-MM-dd`; devolve `null` quando o texto não é uma data válida.
  static DateTime? deIso(String? texto) {
    if (texto == null) return null;
    final partes = texto.trim().split('-');
    if (partes.length != 3) return null;
    final ano = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final dia = int.tryParse(partes[2]);
    if (ano == null || mes == null || dia == null) return null;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    final data = DateTime(ano, mes, dia);
    // `DateTime` normaliza 31/02 para 03/03; recusar mantém a chave fiel ao
    // texto que veio da URL.
    if (data.year != ano || data.month != mes || data.day != dia) return null;
    return data;
  }

  /// Segunda-feira da semana que contém [d].
  static DateTime segundaDe(DateTime d) {
    final alvo = dia(d);
    return alvo.subtract(Duration(days: alvo.weekday - DateTime.monday));
  }

  /// As sete datas da semana que contém [d], de segunda a domingo.
  static List<DateTime> semanaDe(DateTime d) {
    final inicio = segundaDe(d);
    return [for (var i = 0; i < 7; i++) inicio.add(Duration(days: i))];
  }

  /// Índice do dia na semana (segunda = 0).
  static int indiceNaSemana(DateTime d) => (dia(d).weekday - DateTime.monday) % 7;

  /// Soma dias preservando o dia (sem hora).
  static DateTime somarDias(DateTime d, int dias) => dia(d).add(Duration(days: dias));

  /// Mesmas data e hora zero.
  static bool mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Primeiro dia do mês de [d].
  static DateTime inicioDoMes(DateTime d) => DateTime(d.year, d.month, 1);

  /// Primeiro dia do mês seguinte.
  static DateTime mesSeguinte(DateTime d) => DateTime(d.year, d.month + 1, 1);

  /// Primeiro dia do mês anterior.
  static DateTime mesAnterior(DateTime d) => DateTime(d.year, d.month - 1, 1);

  /// Início da semana (segunda) que contém o dia 1º do mês de [d].
  static DateTime primeiraSegundaDoMes(DateTime d) => segundaDe(inicioDoMes(d));

  /// Abreviações de mês.
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

  /// `outubro de 2026`.
  static String mesExtenso(DateTime d) => '${_meses[d.month - 1]} de ${d.year}';

  /// `21/10`.
  static String diaMes(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// `21/10/2026`.
  static String dataCurta(DateTime d) =>
      '${diaMes(d)}/${d.year.toString().padLeft(4, '0')}';

  /// `13 a 19 de outubro` — ou com o mês nos dois lados quando a semana
  /// atravessa a virada do mês (`28 de setembro a 4 de outubro`).
  static String intervaloSemana(DateTime qualquerDiaDaSemana) {
    final inicio = segundaDe(qualquerDiaDaSemana);
    final fim = somarDias(inicio, 6);
    if (inicio.month == fim.month) {
      return '${inicio.day} a ${fim.day} de ${_meses[inicio.month - 1]}';
    }
    return '${inicio.day} de ${_meses[inicio.month - 1]} a ${fim.day} de ${_meses[fim.month - 1]}';
  }

  /// `segunda, 21 de outubro` — usado nos cabeçalhos com data.
  static String diaPorExtenso(DateTime d) =>
      '${nomesSemana[indiceNaSemana(d)]}, ${d.day} de ${_meses[d.month - 1]}';

  /// Nomes por extenso na ordem da semana (segunda = 0).
  static const nomesSemana = [
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'domingo',
  ];

  /// `Seg`, `Ter`, … para colunas compactas.
  static const nomesCurtos = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  /// Quantos dias tem o mês de [d].
  static int diasNoMes(DateTime d) => DateTime(d.year, d.month + 1, 0).day;
}
