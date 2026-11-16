import 'package:flutter/material.dart';

import 'models/survey.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/survey_screen.dart';
import 'services/api_service.dart';
import 'services/local_database_service.dart';
import 'services/location_service.dart';

void main() => runApp(TopoSurveyApp.local());

class TopoSurveyApp extends StatelessWidget {
  const TopoSurveyApp({
    super.key,
    this.location = const LocationService(),
    this.checkBackend,
    this.loadSurveys,
    this.loadSurvey,
    this.saveSurvey,
    this.deleteSurvey,
  });

  factory TopoSurveyApp.local({
    LocalDatabaseService? database,
    LocationService location = const LocationService(),
  }) {
    final storage = database ?? LocalDatabaseService();
    return TopoSurveyApp(
      location: location,
      loadSurveys: storage.loadSurveys,
      loadSurvey: storage.loadSurvey,
      saveSurvey: storage.saveSurvey,
      deleteSurvey: storage.deleteSurvey,
    );
  }

  factory TopoSurveyApp.connected({
    required ApiService api,
    LocationService location = const LocationService(),
  }) => TopoSurveyApp(
    location: location,
    checkBackend: api.checkHealth,
    loadSurveys: api.loadSurveys,
    loadSurvey: api.loadSurvey,
    saveSurvey: api.saveSurvey,
    deleteSurvey: api.deleteSurvey,
  );

  final LocationService location;
  final Future<void> Function()? checkBackend;
  final Future<List<Survey>> Function()? loadSurveys;
  final Future<Survey> Function(int)? loadSurvey;
  final Future<Survey> Function(SurveyMeasurement)? saveSurvey;
  final Future<void> Function(int)? deleteSurvey;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF166534);
    const accent = Color(0xFFDCFCE7);
    const background = Color(0xFFF8FAFC);
    const ink = Color(0xFF0F172A);
    const secondary = Color(0xFF64748B);
    const border = Color(0xFFE2E8F0);
    final colors = ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: accent,
      onPrimaryContainer: primary,
      surface: Colors.white,
      onSurface: ink,
      onSurfaceVariant: secondary,
      outlineVariant: border,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonSize = Size(0, 48);

    return MaterialApp(
      title: 'TopoSurvey',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: colors,
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: ink,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: ink,
            fontSize: 22,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w700,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: accent,
          elevation: 0,
        ),
        dividerColor: border,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: buttonSize,
            shape: buttonShape,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: buttonSize,
            shape: buttonShape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: buttonSize,
            shape: buttonShape,
          ),
        ),
        dialogTheme: DialogThemeData(shape: buttonShape),
      ),
      home: _SurveyTabs(
        location: location,
        checkBackend: checkBackend,
        loadSurveys: loadSurveys,
        loadSurvey: loadSurvey,
        saveSurvey: saveSurvey,
        deleteSurvey: deleteSurvey,
      ),
    );
  }
}

class _SurveyTabs extends StatefulWidget {
  const _SurveyTabs({
    required this.location,
    required this.checkBackend,
    required this.loadSurveys,
    required this.loadSurvey,
    required this.saveSurvey,
    required this.deleteSurvey,
  });

  final LocationService location;
  final Future<void> Function()? checkBackend;
  final Future<List<Survey>> Function()? loadSurveys;
  final Future<Survey> Function(int)? loadSurvey;
  final Future<Survey> Function(SurveyMeasurement)? saveSurvey;
  final Future<void> Function(int)? deleteSurvey;

  @override
  State<_SurveyTabs> createState() => _SurveyTabsState();
}

class _SurveyTabsState extends State<_SurveyTabs> {
  int _selected = 0;
  Future<List<Survey>>? _history;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
  }

  Future<List<Survey>>? _loadHistory() {
    final load = widget.loadSurveys;
    return load == null ? null : Future.sync(load);
  }

  void _reload() {
    final history = _loadHistory();
    setState(() {
      _history = history;
    });
  }

  Future<Survey> _save(SurveyMeasurement measurement) async {
    if (_saving) throw const ApiException('Penyimpanan masih berlangsung.');
    setState(() => _saving = true);
    try {
      return await widget.saveSurvey!(measurement);
    } finally {
      if (mounted) {
        final history = _loadHistory();
        setState(() {
          _saving = false;
          _history = history;
        });
      }
    }
  }

  Future<void> _delete(int id) async {
    try {
      await widget.deleteSurvey!(id);
    } finally {
      if (mounted) _reload();
    }
  }

  void _select(int index) => setState(() => _selected = index);

  @override
  Widget build(BuildContext context) {
    const titles = ['TopoSurvey', 'Survei', 'Riwayat'];
    return PopScope(
      canPop: _selected == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected != 0) _select(0);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(titles[_selected])),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: FutureBuilder<List<Survey>>(
                future: _history,
                builder: (context, snapshot) => switch (_selected) {
                  0 => HomeScreen(
                    location: widget.location,
                    checkBackend: widget.checkBackend,
                    surveyCount:
                        snapshot.connectionState == ConnectionState.done
                        ? snapshot.data?.length
                        : null,
                    onStart: () => _select(1),
                    onHistory: () => _select(2),
                    onReload: _reload,
                    historyUnavailable: snapshot.hasError,
                    historyLoading:
                        snapshot.connectionState == ConnectionState.waiting,
                  ),
                  1 => SurveyScreen(
                    location: widget.location,
                    savedSurveys: snapshot.data ?? const [],
                    isSaving: _saving,
                    storageUnavailable: snapshot.hasError,
                    onSave: widget.saveSurvey == null ? null : _save,
                  ),
                  _ => HistoryScreen(
                    snapshot: snapshot,
                    onStart: () => _select(1),
                    onReload: _reload,
                    loadDetail: widget.loadSurvey,
                    onDelete: widget.deleteSurvey == null ? null : _delete,
                  ),
                },
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Beranda',
            ),
            NavigationDestination(
              icon: Icon(Icons.my_location_outlined),
              selectedIcon: Icon(Icons.my_location),
              label: 'Survei',
            ),
            NavigationDestination(icon: Icon(Icons.history), label: 'Riwayat'),
          ],
        ),
      ),
    );
  }
}
