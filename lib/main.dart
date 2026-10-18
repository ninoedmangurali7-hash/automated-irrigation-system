import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

const bool demoMode = true;
const String systemId = 'greenhouse-1';

const _webFirebaseOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
  appId: String.fromEnvironment('FIREBASE_APP_ID'),
  messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!demoMode) {
    if (kIsWeb &&
        (DefaultFirebaseOptions.currentPlatform.apiKey.contains('YOUR_') ||
            DefaultFirebaseOptions.currentPlatform.appId.contains('YOUR_') ||
            DefaultFirebaseOptions.currentPlatform.messagingSenderId
                .contains('YOUR_') ||
            DefaultFirebaseOptions.currentPlatform.projectId.contains('YOUR_'))) {
      throw StateError(
        'Firebase configuration is not set. Replace lib/firebase_options.dart '
        'with your project settings or run flutterfire configure.',
      );
    }
    await Firebase.initializeApp(
      options: kIsWeb ? DefaultFirebaseOptions.currentPlatform : null,
    );
  }
  runApp(const IrrigationApp());
}

class IrrigationReading {
  const IrrigationReading({
    required this.moisture,
    required this.fieldBMoisture,
    required this.threshold,
    required this.pumpOn,
    required this.valveAOpen,
    required this.valveBOpen,
    required this.automaticMode,
    required this.waterToday,
    required this.baselineWater,
    required this.automatedWater,
    required this.updatedAt,
    this.fieldAWaterToday,
    this.fieldBWaterToday,
  });

  final double moisture;
  final double fieldBMoisture;
  final double threshold;
  final bool pumpOn;
  final bool valveAOpen;
  final bool valveBOpen;
  final bool automaticMode;
  final double waterToday;
  final double baselineWater;
  final double automatedWater;
  final DateTime updatedAt;
  final double? fieldAWaterToday;
  final double? fieldBWaterToday;

  double get waterSavedPerDay => baselineWater - automatedWater;

  int? get waterSavedPercent => baselineWater <= 0
      ? null
      : (waterSavedPerDay / baselineWater * 100).round();

  factory IrrigationReading.fromMap(Map<String, dynamic> data) {
    double number(String field) {
      final value = data[field];
      if (value is! num) {
        throw FormatException('Firestore field "$field" must be a number.');
      }
      return value.toDouble();
    }

    double optionalNumber(String field, double fallback) {
      final value = data[field];
      if (value == null) return fallback;
      if (value is! num) {
        throw FormatException('Firestore field "$field" must be a number.');
      }
      return value.toDouble();
    }

    double? optionalWater(String field) {
      final value = data[field];
      if (value == null) return null;
      if (value is! num) {
        throw FormatException('Firestore field "$field" must be a number.');
      }
      return value.toDouble();
    }

    bool optionalBool(String field) {
      final value = data[field];
      if (value == null) return false;
      if (value is! bool) {
        throw FormatException('Firestore field "$field" must be a boolean.');
      }
      return value;
    }

    final mode = data['mode'];
    if (mode != 'automatic' && mode != 'manual') {
      throw const FormatException(
        'Firestore field "mode" must be "automatic" or "manual".',
      );
    }
    final pumpOn = data['actualPumpOn'];
    if (pumpOn is! bool) {
      throw const FormatException(
        'Firestore field "actualPumpOn" must be a boolean.',
      );
    }
    final lastUpdated = data['lastUpdated'];
    if (lastUpdated is! Timestamp) {
      throw const FormatException(
        'Firestore field "lastUpdated" must be a timestamp.',
      );
    }

    final moisture = optionalNumber('fieldAMoisture', number('moisture'));
    return IrrigationReading(
      moisture: moisture,
      fieldBMoisture: optionalNumber('fieldBMoisture', moisture),
      threshold: number('threshold'),
      pumpOn: pumpOn,
      valveAOpen: optionalBool('valveAOpen'),
      valveBOpen: optionalBool('valveBOpen'),
      automaticMode: mode == 'automatic',
      waterToday: number('waterUsedToday'),
      baselineWater: number('baselineWater'),
      automatedWater: number('automatedWater'),
      updatedAt: lastUpdated.toDate(),
      fieldAWaterToday: optionalWater('fieldAWaterToday'),
      fieldBWaterToday: optionalWater('fieldBWaterToday'),
    );
  }
}

List<String> newlyDryFields({
  required IrrigationReading? previous,
  required IrrigationReading current,
}) {
  if (previous == null || previous.threshold != current.threshold) {
    return const [];
  }
  return [
    if (previous.moisture >= current.threshold &&
        current.moisture < current.threshold)
      'A',
    if (previous.fieldBMoisture >= current.threshold &&
        current.fieldBMoisture < current.threshold)
      'B',
  ];
}

class MoistureSample {
  const MoistureSample({
    required this.moisture,
    required this.recordedAt,
    this.fieldBMoisture,
  });

  final double moisture;
  final double? fieldBMoisture;
  final DateTime recordedAt;

  factory MoistureSample.fromMap(Map<String, dynamic> data) {
    final moisture = data['moisture'];
    if (moisture is! num) {
      throw const FormatException(
        'Moisture history field "moisture" must be a number.',
      );
    }
    final recordedAt = data['recordedAt'];
    if (recordedAt is! Timestamp) {
      throw const FormatException(
        'Moisture history field "recordedAt" must be a timestamp.',
      );
    }
    return MoistureSample(
      moisture: moisture.toDouble(),
      recordedAt: recordedAt.toDate(),
      fieldBMoisture: data['fieldBMoisture'] is num
          ? (data['fieldBMoisture'] as num).toDouble()
          : null,
    );
  }
}

class IrrigationEvent {
  const IrrigationEvent({
    required this.title,
    required this.details,
    required this.type,
    required this.occurredAt,
  });

  final String title;
  final String details;
  final String type;
  final DateTime occurredAt;

  factory IrrigationEvent.fromMap(Map<String, dynamic> data) {
    final title = data['title'];
    final details = data['details'];
    final type = data['type'];
    final occurredAt = data['occurredAt'];
    if (title is! String ||
        details is! String ||
        type is! String ||
        occurredAt is! Timestamp) {
      throw const FormatException('Invalid irrigation event document.');
    }
    return IrrigationEvent(
      title: title,
      details: details,
      type: type,
      occurredAt: occurredAt.toDate(),
    );
  }
}

