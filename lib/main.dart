import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

const _notificationChannelId = 'gps_tracking_channel';
const _notificationId = 912;
const _serviceEvent = 'gps_update';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureBackgroundService();
  runApp(const GpsTrackerApp());
}

Future<void> _configureBackgroundService() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  const channel = AndroidNotificationChannel(
    _notificationChannelId,
    'Seguimiento GPS',
    description: 'Mantiene activo el seguimiento GPS en segundo plano.',
    importance: Importance.low,
  );

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_bg_service_small'),
    ),
  );

  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _backgroundServiceEntryPoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'GPS activo',
      initialNotificationContent: 'Preparando seguimiento...',
      foregroundServiceNotificationId: _notificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

@pragma('vm:entry-point')
void _backgroundServiceEntryPoint(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();

  var tick = 0;
  Timer? timer;

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  Future<void> publishUpdate() async {
    tick += 1;

    Position? position;
    String? error;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }

    final timestamp = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'backgroundCount': tick,
      'timestamp': timestamp,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'accuracy': position?.accuracy,
      'error': error,
    };

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'GPS activo',
        content: 'Lecturas en segundo plano: $tick',
      );
    }

    service.invoke(_serviceEvent, payload);
  }

  service.on('pauseTracking').listen((_) {
    timer?.cancel();
    timer = null;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'GPS pausado',
        content: 'Toca la app para reanudar el seguimiento.',
      );
    }
  });

  service.on('resumeTracking').listen((_) {
    timer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => publishUpdate(),
    );
    publishUpdate();
  });

  service.on('resetTracking').listen((_) {
    tick = 0;
    service.invoke(_serviceEvent, {
      'backgroundCount': tick,
      'timestamp': DateTime.now().toIso8601String(),
      'reset': true,
    });
  });

  service.on('stopService').listen((_) {
    timer?.cancel();
    service.stopSelf();
  });

  service.invoke(_serviceEvent, {
    'backgroundCount': tick,
    'timestamp': DateTime.now().toIso8601String(),
  });
}

class GpsTrackerApp extends StatelessWidget {
  const GpsTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1f7a5f),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f4),
        useMaterial3: true,
      ),
      home: const GpsHomePage(),
    );
  }
}

class GpsHomePage extends StatefulWidget {
  const GpsHomePage({super.key});

  @override
  State<GpsHomePage> createState() => _GpsHomePageState();
}

class _GpsHomePageState extends State<GpsHomePage> with WidgetsBindingObserver {
  Timer? _foregroundTimer;
  Timer? _webSimulatorTimer;
  StreamSubscription<Map<String, dynamic>?>? _serviceSubscription;

  bool _tracking = false;
  bool _foregroundVisible = true;
  int _foregroundCount = 0;
  int _backgroundCount = 0;
  Position? _lastPosition;
  DateTime? _lastUpdate;
  String _status = 'Seguimiento pausado';
  String? _permissionMessage;
  final List<_TrackingHistoryEntry> _history = [];

