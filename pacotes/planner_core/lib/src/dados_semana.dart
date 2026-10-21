/// Template semanal — a tradução fiel do planejador HTML original.
///
/// A semana é um dado compilado, não um registro no banco: o template só muda
/// quando o produto muda. O que o usuário altera são as marcações e os cômodos,
/// e é só isso que a fonte de dados persiste.
///
/// Regras que vinham do arquivo original e foram preservadas:
/// - acordar às 6h, dormir às 22h;
/// - café, almoço, jantar e telas de desaceleração em todos os dias;
/// - dias pares (ter/qui) alternam academia e pilates com blocos de
///   reorganização; segunda e quarta são dias inteiros de reorganização;
/// - sábado troca o Inglês pela limpeza completa; domingo começa mais tarde e
///   reserva a tarde para recarregar.
library;

import 'modelos.dart';

/// Horários com hora marcada — compromisso fixo, não desloca.
const _fixo = true;

/// Bloco que ocupa a maior parte do dia.
const _prio = true;

Atividade _a(
  String dia,
  String horario,
  String titulo, {
  String detalhe = '',
  required Categoria categoria,
  bool fixo = false,
  bool prioridade = false,
}) => Atividade(
  id: Atividade.chavear(dia, horario),
  horario: horario,
  titulo: titulo,
  detalhe: detalhe,
  categoria: categoria,
  fixo: fixo,
  prioridade: prioridade,
);

/// Bloco de reorganização: título fixo, duração e objetivo no detalhe.
Atividade _reorganizacao(String dia, String horario, String duracao, [String objetivo = '']) => _a(
  dia,
  horario,
  'Reorganização',
  detalhe: objetivo.isEmpty ? duracao : '$duracao · $objetivo',
  categoria: Categoria.casa,
  prioridade: _prio,
);

/// A limpeza curta que fecha o dia — o "foco" do planejador original.
Atividade _foco(String dia, String horario, String alvo) => _a(
  dia,
  horario,
  'Limpeza do dia',
  detalhe: alvo,
  categoria: Categoria.casa,
);

/// Rotina da manhã, igual de segunda a sexta.
///
/// Sábado e domingo aproveitam só as três primeiras linhas: nesses dias o
/// Inglês e a aula dão lugar à limpeza completa e à reorganização da manhã.
List<Atividade> _manha(String dia) => [
  _a(dia, '06:00', 'Acordar', detalhe: 'Água e higiene', categoria: Categoria.bemEstar),
  _a(
    dia,
    '06:10',
    'Manutenção da limpeza',
    detalhe: 'Guardar a louça da lava-louça, arrumar a cama, aspirar o chão, pôr a mesa do café',
    categoria: Categoria.casa,
  ),
  _a(dia, '06:40', 'Café da manhã', detalhe: 'Sem tela', categoria: Categoria.bemEstar),
  _a(dia, '07:10', 'Inglês', detalhe: '45 minutos', categoria: Categoria.estudo),
  _a(dia, '08:00', 'Aula do curso XYZ', detalhe: 'Uma aula + anotações', categoria: Categoria.estudo),
];

List<Atividade> _almoco(String dia) => [
  _a(dia, '12:30', 'Almoço', categoria: Categoria.bemEstar),
];

/// Fim do dia: banho, leitura, preparação de amanhã e desaceleração.
List<Atividade> _noite(String dia) => [
  _a(dia, '18:30', 'Banho e jantar', categoria: Categoria.bemEstar),
  _a(dia, '19:30', 'Leitura', detalhe: '40 a 60 minutos do livro', categoria: Categoria.estudo),
  _a(
    dia,
    '20:30',
    'Preparar o dia seguinte',
    detalhe: 'Louça na lava-louça, bolsa pronta, cômodo de amanhã definido',
    categoria: Categoria.casa,
  ),
  _a(dia, '21:00', 'Desacelerar', detalhe: 'Luz baixa, sem telas fortes', categoria: Categoria.bemEstar),
  _a(dia, '22:00', 'Dormir', categoria: Categoria.bemEstar),
];

/// Segunda e quarta: reorganização o dia inteiro, um cômodo por vez.
List<Atividade> _diaLongo(String dia, String alvo) => [
  ..._manha(dia),
  _reorganizacao(dia, '09:00', '3h30', 'um cômodo ou categoria por vez'),
  ..._almoco(dia),
  _reorganizacao(dia, '13:30', '4h', 'continuar até fechar o cômodo'),
  _foco(dia, '17:30', alvo),
  ..._noite(dia),
];

