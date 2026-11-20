import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import 'dashboard_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final FlutterBluetoothSerial _bt = FlutterBluetoothSerial.instance;
  List<BluetoothDevice> _bonded = [];
  final List<BluetoothDiscoveryResult> _found = [];
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;
  bool _scanning = false;
  bool _btOn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ensurePermissions();
    final state = await _bt.state;
    _btOn = state == BluetoothState.STATE_ON;
    if (mounted) setState(() {});
    if (_btOn) await _loadBonded();
  }

  Future<bool> _ensurePermissions() async {
    final result = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final ok = result.values.every((s) => s.isGranted || s.isLimited) ||
        // On Android <= 11 the bluetoothScan/Connect permissions report as denied/restricted.
        (result[Permission.locationWhenInUse]?.isGranted ?? false);

    if (!ok && mounted) {
      _snack('Bluetooth and Location permissions are required.');
    }
    return ok;
  }

  Future<void> _enableBluetooth() async {
    final on = await _bt.requestEnable() ?? false;
    if (!mounted) return;
    setState(() => _btOn = on);
    if (on) await _loadBonded();
  }

  Future<void> _loadBonded() async {
    final list = await _bt.getBondedDevices();
    if (mounted) {
      setState(() => _bonded = list);
    }
  }

  Future<void> _startScan() async {
    if (!_btOn) {
      await _enableBluetooth();
      if (!_btOn) return;
    }
    if (!await _ensurePermissions()) return;

    setState(() {
      _found.clear();
      _scanning = true;
    });

    await _discoverySub?.cancel();
    _discoverySub = _bt.startDiscovery().listen(
      (r) {
        final idx = _found.indexWhere((e) => e.device.address == r.device.address);
        if (!mounted) return;
        setState(() {
          if (idx >= 0) {
            _found[idx] = r;
          } else {
            _found.add(r);
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _stopScan() async {
    await _discoverySub?.cancel();
    await _bt.cancelDiscovery();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_scanning) await _stopScan();

    // Pair first if needed (system dialog will ask for PIN: usually 1234 or 0000).
    var d = device;
    if (!d.isBonded) {
      final bonded = await _bt.bondDeviceAtAddress(d.address) ?? false;
      if (!bonded) {
        _snack('Pairing failed or was cancelled.');
        return;
      }
      await _loadBonded();
      final matched = _bonded.where((item) => item.address == d.address).toList();
      if (matched.isNotEmpty) {
        d = matched.first;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final ok = await btService.connect(d);
    if (!mounted) return;
    Navigator.of(context).pop(); // close loader

    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      _snack(btService.error ?? 'Could not connect.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _bt.cancelDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Device'),
        actions: [
          ListenableBuilder(
            listenable: btService,
            builder: (_, _) => btService.connected
                ? TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DashboardScreen()),
                    ),
                    icon: const Icon(Icons.dashboard_rounded),
                    label: const Text('Dashboard'),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? _stopScan : _startScan,
        icon: Icon(_scanning ? Icons.stop_rounded : Icons.bluetooth_searching),
        label: Text(_scanning ? 'Stop' : 'Scan'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadBonded,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (!_btOn)
              Card(
                color: cs.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.bluetooth_disabled,
                    color: cs.onErrorContainer,
                  ),
                  title: Text(
                    'Bluetooth is off',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                  trailing: FilledButton(
                    onPressed: _enableBluetooth,
                    child: const Text('Enable'),
                  ),
                ),
              ),
            _header('Paired devices'),
            if (_bonded.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No paired devices. Tap Scan to find your HC-05/HC-06.',
                ),
              ),
            ..._bonded.map((d) => _deviceTile(d, null)),
            _header('Discovered devices${_scanning ? ' (scanning...)' : ''}'),
            if (_scanning) const LinearProgressIndicator(),
            ..._found
                .where((r) => !_bonded.any((b) => b.address == r.device.address))
                .map((r) => _deviceTile(r.device, r.rssi)),
          ],
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          t,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.white60, letterSpacing: 1),
        ),
      );

  Widget _deviceTile(BluetoothDevice d, int? rssi) {
    final isCurrent =
        btService.connected && btService.device?.address == d.address;
    final looksLikeHc = (d.name ?? '').toUpperCase().startsWith('HC-');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              looksLikeHc ? Colors.blue.withOpacity(.2) : Colors.white10,
          child: Icon(
            Icons.bluetooth,
            color: looksLikeHc ? Colors.lightBlueAccent : Colors.white54,
          ),
        ),
        title: Text(
          (d.name?.isNotEmpty ?? false) ? d.name! : 'Unknown device',
        ),
        subtitle: Text(
          '${d.address}${rssi != null ? ' • $rssi dBm' : ''}',
        ),
        trailing: isCurrent
            ? const Chip(label: Text('Connected'))
            : FilledButton.tonal(
                onPressed: () => _connect(d),
                child: Text(d.isBonded ? 'Connect' : 'Pair'),
              ),
      ),
    );
  }
}