  bool get _usesAndroidService =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_usesAndroidService) {
      try {
        _serviceSubscription = FlutterBackgroundService()
            .on(_serviceEvent)
            .listen(_handleBackgroundUpdate);
      } catch (_) {
        _serviceSubscription = null;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundTimer?.cancel();
    _webSimulatorTimer?.cancel();
    _serviceSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (_foregroundVisible == visible) {
      return;
    }
    setState(() {
      _foregroundVisible = visible;
      _status = _tracking
          ? (visible ? 'Seguimiento activo' : 'Seguimiento en segundo plano')
          : 'Seguimiento pausado';
    });
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _pauseTracking();
      return;
    }

    final allowed = await _ensureLocationPermission();
    if (!allowed) {
      return;
    }

    setState(() {
      _tracking = true;
      _status = 'Seguimiento activo';
      _permissionMessage = null;
    });

    _foregroundTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _captureForegroundTick(),
    );
    await _captureForegroundTick();

    if (_usesAndroidService) {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
      service.invoke('resumeTracking');
    } else {
      _startWebSimulator();
    }
  }

  Future<void> _pauseTracking() async {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    _webSimulatorTimer?.cancel();
    _webSimulatorTimer = null;

    if (_usesAndroidService) {
      FlutterBackgroundService().invoke('pauseTracking');
    }

    setState(() {
      _tracking = false;
      _status = 'Seguimiento pausado';
    });
  }

  void _clearTrackingData() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
    _webSimulatorTimer?.cancel();
    _webSimulatorTimer = null;

    if (_usesAndroidService) {
      FlutterBackgroundService().invoke('resetTracking');
      FlutterBackgroundService().invoke('pauseTracking');
    }

    setState(() {
      _tracking = false;
      _foregroundCount = 0;
      _backgroundCount = 0;
      _lastPosition = null;
      _lastUpdate = null;
      _permissionMessage = null;
      _status = 'Registros y contadores limpios';
      _history.clear();
    });
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() {
        _permissionMessage = 'Activa el GPS del dispositivo para continuar.';
        _status = 'GPS desactivado';
      });
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _permissionMessage =
            'Concede permiso de ubicacion. En Android habilita tambien "Permitir todo el tiempo" para segundo plano.';
        _status = 'Permiso requerido';
      });
      return false;
    }

    if (_usesAndroidService && permission != LocationPermission.always) {
      setState(() {
        _permissionMessage =
            'Para seguimiento real en segundo plano, cambia el permiso de ubicacion a "Permitir todo el tiempo" en ajustes de Android.';
      });
    }

    if (_usesAndroidService) {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    return true;
  }

  Future<void> _captureForegroundTick() async {
    if (!_tracking) {
      return;
    }

    Position? position;
    String? error;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }

    if (!mounted || !_tracking) {
      return;
    }

    setState(() {
      _foregroundCount += 1;
      _lastPosition = position ?? _lastPosition;
      _lastUpdate = DateTime.now();
      _addHistoryEntry(
        source: 'Primer plano',
        count: _foregroundCount,
        position: position,
        timestamp: _lastUpdate!,
        message: error == null ? 'Lectura GPS registrada' : 'Lectura fallida',
      );
      if (error != null) {
        _permissionMessage = 'No se pudo leer GPS: $error';
      }
    });
  }

  void _startWebSimulator() {
    _webSimulatorTimer?.cancel();
    _webSimulatorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_tracking) {
        return;
      }
      setState(() {
        _backgroundCount += 1;
        _lastUpdate = DateTime.now();
        _status = kIsWeb
            ? 'Simulador web activo'
            : 'Simulador de segundo plano activo';
        _addHistoryEntry(
          source: kIsWeb ? 'Simulador web' : 'Simulador',
          count: _backgroundCount,
          position: _lastPosition,
          timestamp: _lastUpdate!,
          message: 'Pulso de segundo plano simulado',
        );
      });
    });
  }

  void _handleBackgroundUpdate(Map<String, dynamic>? data) {
    if (!mounted || data == null) {
      return;
    }

    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    final accuracy = (data['accuracy'] as num?)?.toDouble();
    final timestamp = DateTime.tryParse('${data['timestamp']}');
    final error = data['error'] as String?;
    final reset = data['reset'] == true;

    setState(() {
      _backgroundCount = data['backgroundCount'] as int? ?? _backgroundCount;
      _lastUpdate = timestamp ?? _lastUpdate;
      if (latitude != null && longitude != null) {
        _lastPosition = Position(
          longitude: longitude,
          latitude: latitude,
          timestamp: timestamp ?? DateTime.now(),
          accuracy: accuracy ?? 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }
      if (!reset && _backgroundCount > 0) {
        _addHistoryEntry(
          source: 'Segundo plano',
          count: _backgroundCount,
          position: _lastPosition,
          timestamp: _lastUpdate ?? DateTime.now(),
          message: error == null ? 'Lectura GPS registrada' : 'Lectura fallida',
        );
      }
      if (error != null && error.isNotEmpty) {
        _permissionMessage = 'Segundo plano: $error';
      }
    });
  }

  void _addHistoryEntry({
    required String source,
    required int count,
    required Position? position,
    required DateTime timestamp,
    required String message,
  }) {
    _history.insert(
      0,
      _TrackingHistoryEntry(
        source: source,
        count: count,
        position: position,
        timestamp: timestamp,
        message: message,
      ),
    );
    if (_history.length > 30) {
      _history.removeRange(30, _history.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento GPS'), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Monitor de ubicacion',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _status,
              style: textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final cards = [
                  _MetricCard(
                    icon: Icons.phone_android,
                    label: 'Primer plano',
                    value: _foregroundCount.toString(),
                    detail: _foregroundVisible ? 'App visible' : 'App oculta',
                  ),
                  _MetricCard(
                    icon: Icons.cloud_sync,
                    label: 'Segundo plano',
                    value: _backgroundCount.toString(),
                    detail: _usesAndroidService
                        ? 'Servicio Android'
                        : 'Simulador web',
                  ),
                ];

                if (!wide) {
                  return Column(
                    children: [cards[0], const SizedBox(height: 12), cards[1]],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _LocationCard(position: _lastPosition, lastUpdate: _lastUpdate),
            const SizedBox(height: 12),
            _HistoryCard(entries: _history),
            if (_permissionMessage != null) ...[
              const SizedBox(height: 12),
              _WarningPanel(message: _permissionMessage!),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(_tracking ? Icons.pause : Icons.play_arrow),
              label: Text(_tracking ? 'Pausar GPS' : 'Seguir con GPS'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                textStyle: textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Geolocator.openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Abrir permisos de la app'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearTrackingData,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Limpiar registros y contadores'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingHistoryEntry {
  const _TrackingHistoryEntry({
    required this.source,
    required this.count,
    required this.position,
    required this.timestamp,
    required this.message,
  });

  final String source;
  final int count;
  final Position? position;
  final DateTime timestamp;
  final String message;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(height: 14),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(detail),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.position, required this.lastUpdate});

  final Position? position;
  final DateTime? lastUpdate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latitude = position?.latitude.toStringAsFixed(6) ?? '--';
    final longitude = position?.longitude.toStringAsFixed(6) ?? '--';
    final accuracy = position == null
        ? '--'
        : '${position!.accuracy.toStringAsFixed(1)} m';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.my_location, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Ultima ubicacion',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LocationRow(label: 'Latitud', value: latitude),
          _LocationRow(label: 'Longitud', value: longitude),
          _LocationRow(label: 'Precision', value: accuracy),
          _LocationRow(
            label: 'Actualizado',
            value: lastUpdate == null
                ? '--'
                : TimeOfDay.fromDateTime(lastUpdate!).format(context),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entries});

  final List<_TrackingHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleEntries = entries.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Historial de seguimiento',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (visibleEntries.isEmpty)
            Text(
              'Sin registros todavia',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            ...visibleEntries.map((entry) => _HistoryRow(entry: entry)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final _TrackingHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final position = entry.position;
    final coordinates = position == null
        ? 'Sin coordenadas'
        : '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.source} #${entry.count}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(entry.message),
                Text(
                  '$coordinates - ${TimeOfDay.fromDateTime(entry.timestamp).format(context)}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