/// Terça, quinta e sexta: academia de manhã, tarde dividida entre pilates e
/// reorganização, limpeza curta antes do jantar.
List<Atividade> _diaAcademia(String dia, String alvo, List<Atividade> tarde) => [
  ..._manha(dia),
  _reorganizacao(dia, '09:00', '1h30'),
  _a(
    dia,
    '10:30',
    'Preparar para a academia',
    detalhe: 'Bolsa pronta desde a noite anterior',
    categoria: Categoria.movimento,
  ),
  _a(dia, '11:00', 'Academia', categoria: Categoria.movimento, fixo: _fixo),
  ..._almoco(dia),
  ...tarde,
  _foco(dia, '18:00', alvo),
  ..._noite(dia),
];

/// Tarde de terça e quinta: pilates às 15h, cercado de reorganização.
List<Atividade> _tardePilates(String dia) => [
  _reorganizacao(dia, '13:30', '1h'),
  _a(dia, '14:30', 'Preparar para o pilates', categoria: Categoria.movimento),
  _a(dia, '15:00', 'Pilates', categoria: Categoria.movimento, fixo: _fixo),
  _reorganizacao(dia, '16:15', '1h45'),
];

/// Tarde de sexta: fechar o que ficou pela metade na semana.
List<Atividade> _tardeSexta(String dia) => [
  _reorganizacao(dia, '13:30', '4h', 'fechar o que ficou pela metade na semana'),
];

/// Sábado: limpeza completa no lugar da aula, reorganização o resto do dia.
List<Atividade> _sabado(String dia) => [
  ..._manha(dia).take(3),
  _a(
    dia,
    '07:10',
    'Limpeza completa',
    detalhe: '1h30, incluindo trocar roupa de cama e toalhas',
    categoria: Categoria.casa,
  ),
  _reorganizacao(dia, '09:00', '3h30'),
  ..._almoco(dia),
  _reorganizacao(dia, '13:30', '4h'),
  ..._noite(dia),
];

/// Domingo: reorganização de manhã, tarde de recarga e planejamento.
List<Atividade> _domingo(String dia) => [
  ..._manha(dia).take(3),
  _reorganizacao(dia, '07:30', '4h30'),
  ..._almoco(dia),
  _a(dia, '13:30', 'Descanso', detalhe: 'Recarregar para a semana', categoria: Categoria.bemEstar),
  _a(
    dia,
    '17:00',
    'Planejar a semana',
    detalhe: '20 min: próximos cômodos, compras, horários',
    categoria: Categoria.bemEstar,
  ),
  ..._noite(dia),
];

/// O template completo, na ordem de segunda a domingo.
List<Dia> construirSemana() => [
  Dia(
    chave: 'seg',
    nome: 'Segunda',
    nota: 'Dia inteiro de reorganização',
    atividades: _diaLongo('seg', 'Banheiros'),
  ),
  Dia(
    chave: 'ter',
    nome: 'Terça',
    nota: 'Reorganização entre academia e pilates',
    atividades: _diaAcademia('ter', 'Roupas: lavar e passar', _tardePilates('ter')),
  ),
  Dia(
    chave: 'qua',
    nome: 'Quarta',
    nota: 'Dia inteiro de reorganização',
    atividades: _diaLongo('qua', 'Cozinha: geladeira e fogão'),
  ),
  Dia(
    chave: 'qui',
    nome: 'Quinta',
    nota: 'Reorganização entre academia e pilates',
    atividades: _diaAcademia('qui', 'Tirar pó', _tardePilates('qui')),
  ),
  Dia(
    chave: 'sex',
    nome: 'Sexta',
    nota: 'Academia e tarde longa de reorganização',
    atividades: _diaAcademia('sex', 'Passar pano no chão', _tardeSexta('sex')),
  ),
  Dia(
    chave: 'sab',
    nome: 'Sábado',
    nota: 'Limpeza completa e reorganização',
    atividades: _sabado('sab'),
  ),
  Dia(
    chave: 'dom',
    nome: 'Domingo',
    nota: 'Reorganização de manhã, recarga à tarde',
    atividades: _domingo('dom'),
  ),
];

/// Semana recém-criada: template completo, nada marcado, cômodos padrão.
Semana semanaInicial() => Semana(dias: construirSemana(), marcadas: const {}, comodos: comodosPadrao());
