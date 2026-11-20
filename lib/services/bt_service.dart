import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Handles the Bluetooth SPP connection, the protocol parser and app state.
class BtService extends ChangeNotifier {
  BluetoothConnection? _conn;
  StreamSubscription<Uint8List>? _sub;
  Timer? _pollTimer;
  String _buffer = '';

  BluetoothDevice? device;
  bool connecting = false;
  bool connected = false;
  String? error;

  // Device state (updated from incoming data)
  bool lamp = false;
  bool plug = false;
  bool alarm = false;
  bool? doorOpen; // null = unknown
  double? temperature;
  int? limit;
  DateTime? lastUpdate;

  // Auto polling
  bool autoPoll = true;
  static const pollInterval = Duration(seconds: 3);

  // Raw log (handy for debugging / demo)
  final List<String> log = [];

  void _log(String s) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    log.insert(0, '$ts $s');
    if (log.length > 100) log.removeLast();
  }

  //
  // Connection
  //
  Future<bool> connect(BluetoothDevice d) async {
    if (connecting) return false;
    await disconnect();

    connecting = true;
    error = null;
    device = d;
    notifyListeners();

    try {
      _conn = await BluetoothConnection.toAddress(d.address)
          .timeout(const Duration(seconds: 15));
      connected = true;
      _buffer = '';
      _log('Connected to ${d.name ?? d.address}');

      _sub = _conn!.input!.listen(
        _onData,
        onDone: _handleRemoteClose,
        onError: (_) => _handleRemoteClose(),
        cancelOnError: true,
      );

      connecting = false;
      notifyListeners();

      await requestStatus();
      _restartPolling();
      return true;
    } catch (e) {
      connecting = false;
      connected = false;
      error = 'Connection failed. Make sure the module is powered and paired.';
      _log('Connect error: $e');
      notifyListeners();
      return false;
    }
  }

  void _handleRemoteClose() {
    _log('Connection closed');
    _cleanup();
    notifyListeners();
  }

  Future<void> disconnect() async {
    _cleanup();
    notifyListeners();
  }

  void _cleanup() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _conn?.dispose();
    } catch (_) {}
    _conn = null;
    connected = false;
    connecting = false;
  }

  //
  // Polling
  //
  void setAutoPoll(bool v) {
    autoPoll = v;
    _restartPolling();
    notifyListeners();
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (autoPoll && connected) {
      _pollTimer = Timer.periodic(pollInterval, (_) => requestStatus());
    }
  }

  //
  // Sending
  //
  Future<void> _send(String cmd) async {
    if (!connected || _conn == null) return;
    try {
      _conn!.output.add(Uint8List.fromList(ascii.encode('$cmd\r\n')));
      await _conn!.output.allSent;
      _log('TX: $cmd');
    } catch (e) {
      _log('TX error: $e');
      _handleRemoteClose();
    }
  }

  Future<void> setLamp(bool on) => _send('LAMP:${on ? 1 : 0}');
  Future<void> setPlug(bool on) => _send('PLUG:${on ? 1 : 0}');
  Future<void> setLimit(int value) => _send('LIMIT:$value');
  Future<void> requestStatus() => _send('STATUS?');

  //
  // Receiving + parsing
  //
  void _onData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);

    // Split on \n; the last element is an incomplete line, so keep it buffered.
    final parts = _buffer.split('\n');
    _buffer = parts.removeLast();

    var changed = false;
    for (final raw in parts) {
      final line = raw.trim(); // removes \r and extra whitespace
      if (line.isEmpty) continue;
      _log('RX: $line');
      if (_parseLine(line)) {
        changed = true;
      }
    }

    if (changed) {
      lastUpdate = DateTime.now();
      notifyListeners();
    }

    // Guard against garbage without a newline
    if (_buffer.length > 512) _buffer = '';
  }

  bool _parseLine(String line) {
    var l = line.trim();
    if (l.toUpperCase().startsWith('ACK:')) {
      l = l.substring(4).trim();
    }

    // Full status line: "LAMP:0, PLUG:0, DOOR:CLOSED, TEMP:27.5, ALARM:0"
    var changed = false;
    for (final token in l.split(',')) {
      if (_applyKeyValue(token.trim())) {
        changed = true;
      }
    }
    return changed;
  }

  bool _applyKeyValue(String token) {
    final idx = token.indexOf(':');
    if (idx <= 0) return false;

    final key = token.substring(0, idx).trim().toUpperCase();
    final val = token.substring(idx + 1).trim();

    switch (key) {
      case 'LAMP':
        lamp = val == '1' || val.toUpperCase() == 'ON';
        return true;
      case 'PLUG':
        plug = val == '1' || val.toUpperCase() == 'ON';
        return true;
      case 'ALARM':
        alarm = val == '1' || val.toUpperCase() == 'ON';
        return true;
      case 'DOOR':
        doorOpen = val.toUpperCase() == 'OPEN';
        return true;
      case 'TEMP':
        final t = double.tryParse(val);
        if (t == null) return false;
        temperature = t;
        return true;
      case 'LIMIT':
        final n = int.tryParse(val) ?? double.tryParse(val)?.round();
        if (n == null) return false;
        limit = n;
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}