abstract interface class IrrigationRepository {
  Stream<IrrigationReading> watchReading();
  Stream<List<MoistureSample>> watchMoistureHistory();
  Stream<List<IrrigationEvent>> watchEvents();
  Future<void> setThreshold(double value);
  Future<void> setAutomaticMode(bool enabled);
  Future<void> setManualPump(bool enabled);
  Future<void> setValveCommand(String valve, bool open);
}

class DemoIrrigationRepository implements IrrigationRepository {
  DemoIrrigationRepository() {
    _moistureHistory.add(
      MoistureSample(
        moisture: _reading.moisture,
        fieldBMoisture: _reading.fieldBMoisture,
        recordedAt: DateTime.now(),
      ),
    );
    for (var daysAgo = 1; daysAgo <= 6; daysAgo++) {
      _moistureHistory.add(
        MoistureSample(
          moisture: [38, 46, 31, 52, 43, 35][daysAgo - 1].toDouble(),
          fieldBMoisture: [61, 57, 72, 66, 70, 64][daysAgo - 1].toDouble(),
          recordedAt: DateTime.now().subtract(Duration(days: daysAgo)),
        ),
      );
    }
    final now = DateTime.now();
    _events.addAll([
      IrrigationEvent(
        title: 'Valve A opened — auto',
        details: 'Today, 7:42 AM · moisture dropped to 24%',
        type: 'watering',
        occurredAt: now.subtract(const Duration(minutes: 8)),
      ),
      IrrigationEvent(
        title: 'Field B moisture normal',
        details: 'Today, 6:15 AM · 68%',
        type: 'normal',
        occurredAt: now.subtract(const Duration(hours: 1)),
      ),
      IrrigationEvent(
        title: 'Pump maintenance reminder',
        details: '3 days ago · 30 days since last check',
        type: 'reminder',
        occurredAt: now.subtract(const Duration(days: 3)),
      ),
      IrrigationEvent(
        title: 'Weekly summary ready',
        details: '7 days of irrigation data collected',
        type: 'report',
        occurredAt: now.subtract(const Duration(days: 4)),
      ),
    ]);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final previousValveAOpen = _reading.valveAOpen;
      final previousValveBOpen = _reading.valveBOpen;
      if (_reading.automaticMode) {
        double nextMoisture(double moisture, bool valveOpen) => valveOpen
            ? math.min(_reading.threshold + 6, moisture + 2).toDouble()
            : math.max(8, moisture - 0.4).toDouble();
        final fieldAMoisture =
            nextMoisture(_reading.moisture, _reading.valveAOpen);
        final fieldBMoisture =
            nextMoisture(_reading.fieldBMoisture, _reading.valveBOpen);
        final valveAOpen = fieldAMoisture < _reading.threshold;
        final valveBOpen = fieldBMoisture < _reading.threshold;
        _reading = _copy(
          moisture: fieldAMoisture,
          fieldBMoisture: fieldBMoisture,
          pumpOn: valveAOpen || valveBOpen,
          valveAOpen: valveAOpen,
          valveBOpen: valveBOpen,
          waterToday: _reading.waterToday +
              (valveAOpen || valveBOpen ? 0.2 : 0),
        );
      } else {
        _reading = _copy(
          moisture: math.max(8, _reading.moisture - 0.1).toDouble(),
          fieldBMoisture:
              math.max(8, _reading.fieldBMoisture - 0.1).toDouble(),
        );
      }
      _controller.add(_reading);
      if (!previousValveAOpen && _reading.valveAOpen) {
        _recordEvent(
          'Valve A opened — auto',
          'Field A moisture is ${_reading.moisture.round()}%',
          'watering',
        );
      }
      if (!previousValveBOpen && _reading.valveBOpen) {
        _recordEvent(
          'Valve B opened — auto',
          'Field B moisture is ${_reading.fieldBMoisture.round()}%',
          'watering',
        );
      }
      _moistureHistory[0] =
          MoistureSample(
            moisture: _reading.moisture,
            fieldBMoisture: _reading.fieldBMoisture,
            recordedAt: DateTime.now(),
          );
      _historyController.add(List.unmodifiable(_moistureHistory));
    });
  }

  final StreamController<IrrigationReading> _controller =
      StreamController<IrrigationReading>.broadcast();
  final StreamController<List<MoistureSample>> _historyController =
      StreamController<List<MoistureSample>>.broadcast();
  final StreamController<List<IrrigationEvent>> _eventController =
      StreamController<List<IrrigationEvent>>.broadcast();
  final List<MoistureSample> _moistureHistory = [];
  final List<IrrigationEvent> _events = [];
  Timer? _timer;
  IrrigationReading _reading = IrrigationReading(
    moisture: 24,
    fieldBMoisture: 68,
    threshold: 35,
    pumpOn: true,
    valveAOpen: true,
    valveBOpen: false,
    automaticMode: true,
    waterToday: 18.4,
    baselineWater: 42,
    automatedWater: 25,
    updatedAt: DateTime.now(),
    fieldAWaterToday: 10.6,
    fieldBWaterToday: 7.8,
  );

  void _recordEvent(String title, String details, String type) {
    _events.insert(
      0,
      IrrigationEvent(
        title: title,
        details: details,
        type: type,
        occurredAt: DateTime.now(),
      ),
    );
    if (_events.length > 50) _events.removeLast();
    _eventController.add(List.unmodifiable(_events));
  }

  IrrigationReading _copy({
    double? moisture,
    double? fieldBMoisture,
    double? threshold,
    bool? pumpOn,
    bool? valveAOpen,
    bool? valveBOpen,
    bool? automaticMode,
    double? waterToday,
  }) =>
      IrrigationReading(
        moisture: moisture ?? _reading.moisture,
        fieldBMoisture: fieldBMoisture ?? _reading.fieldBMoisture,
        threshold: threshold ?? _reading.threshold,
        pumpOn: pumpOn ?? _reading.pumpOn,
        valveAOpen: valveAOpen ?? _reading.valveAOpen,
        valveBOpen: valveBOpen ?? _reading.valveBOpen,
        automaticMode: automaticMode ?? _reading.automaticMode,
        waterToday: waterToday ?? _reading.waterToday,
        baselineWater: _reading.baselineWater,
        automatedWater: _reading.automatedWater,
        updatedAt: DateTime.now(),
        fieldAWaterToday: _reading.fieldAWaterToday,
        fieldBWaterToday: _reading.fieldBWaterToday,
      );

  @override
  Stream<IrrigationReading> watchReading() async* {
    yield _reading;
    yield* _controller.stream;
  }

  @override
  Stream<List<MoistureSample>> watchMoistureHistory() async* {
    yield List.unmodifiable(_moistureHistory);
    yield* _historyController.stream;
  }

  @override
  Stream<List<IrrigationEvent>> watchEvents() async* {
    yield List.unmodifiable(_events);
    yield* _eventController.stream;
  }

  @override
  Future<void> setThreshold(double value) async {
    _reading = _copy(threshold: value);
    _controller.add(_reading);
  }

  @override
  Future<void> setAutomaticMode(bool enabled) async {
    final valveAOpen =
        enabled && _reading.moisture < _reading.threshold;
    final valveBOpen =
        enabled && _reading.fieldBMoisture < _reading.threshold;
    _reading = _copy(
      automaticMode: enabled,
      valveAOpen: valveAOpen,
      valveBOpen: valveBOpen,
      pumpOn: valveAOpen || valveBOpen,
    );
    _controller.add(_reading);
  }

  @override
  Future<void> setManualPump(bool enabled) async {
    _reading = _copy(
      automaticMode: false,
      pumpOn: enabled,
      valveAOpen: enabled ? _reading.valveAOpen : false,
      valveBOpen: enabled ? _reading.valveBOpen : false,
    );
    _controller.add(_reading);
    _recordEvent(
      enabled ? 'Pump started manually' : 'Pump stopped manually',
      'Manual pump control changed in the app',
      'manual',
    );
  }

  @override
  Future<void> setValveCommand(String valve, bool open) async {
    if (valve != 'A' && valve != 'B') {
      throw ArgumentError.value(valve, 'valve', 'Expected A or B.');
    }
    _reading = _copy(
      automaticMode: false,
      valveAOpen: valve == 'A' ? open : _reading.valveAOpen,
      valveBOpen: valve == 'B' ? open : _reading.valveBOpen,
      pumpOn: valve == 'A'
          ? open || _reading.valveBOpen
          : open || _reading.valveAOpen,
    );
    _controller.add(_reading);
    _recordEvent(
      'Valve $valve ${open ? 'opened' : 'closed'} — manual',
      'Manual valve override changed in the app',
      'manual',
    );
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
    _historyController.close();
    _eventController.close();
  }
}

