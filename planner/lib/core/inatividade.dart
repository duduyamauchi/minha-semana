import 'dart:async';

/// Encerra a sessão depois de um período sem uso.
///
/// Sem isso, quem entrasse de manhã continuaria autenticado à noite mesmo sem
/// tocar em nada — numa máquina compartilhada, isso é uma porta aberta. O
/// servidor também aplica o mesmo limite; aqui é a metade que avisa antes.
///
/// A classe não conhece Flutter nem HTTP: recebe um relógio e um callback, o que
/// a torna testável sem esperar uma hora.
class Inatividade {
  Inatividade({
    required this.limite,
    required this.aoExpirar,
    this.aviso = const Duration(minutes: 2),
    this.aoAvisar,
    DateTime Function()? agora,
    Timer Function(Duration, void Function())? agendar,
  }) : _agora = agora ?? DateTime.now,
       _agendar = agendar ?? ((d, f) => Timer(d, f)),
       _ultimoUso = (agora ?? DateTime.now)();

  /// Tempo máximo sem atividade.
  final Duration limite;

  /// Quanto tempo antes do limite o usuário é avisado.
  final Duration aviso;

  /// Chamado quando o limite estoura.
  final void Function() aoExpirar;

  /// Chamado quando entra na janela de aviso. Opcional.
  final void Function()? aoAvisar;

  final DateTime Function() _agora;
  final Timer Function(Duration, void Function()) _agendar;

  DateTime _ultimoUso;
  Timer? _timer;
  bool _encerrado = false;

  /// Indica se o usuário já está na janela de aviso.
  bool get emAviso => restante <= aviso && restante > Duration.zero;

  /// Quanto tempo falta para expirar (nunca negativo).
  Duration get restante {
    final passado = _agora().difference(_ultimoUso);
    final falta = limite - passado;
    return falta.isNegative ? Duration.zero : falta;
  }

  /// Marca atividade: reinicia a contagem.
  void registrarUso() {
    if (_encerrado) return;
    _ultimoUso = _agora();
    _reagendar();
  }

  void iniciar() {
    _encerrado = false;
    _ultimoUso = _agora();
    _reagendar();
  }

  void _reagendar() {
    _timer?.cancel();
    final falta = restante;
    if (falta == Duration.zero) {
      _expirar();
      return;
    }
    // Acorda no início da janela de aviso (se ela ainda não passou) para poder
    // avisar, e no limite para encerrar.
    final proximo = emAviso ? falta : (falta > aviso ? falta - aviso : falta);
    _timer = _agendar(proximo, () {
      if (_encerrado) return;
      if (emAviso) {
        aoAvisar?.call();
        _reagendar();
        return;
      }
      _expirar();
    });
  }

  void _expirar() {
    if (_encerrado) return;
    _encerrado = true;
    _timer?.cancel();
    aoExpirar();
  }

  /// Interrompe a contagem (logout explícito ou tela sem sessão).
  void parar() {
    _encerrado = true;
    _timer?.cancel();
  }
}
