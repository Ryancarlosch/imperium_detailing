import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/agendamento.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  static const int _idBase = 100000;
  static const int _idLimite = 200000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inicializado = false;

  Future<void> inicializar() async {
    if (_inicializado) {
      return;
    }

    tz_data.initializeTimeZones();

    try {
      final fuso =
          await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(
          tz.getLocation(fuso.identifier),
      );
    } catch (erro) {
      debugPrint(
        'Não foi possível identificar o fuso horário: '
        '$erro',
      );

      // Fuso padrão da região de Itaiópolis/SC.
      tz.setLocalLocation(
        tz.getLocation('America/Sao_Paulo'),
      );
    }

    const android =
        AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const configuracoes =
        InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(
      settings: configuracoes,
    );

    _inicializado = true;
  }

  Future<bool> solicitarPermissao() async {
    await inicializar();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final androidPermitido =
        await android?.requestNotificationsPermission();

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    final iosPermitido =
        await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    return androidPermitido ??
        iosPermitido ??
        true;
  }

  Future<void> sincronizarAgendamentos(
    List<Agendamento> agendamentos,
  ) async {
    await inicializar();

    final pendentes =
        await _plugin.pendingNotificationRequests();

    for (final notificacao in pendentes) {
      if (notificacao.id >= _idBase &&
          notificacao.id < _idLimite) {
        await _plugin.cancel(
          id: notificacao.id,
        );
      }
    }

    for (final agendamento in agendamentos) {
      if (agendamento.id == null) {
        continue;
      }

      if (agendamento.status == 'Cancelado' ||
          agendamento.status == 'Finalizado') {
        continue;
      }

      await agendarLembrete(
        agendamento,
      );
    }
  }

  Future<void> agendarLembrete(
    Agendamento agendamento,
  ) async {
    await inicializar();

    if (agendamento.id == null) {
      return;
    }

    final dataDoServico =
        _converterDataHora(
      agendamento.data,
      agendamento.hora,
    );

    if (dataDoServico == null) {
      debugPrint(
        'Data inválida no agendamento '
        '${agendamento.id}: '
        '${agendamento.data} ${agendamento.hora}',
      );
      return;
    }

    final agora = tz.TZDateTime.now(tz.local);

    if (!dataDoServico.isAfter(agora)) {
      return;
    }

    var dataDoLembrete =
        dataDoServico.subtract(
      const Duration(days: 1),
    );

    String titulo = 'Agendamento amanhã';
    String corpo =
        '${agendamento.servico} em '
        '${agendamento.data} às '
        '${agendamento.hora}.';

    if (!dataDoLembrete.isAfter(agora)) {
      dataDoLembrete = agora.add(
        const Duration(seconds: 10),
      );
      titulo = 'Agendamento em breve';
      corpo =
          '${agendamento.servico} está marcado para '
          '${agendamento.data} às '
          '${agendamento.hora}.';
    }

    const detalhesAndroid =
        AndroidNotificationDetails(
      'lembretes_agendamentos',
      'Lembretes de agendamentos',
      channelDescription:
          'Avisos um dia antes dos serviços agendados',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: '@mipmap/ic_launcher',
    );

    const detalhesIos =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const detalhes =
        NotificationDetails(
      android: detalhesAndroid,
      iOS: detalhesIos,
    );

    await _plugin.zonedSchedule(
      id: _idDaNotificacao(agendamento.id!),
      title: titulo,
      body: corpo,
      scheduledDate: dataDoLembrete,
      notificationDetails: detalhes,
      androidScheduleMode:
          AndroidScheduleMode.inexactAllowWhileIdle,
      payload:
          'agendamento:${agendamento.id}',
    );
  }

  Future<void> cancelarLembrete(
    int agendamentoId,
  ) async {
    await inicializar();

    await _plugin.cancel(
      id: _idDaNotificacao(agendamentoId),
    );
  }

  int _idDaNotificacao(int agendamentoId) {
    return _idBase +
        (agendamentoId % (_idLimite - _idBase));
  }

  tz.TZDateTime? _converterDataHora(
    String data,
    String hora,
  ) {
    final partesHora =
        hora.trim().split(':');

    if (partesHora.length < 2) {
      return null;
    }

    final horas =
        int.tryParse(partesHora[0]);
    final minutos =
        int.tryParse(partesHora[1]);

    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return null;
    }

    final dataLimpa = data.trim();

    final formatoBrasileiro =
        RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$')
            .firstMatch(dataLimpa);

    if (formatoBrasileiro != null) {
      return _criarDataValida(
        int.parse(formatoBrasileiro.group(3)!),
        int.parse(formatoBrasileiro.group(2)!),
        int.parse(formatoBrasileiro.group(1)!),
        horas,
        minutos,
      );
    }

    final formatoIso =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})')
            .firstMatch(dataLimpa);

    if (formatoIso != null) {
      return _criarDataValida(
        int.parse(formatoIso.group(1)!),
        int.parse(formatoIso.group(2)!),
        int.parse(formatoIso.group(3)!),
        horas,
        minutos,
      );
    }

    return null;
  }

  tz.TZDateTime? _criarDataValida(
    int ano,
    int mes,
    int dia,
    int hora,
    int minuto,
  ) {
    try {
      final resultado = tz.TZDateTime(
        tz.local,
        ano,
        mes,
        dia,
        hora,
        minuto,
      );

      if (resultado.year != ano ||
          resultado.month != mes ||
          resultado.day != dia) {
        return null;
      }

      return resultado;
    } catch (_) {
      return null;
    }
  }
}