class FirebaseIrrigationRepository implements IrrigationRepository {
  FirebaseIrrigationRepository()
      : _document = FirebaseFirestore.instance
            .collection('systems')
            .doc(systemId)
            .collection('telemetry')
            .doc('current');

  final DocumentReference<Map<String, dynamic>> _document;

  @override
  Stream<List<MoistureSample>> watchMoistureHistory() => FirebaseFirestore
      .instance
      .collection('systems')
      .doc(systemId)
      .collection('readings')
      .where(
        'recordedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 7)),
        ),
      )
      .orderBy('recordedAt', descending: true)
      .limit(168)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => MoistureSample.fromMap(document.data()))
            .toList(growable: false),
      );

  @override
  Stream<List<IrrigationEvent>> watchEvents() => FirebaseFirestore.instance
      .collection('systems')
      .doc(systemId)
      .collection('events')
      .orderBy('occurredAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => IrrigationEvent.fromMap(document.data()))
            .toList(growable: false),
      );

  @override
  Stream<IrrigationReading> watchReading() => _document.snapshots().map(
        (snapshot) {
          if (!snapshot.exists) {
            throw StateError(
              'Firestore document systems/$systemId/telemetry/current '
              'does not exist.',
            );
          }
          return IrrigationReading.fromMap(snapshot.data()!);
        },
      );

  @override
  Future<void> setThreshold(double value) =>
      _document.set({'threshold': value}, SetOptions(merge: true));

  @override
  Future<void> setAutomaticMode(bool enabled) => _document.set(
        {
          'mode': enabled ? 'automatic' : 'manual',
          'pumpCommand': false,
          'valveACommand': false,
          'valveBCommand': false,
        },
        SetOptions(merge: true),
      );

  @override
  Future<void> setManualPump(bool enabled) => _document.set(
        {
          'mode': 'manual',
          'pumpCommand': enabled,
          if (!enabled) 'valveACommand': false,
          if (!enabled) 'valveBCommand': false,
        },
        SetOptions(merge: true),
      );

  @override
  Future<void> setValveCommand(String valve, bool open) {
    if (valve != 'A' && valve != 'B') {
      throw ArgumentError.value(valve, 'valve', 'Expected A or B.');
    }
    return _document.set(
      {'mode': 'manual', 'valve${valve}Command': open},
      SetOptions(merge: true),
    );
  }
}

class IrrigationApp extends StatelessWidget {
  const IrrigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF75B7FF);
    return MaterialApp(
      title: 'Irrigation monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F8F6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        dividerColor: const Color(0xFFE5EAE6),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: const Color(0xFF202722),
              displayColor: const Color(0xFF202722),
            ),
        fontFamily: 'Roboto',
      ),
      home: IrrigationHome(
        repository: demoMode
            ? DemoIrrigationRepository()
            : FirebaseIrrigationRepository(),
      ),
    );
  }
}

class IrrigationHome extends StatefulWidget {
  const IrrigationHome({required this.repository, super.key});

  final IrrigationRepository repository;

  @override
  State<IrrigationHome> createState() => _IrrigationHomeState();
}

class _IrrigationHomeState extends State<IrrigationHome> {
  int _selectedTab = 0;
  double _threshold = 35;
  double? _lastStreamThreshold;
  bool _showAlerts = false;
  bool _showReport = false;
  bool _alertsEnabled = true;
  bool _historyFieldA = true;
  late final Stream<IrrigationReading> _readingStream;
  late final StreamSubscription<IrrigationReading> _alertSubscription;
  IrrigationReading? _previousReading;

  @override
  void initState() {
    super.initState();
    _readingStream = widget.repository.watchReading().asBroadcastStream();
    _alertSubscription = _readingStream.listen(
      _handleAlertReading,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Moisture alert stream failed: $error\n$stackTrace');
      },
    );
  }

  void _handleAlertReading(IrrigationReading current) {
    final newlyDry = newlyDryFields(
      previous: _previousReading,
      current: current,
    );
    _previousReading = current;
    if (!mounted || !_alertsEnabled || newlyDry.isEmpty) return;

    final fields = newlyDry.map((field) => 'Field $field').join(' and ');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFFFF2D9),
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD59015)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$fields moisture fell below ${current.threshold.round()}%.',
                    style: const TextStyle(color: Color(0xFF855A0A)),
                  ),
                ),
              ],
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    unawaited(_alertSubscription.cancel());
    if (widget.repository case final DemoIrrigationRepository repository) {
      repository.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IrrigationReading>(
      stream: _readingStream,
      builder: (context, snapshot) {
        final reading = snapshot.data;
        if (reading != null && reading.threshold != _lastStreamThreshold) {
          _lastStreamThreshold = reading.threshold;
          _threshold = reading.threshold;
        }
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wideLayout = constraints.maxWidth >= 760;
                final page = snapshot.hasError
                    ? _ErrorPanel(message: snapshot.error.toString())
                    : reading == null
                        ? const Center(child: CircularProgressIndicator())
                        : _showAlerts
                            ? _alerts()
                            : _showReport
                                ? _report(reading)
                                : _selectedTab == 0
                                    ? _overview(reading)
                                    : _selectedTab == 1
                                        ? _fieldMap(reading)
                                        : _selectedTab == 2
                                            ? _history(reading)
                                            : _settings(reading);
                return Row(
                  children: [
                    if (wideLayout)
                      NavigationRail(
                        selectedIndex: _selectedTab,
                        onDestinationSelected: (index) => setState(() {
                          _selectedTab = index;
                          _showAlerts = false;
                          _showReport = false;
                        }),
                        labelType: NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Icon(Icons.water_drop_rounded,
                              color: Color(0xFF438BD2), size: 30),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home_rounded),
                            label: Text('Dashboard'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.map_outlined),
                            selectedIcon: Icon(Icons.map_rounded),
                            label: Text('Map'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.schedule_outlined),
                            selectedIcon: Icon(Icons.schedule_rounded),
                            label: Text('History'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings_rounded),
                            label: Text('Settings'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: page,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
              ? _BottomNavigationBar(
                  selectedIndex: _selectedTab,
                  onDestinationSelected: (index) => setState(() {
                    _selectedTab = index;
                    _showAlerts = false;
                    _showReport = false;
                  }),
                )
              : null,
        );
      },
    );
  }

  Widget _overview(IrrigationReading reading) {
    final fieldADry = reading.moisture < reading.threshold;
    final fieldBDry = reading.fieldBMoisture < reading.threshold;
    return _Page(
      title: 'Irrigation monitor',
      subtitle: 'Updated ${_timeAgo(reading.updatedAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ConnectionBadge(isDemo: demoMode),
          IconButton(
            tooltip: 'Alerts',
            onPressed: () => setState(() {
              _showAlerts = true;
              _showReport = false;
            }),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      children: [
        if (fieldADry || fieldBDry) ...[
          _DryFieldAlert(
            field: fieldADry ? 'A' : 'B',
            valveOpen: fieldADry ? reading.valveAOpen : reading.valveBOpen,
            automaticMode: reading.automaticMode,
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: _ZoneCard(
                label: 'Field A',
                moisture: reading.moisture,
                threshold: reading.threshold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ZoneCard(
                label: 'Field B',
                moisture: reading.fieldBMoisture,
                threshold: reading.threshold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SharedPumpCard(
          reading: reading,
          onPumpChanged: (enabled) =>
              _run(() => widget.repository.setManualPump(enabled)),
          onValveChanged: (valve, open) => _run(
            () => widget.repository.setValveCommand(valve, open),
          ),
        ),
        const SizedBox(height: 14),
        _SevenDayMoistureCard(
          repository: widget.repository,
          threshold: reading.threshold,
        ),
        const SizedBox(height: 14),
        _WaterTodayCard(reading: reading),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fieldMap(IrrigationReading reading) {
    return _Page(
      title: 'Field map',
      subtitle: 'Live moisture and valve status for both fields.',
      children: [
        Container(
          height: 265,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3E8),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MapField(
                  label: 'Field A',
                  moisture: reading.moisture,
                  threshold: reading.threshold,
                  valveOpen: reading.valveAOpen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MapField(
                  label: 'Field B',
                  moisture: reading.fieldBMoisture,
                  threshold: reading.threshold,
                  valveOpen: reading.valveBOpen,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SharedPumpCard(
          reading: reading,
          onValveChanged: (valve, open) => _run(
            () => widget.repository.setValveCommand(valve, open),
          ),
          onPumpChanged: (enabled) =>
              _run(() => widget.repository.setManualPump(enabled)),
        ),
        const SizedBox(height: 14),
        _MapLegend(reading: reading),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _history(IrrigationReading reading) {
    return _Page(
      title: 'History',
      subtitle: 'Moisture and irrigation activity.',
      children: [
        Row(
          children: [
            _FieldSelector(
              label: 'Field A',
              selected: _historyFieldA,
              onTap: () => setState(() => _historyFieldA = true),
            ),
            const SizedBox(width: 8),
            _FieldSelector(
              label: 'Field B',
              selected: !_historyFieldA,
              onTap: () => setState(() => _historyFieldA = false),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() {
                _showReport = true;
                _showAlerts = false;
              }),
              icon: const Icon(Icons.assessment_outlined, size: 18),
              label: const Text('Report'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MoistureHistoryCard(
          repository: widget.repository,
          field: _historyFieldA ? 'A' : 'B',
        ),
        const SizedBox(height: 16),
        _EventList(repository: widget.repository, title: 'Water log'),
        const SizedBox(height: 16),
        _SavingsCard(reading: reading, expanded: true),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _alerts() => _Page(
        title: 'Alerts',
        subtitle: 'Dryness warnings, auto-watering, and reminders.',
        trailing: IconButton(
          tooltip: 'Back to dashboard',
          onPressed: () => setState(() => _showAlerts = false),
          icon: const Icon(Icons.close),
        ),
        children: [
          _EventList(repository: widget.repository, title: 'Recent alerts'),
          const SizedBox(height: 24),
        ],
      );

  Widget _report(IrrigationReading reading) => _Page(
        title: 'Water usage report',
        subtitle: 'Weekly consumption, per-field breakdown, and estimated savings.',
        trailing: IconButton(
          tooltip: 'Back to history',
          onPressed: () => setState(() => _showReport = false),
          icon: const Icon(Icons.close),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _ReportMetric(
                  label: 'This week',
                  value: '${(reading.automatedWater * 7).toStringAsFixed(0)} L',
                  note: 'Based on daily average',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReportMetric(
                  label: 'Weekly savings',
                  value: reading.waterSavedPercent == null
                      ? '—'
                      : '${(reading.waterSavedPerDay.abs() * 7).toStringAsFixed(1)} L',
                  note: reading.waterSavedPercent == null
                      ? 'record a baseline first'
                      : reading.waterSavedPerDay >= 0
                          ? 'water saved vs. baseline'
                          : 'additional water used',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usage by field',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 16),
                _FieldUsageRow(
                  label: 'Field A',
                  usage: reading.fieldAWaterToday,
                  total: reading.waterToday,
                  color: const Color(0xFF4F9E69),
                ),
                const SizedBox(height: 14),
                _FieldUsageRow(
                  label: 'Field B',
                  usage: reading.fieldBWaterToday,
                  total: reading.waterToday,
                  color: const Color(0xFF75B7FF),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SavingsCard(reading: reading, expanded: true),
          const SizedBox(height: 24),
        ],
      );

  Widget _settings(IrrigationReading reading) {
    return _Page(
      title: 'Settings',
      subtitle: 'Fine-tune how your irrigation system works.',
      children: [
        _ControlCard(
          reading: reading,
          threshold: _threshold,
          onThresholdChanged: (value) => setState(() => _threshold = value),
          onThresholdChangeEnd: (value) => _run(
            () => widget.repository.setThreshold(value),
          ),
          onModeChanged: (value) =>
              _run(() => widget.repository.setAutomaticMode(value)),
          onPumpChanged: (value) =>
              _run(() => widget.repository.setManualPump(value)),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Moisture alerts'),
            subtitle: const Text('Show alerts while the app is open'),
            value: _alertsEnabled,
            onChanged: (enabled) => setState(() => _alertsEnabled = enabled),
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Alerts and activity'),
            subtitle: const Text('View watering events and reminders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _showAlerts = true),
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('System details',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 18),
              _DetailRow('System ID', systemId),
              const _ThinDivider(),
              _DetailRow('Connection', demoMode ? 'Demo mode' : 'Firebase'),
              const _ThinDivider(),
              _DetailRow(
                'Last updated',
                '${reading.updatedAt.hour.toString().padLeft(2, '0')}:'
                    '${reading.updatedAt.minute.toString().padLeft(2, '0')}',
              ),
              const _ThinDivider(),
              const _DetailRow('Device', 'ESP32 · ready to connect'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_outlined, color: Color(0xFF31D3A0)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  demoMode
                      ? 'You are viewing a live simulation. Configure Firebase '
                          'to monitor and control your real device remotely.'
                      : 'Live data streams from your Firebase-connected irrigation system.',
                  style: const TextStyle(
                    color: Color(0xFF68716B),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the system: $error')),
        );
      }
    }
  }
}

class _MapField extends StatelessWidget {
  const _MapField({
    required this.label,
    required this.moisture,
    required this.threshold,
    required this.valveOpen,
  });

  final String label;
  final double moisture;
  final double threshold;
  final bool valveOpen;

  @override
  Widget build(BuildContext context) {
    final dry = moisture < threshold;
    final color = dry ? const Color(0xFFD59015) : const Color(0xFF359C50);
    return Container(
      decoration: BoxDecoration(
        color: dry ? const Color(0xFFFFF8E8) : const Color(0xFFF2FAF1),
        border: Border.all(color: color.withOpacity(0.45), width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          Icon(
            Icons.sensors_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(height: 5),
          Text(
            '${moisture.round()}%',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            valveOpen ? 'Valve open' : 'Valve closed',
            style: const TextStyle(fontSize: 11, color: Color(0xFF626B65)),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.reading});

  final IrrigationReading reading;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          children: [
            _LegendRow(
              color: Color(0xFFD59015),
              title: 'Field A — valve ${reading.valveAOpen ? 'open' : 'closed'}',
            ),
            const Divider(height: 18),
            _LegendRow(
              color: Color(0xFF359C50),
              title: 'Field B — valve ${reading.valveBOpen ? 'open' : 'closed'}',
            ),
            const Divider(height: 18),
            _LegendRow(
              color: Color(0xFF438BD2),
              title:
                  'Shared pump — ${reading.pumpOn ? 'running' : 'standby'}',
            ),
          ],
        ),
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.title});

  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
          const Icon(Icons.chevron_right, color: Color(0xFF969E98), size: 18),
        ],
      );
}

class _FieldSelector extends StatelessWidget {
  const _FieldSelector({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: onTap == null ? null : (_) => onTap?.call(),
        selectedColor: const Color(0xFF438BD2),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF68716B),
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: const Color(0xFFEDEFEF),
        side: BorderSide.none,
      );
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF68716B), fontSize: 12)),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(note,
                style: const TextStyle(color: Color(0xFF68716B), fontSize: 11)),
          ],
        ),
      );
}

class _FieldUsageRow extends StatelessWidget {
  const _FieldUsageRow({
    required this.label,
    required this.usage,
    required this.total,
    required this.color,
  });

  final String label;
  final double? usage;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                usage == null ? 'No field data' : '${usage!.toStringAsFixed(1)} L',
                style: const TextStyle(
                    color: Color(0xFF68716B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: usage == null || total <= 0
                  ? 0
                  : (usage! / total).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: const Color(0xFFE7EAE8),
            ),
          ),
        ],
      );
}

class _EventList extends StatelessWidget {
  const _EventList({required this.repository, required this.title});

  final IrrigationRepository repository;
  final String title;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<IrrigationEvent>>(
        stream: repository.watchEvents(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Panel(
              child: Text('Could not load activity: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const _Panel(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final events = snapshot.data!;
          return _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 9),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No activity has been recorded yet.',
                      style: TextStyle(color: Color(0xFF68716B)),
                    ),
                  )
                else
                  for (var index = 0; index < events.length; index++) ...[
                    _EventRow(event: events[index]),
                    if (index < events.length - 1)
                      const Divider(height: 1, indent: 48),
                  ],
              ],
            ),
          );
        },
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final IrrigationEvent event;

  @override
  Widget build(BuildContext context) {
    final color = switch (event.type) {
      'watering' => const Color(0xFFD59015),
      'normal' => const Color(0xFF359C50),
      'reminder' => const Color(0xFF438BD2),
      _ => const Color(0xFF7A8690),
    };
    final icon = switch (event.type) {
      'watering' => Icons.water_drop_outlined,
      'normal' => Icons.check_circle_outline,
      'reminder' => Icons.build_outlined,
      _ => Icons.assessment_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  event.details,
                  style: const TextStyle(
                      color: Color(0xFF68716B), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dateTime) {
  final elapsed = DateTime.now().difference(dateTime);
  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} hr ago';
  return '${elapsed.inDays} d ago';
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_outlined, 'Dashboard'),
      (Icons.map_outlined, 'Map'),
      (Icons.schedule_outlined, 'History'),
      (Icons.settings_outlined, 'Settings'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5EAE6))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: InkWell(
                    onTap: () => onDestinationSelected(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[index].$1,
                          color: selectedIndex == index
                              ? const Color(0xFF438BD2)
                              : const Color(0xFF858585),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[index].$2,
                          style: TextStyle(
                            color: selectedIndex == index
                                ? const Color(0xFF438BD2)
                                : const Color(0xFF858585),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DryFieldAlert extends StatelessWidget {
  const _DryFieldAlert({
    required this.field,
    required this.valveOpen,
    required this.automaticMode,
  });

  final String field;
  final bool valveOpen;
  final bool automaticMode;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF2D9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFFB21A),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF855A0A),
                    height: 1.4,
                    fontSize: 14,
                  ),
                  children: [
                    TextSpan(
                      text: 'Field $field is dry. ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: valveOpen
                          ? automaticMode
                              ? 'Valve $field opened automatically.'
                              : 'Valve $field is open in manual mode.'
                          : 'Waiting for automatic irrigation.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.label,
    required this.moisture,
    required this.threshold,
  });

  final String label;
  final double moisture;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final dry = moisture < threshold;
    final color =
        dry ? const Color(0xFFFFB21A) : const Color(0xFF12B51E);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5EAE6)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF68716B), fontSize: 15),
          ),
          const SizedBox(height: 7),
          Text(
            '${moisture.round()}%',
            style: TextStyle(
              color: color,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (moisture / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: const Color(0xFFE7EAE8),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedPumpCard extends StatelessWidget {
  const _SharedPumpCard({
    required this.reading,
    required this.onValveChanged,
    this.onPumpChanged,
  });

  final IrrigationReading reading;
  final void Function(String valve, bool open) onValveChanged;
  final ValueChanged<bool>? onPumpChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5EAE6)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  color: reading.pumpOn
                      ? const Color(0xFF75B7FF)
                      : const Color(0xFF898989),
                  size: 23,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Shared pump — ${reading.pumpOn ? 'running' : 'standby'}',
                    style: const TextStyle(
                      color: Color(0xFF202722),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (reading.automaticMode)
                  const Text(
                    'AUTO',
                    style: TextStyle(
                      color: Color(0xFF75B7FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                if (!reading.automaticMode && onPumpChanged != null)
                  TextButton(
                    onPressed: () => onPumpChanged!(!reading.pumpOn),
                    child: Text(reading.pumpOn ? 'Stop' : 'Start'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE5EAE6)),
            _ValveRow(
              label: 'Valve A',
              isOpen: reading.valveAOpen,
              onTap: reading.automaticMode
                  ? null
                  : () => onValveChanged('A', !reading.valveAOpen),
            ),
            const Divider(height: 1, color: Color(0xFFE5EAE6)),
            _ValveRow(
              label: 'Valve B',
              isOpen: reading.valveBOpen,
              onTap: reading.automaticMode
                  ? null
                  : () => onValveChanged('B', !reading.valveBOpen),
            ),
          ],
        ),
      );
}

class _ValveRow extends StatelessWidget {
  const _ValveRow({
    required this.label,
    required this.isOpen,
    required this.onTap,
  });

  final String label;
  final bool isOpen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF202722), fontSize: 15),
              ),
            ),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFFFFF2D9)
                      : const Color(0xFFF5F6F5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isOpen
                        ? const Color(0xFFFFE2A9)
                        : const Color(0xFFE5EAE6),
                  ),
                ),
                child: Text(
                  isOpen ? 'Open' : 'Closed',
                  style: TextStyle(
                    color: isOpen
                        ? const Color(0xFFFFB21A)
                        : const Color(0xFF68716B),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SevenDayMoistureCard extends StatelessWidget {
  const _SevenDayMoistureCard({
    required this.repository,
    required this.threshold,
  });

  final IrrigationRepository repository;
  final double threshold;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MoistureSample>>(
        stream: repository.watchMoistureHistory(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Panel(
              child: Text(
                'Could not load moisture history: ${snapshot.error}',
                style: const TextStyle(color: Color(0xFFB44536)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _Panel(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final valuesByDay = <DateTime, List<double>>{};
          for (final sample in snapshot.data!) {
            final date = DateTime(
              sample.recordedAt.year,
              sample.recordedAt.month,
              sample.recordedAt.day,
            );
            if (date.isBefore(today.subtract(const Duration(days: 6))) ||
                date.isAfter(today)) {
              continue;
            }
            valuesByDay.putIfAbsent(date, () => []).add(sample.moisture);
          }
          final dailyValues = List.generate(7, (index) {
            final date = today.subtract(Duration(days: 6 - index));
            final values = valuesByDay[date];
            if (values == null || values.isEmpty) return null;
            return values.reduce((left, right) => left + right) / values.length;
          });
          return Container(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5EAE6)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Moisture — last 7 days',
                  style: TextStyle(
                    color: Color(0xFF202722),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 82,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var index = 0; index < dailyValues.length; index++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: dailyValues[index] == null
                                    ? 0.04
                                    : (dailyValues[index]! / 100)
                                        .clamp(0.08, 1.0)
                                        .toDouble(),
                                widthFactor: 0.86,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: dailyValues[index] == null
                                        ? const Color(0xFFE7EAE8)
                                        : dailyValues[index]! < threshold
                                            ? const Color(0xFFFFE3AC)
                                            : const Color(0xFFDDF1DD),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    for (var index = 0; index < 7; index++)
                      Expanded(
                        child: Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][
                              DateTime(now.year, now.month, now.day)
                                      .subtract(Duration(days: 6 - index))
                                      .weekday -
                                  1],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF858585),
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

class _WaterTodayCard extends StatelessWidget {
  const _WaterTodayCard({required this.reading});

  final IrrigationReading reading;

  @override
  Widget build(BuildContext context) => _Panel(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.water_drop_outlined, color: Color(0xFF75B7FF)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Water used today',
                style: TextStyle(color: Color(0xFF68716B)),
              ),
            ),
            Text(
              '${reading.waterToday.toStringAsFixed(1)} L',
              style: const TextStyle(
                color: Color(0xFF202722),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF202722),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF68716B), fontSize: 13)),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(children),
          ),
        ),
      ],
    );
  }
}

class _MoistureCard extends StatelessWidget {
  const _MoistureCard({required this.reading});

  final IrrigationReading reading;

  @override
  Widget build(BuildContext context) {
    final low = reading.moisture < reading.threshold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF183D32), Color(0xFF1A2923)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF315747)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded,
                  size: 18, color: Color(0xFF8AC9A9)),
              const SizedBox(width: 8),
              const Text('SOIL MOISTURE',
                  style: TextStyle(
                      letterSpacing: 1.1,
                      color: Color(0xFFB3C8BA),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: low
                      ? const Color(0xFF654A2A)
                      : const Color(0xFF254738),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  low ? 'Needs water' : 'Healthy',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          low ? const Color(0xFFFFD08A) : const Color(0xFF8EE3BC),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${reading.moisture.round()}',
                style: const TextStyle(
                    fontSize: 55,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 7, left: 3),
                child: Text('%',
                    style: TextStyle(
                        fontSize: 22,
                        color: Color(0xFFB3C8BA),
                        fontWeight: FontWeight.w500)),
              ),
              const Spacer(),
              const Icon(Icons.eco_rounded,
                  color: Color(0xFF56D9A4), size: 40),
            ],
          ),
          const SizedBox(height: 17),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
            value: (reading.moisture / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: const Color(0xFF34453D),
              color: const Color(0xFF42D69D),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Dry',
                  style: TextStyle(color: Color(0xFF91A69A), fontSize: 11)),
              Text('Target ${reading.threshold.round()}%',
                  style: const TextStyle(
                      color: Color(0xFFC4D3C9), fontSize: 11)),
              const Text('Saturated',
                  style: TextStyle(color: Color(0xFF91A69A), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.footnote,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String footnote;
  final Color color;

  @override
  Widget build(BuildContext context) => _Panel(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(height: 13),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF91A198),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 3),
            Text(footnote,
                style: const TextStyle(
                    color: Color(0xFF68716B), fontSize: 11)),
          ],
        ),
      );
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.reading,
    required this.threshold,
    required this.onThresholdChanged,
    required this.onThresholdChangeEnd,
    required this.onModeChanged,
    required this.onPumpChanged,
  });

  final IrrigationReading reading;
  final double threshold;
  final ValueChanged<double> onThresholdChanged;
  final ValueChanged<double> onThresholdChangeEnd;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<bool> onPumpChanged;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Irrigation control',
                style: TextStyle(
                    color: Color(0xFF202722),
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.auto_mode_rounded,
                    color: Color(0xFF438BD2), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Automatic watering',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('Water when soil drops below target',
                          style: TextStyle(
                              color: Color(0xFF68716B), fontSize: 11)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: reading.automaticMode,
                  onChanged: onModeChanged,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _ThinDivider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('Moisture threshold',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('${threshold.round()}%',
                    style: const TextStyle(
                        color: Color(0xFF438BD2),
                        fontWeight: FontWeight.w700)),
              ],
            ),
            Slider(
              value: threshold.clamp(10, 80).toDouble(),
              min: 10,
              max: 80,
              divisions: 70,
              onChanged: onThresholdChanged,
              onChangeEnd: onThresholdChangeEnd,
            ),
            Row(
              children: [
                const Expanded(
                  child: Text('Manual pump override',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                FilledButton.tonalIcon(
                  onPressed: reading.automaticMode
                      ? null
                      : () => onPumpChanged(!reading.pumpOn),
                  icon: Icon(reading.pumpOn
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(reading.pumpOn ? 'Stop pump' : 'Start pump'),
                ),
              ],
            ),
            if (reading.automaticMode)
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Text('Switch to manual mode to override the pump.',
                    style: TextStyle(
                        color: Color(0xFF68716B), fontSize: 11)),
              ),
          ],
        ),
      );
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.reading, this.expanded = false});

  final IrrigationReading reading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final saved = reading.waterSavedPerDay;
    final saving = saved >= 0;
    final percentSaved = reading.waterSavedPercent;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined,
                  color: Color(0xFF359C50), size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  saving ? 'Water saved' : 'Water use increase',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                percentSaved == null
                    ? 'No baseline'
                    : '${percentSaved.abs()}% ${saving ? 'less' : 'more'}',
                style: TextStyle(
                  color: saving
                      ? const Color(0xFF359C50)
                      : const Color(0xFFB44536),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${saved.abs().toStringAsFixed(1)}',
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800)),
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 5),
                child: Text(
                  saving ? 'L / day saved' : 'L / day extra',
                  style: const TextStyle(color: Color(0xFF68716B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _CompareBar(
            label: 'Before',
            value: reading.baselineWater,
            max: math
                .max(reading.baselineWater, reading.automatedWater)
                .toDouble(),
            color: const Color(0xFF9AA59D),
          ),
          const SizedBox(height: 9),
          _CompareBar(
            label: 'After',
            value: reading.automatedWater,
            max: math
                .max(reading.baselineWater, reading.automatedWater)
                .toDouble(),
            color: const Color(0xFF4F9E69),
          ),
          if (expanded) ...[
            const SizedBox(height: 13),
            Text(
              'Baseline ${reading.baselineWater.toStringAsFixed(1)} L/day  ·  '
              'Automated ${reading.automatedWater.toStringAsFixed(1)} L/day',
              style: const TextStyle(
                  color: Color(0xFF68716B), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final double value;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF68716B), fontSize: 11)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : (value / max).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: const Color(0xFFE7EAE8),
                color: color,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text('${value.toStringAsFixed(0)} L',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    color: Color(0xFF202722),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

class _MoistureHistoryCard extends StatelessWidget {
  const _MoistureHistoryCard({
    required this.repository,
    this.field = 'A',
  });

  final IrrigationRepository repository;
  final String field;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MoistureSample>>(
        stream: repository.watchMoistureHistory(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Panel(
              child: Text(
                'Could not load moisture history: ${snapshot.error}',
                style: const TextStyle(color: Color(0xFFB44536)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _Panel(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final samples = snapshot.data!;
          if (samples.isEmpty) {
            return const _Panel(
              child: Text(
                'No moisture history yet. The device will add readings as it samples the soil.',
                style: TextStyle(color: Color(0xFF68716B), height: 1.5),
              ),
            );
          }
          return _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Soil moisture history',
                  style: TextStyle(
                      color: Color(0xFF202722),
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Sensor readings · past 7 days',
                  style: TextStyle(color: Color(0xFF68716B), fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: CustomPaint(
                    painter:
                        _MoistureHistoryPainter(samples: samples, field: field),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatSampleTime(samples.last.recordedAt),
                      style: const TextStyle(
                          color: Color(0xFF68716B), fontSize: 11),
                    ),
                    Text(
                      '${_sampleMoisture(samples.first, field).round()}% latest',
                      style: const TextStyle(
                        color: Color(0xFF359C50),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

String _formatSampleTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

class _MoistureHistoryPainter extends CustomPainter {
  const _MoistureHistoryPainter({required this.samples, required this.field});

  final List<MoistureSample> samples;
  final String field;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalPadding = 4.0;
    const verticalPadding = 8.0;
    final chartWidth = size.width - horizontalPadding * 2;
    final chartHeight = size.height - verticalPadding * 2;
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E6E1)
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = verticalPadding + chartHeight * i / 2;
      canvas.drawLine(
        Offset(horizontalPadding, y),
        Offset(size.width - horizontalPadding, y),
        gridPaint,
      );
    }
    if (samples.length == 1) {
      final point = Offset(
        size.width / 2,
        verticalPadding +
            chartHeight *
                (1 - _sampleMoisture(samples.first, field).clamp(0, 100) / 100),
      );
      canvas.drawCircle(
        point,
        4,
        Paint()..color = const Color(0xFF31D3A0),
      );
      return;
    }
    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      final x = horizontalPadding +
          chartWidth * index / (samples.length - 1);
      final moisture = _sampleMoisture(
        samples[samples.length - 1 - index],
        field,
      )
          .clamp(0, 100)
          .toDouble();
      final y = verticalPadding + chartHeight * (1 - moisture / 100);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF438BD2)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MoistureHistoryPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.field != field;
}

double _sampleMoisture(MoistureSample sample, String field) =>
    field == 'B' ? sample.fieldBMoisture ?? sample.moisture : sample.moisture;

class _UsageChart extends StatelessWidget {
  const _UsageChart({required this.before, required this.after});

  final double before;
  final double after;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _UsageChartPainter(before: before, after: after),
        child: const SizedBox.expand(),
      );
}

class _UsageChartPainter extends CustomPainter {
  const _UsageChartPainter({required this.before, required this.after});

  final double before;
  final double after;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 24.0;
    final chartHeight = size.height - bottom;
    final chartWidth = size.width - left - 8;
    final maxValue = math.max(1, math.max(before, after) * 1.18);
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E6E1)
      ..strokeWidth = 1;
    final textStyle = const TextStyle(
        color: Color(0xFF68716B), fontSize: 10, fontFamily: 'Roboto');
    for (var i = 0; i < 4; i++) {
      final y = chartHeight - i * chartHeight / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final label = TextPainter(
        text: TextSpan(
          text: '${(maxValue * i / 3).round()}',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 6));
    }
    final barWidth = math.min(42.0, chartWidth / 4).toDouble();
    final gap = chartWidth / 4;
    final bars = [
      (before, 1.2, const Color(0xFF46534D), 'Before'),
      (after, 2.5, const Color(0xFF31D3A0), 'After'),
    ];
    for (final (value, position, color, label) in bars) {
      final x = left + gap * position - barWidth / 2;
      final barHeight =
          chartHeight * (value / maxValue).clamp(0, 1).toDouble();
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(7),
      );
      canvas.drawRRect(rect, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(x + barWidth / 2 - text.width / 2, chartHeight + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _UsageChartPainter oldDelegate) =>
      before != oldDelegate.before || after != oldDelegate.after;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF68716B), fontSize: 11)),
        ],
      );
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.isDemo});

  final bool isDemo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE5EAE6)),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: Color(0xFF31D3A0), shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(isDemo ? 'DEMO' : 'LIVE',
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: Color(0xFF68716B)))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Color(0xFFE5EAE6));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5EAE6)),
        ),
        child: child,
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 36, color: Color(0xFFFFB77A)),
              const SizedBox(height: 14),
              const Text('Can’t reach the irrigation system',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF68716B), fontSize: 12)),
            ],
          ),
        ),
      );
}
