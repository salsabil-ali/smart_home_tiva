import 'package:flutter/material.dart';
import '../main.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;
  double _limit = 30;
  bool _limitInitialised = false;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: btService,
      builder: (context, _) {
        final s = btService;

        // Sync the slider with the limit reported by the device (first time only)
        if (!_limitInitialised && s.limit != null) {
          _limit = s.limit!.toDouble().clamp(20, 60);
          _limitInitialised = true;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Smart Home'),
            actions: [
              IconButton(
                tooltip: 'Refresh status',
                onPressed: s.connected ? s.requestStatus : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Disconnect',
                onPressed: () async {
                  await s.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.link_off_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusBar(s),
              const SizedBox(height: 12),
              if (s.alarm) _alarmBanner(),
              if (s.alarm) const SizedBox(height: 12),
              _sensorRow(s),
              const SizedBox(height: 12),
              _controlCard(
                icon: Icons.lightbulb_rounded,
                color: Colors.amber,
                title: 'Lamp',
                value: s.lamp,
                enabled: s.connected,
                onChanged: s.setLamp,
              ),
              const SizedBox(height: 12),
              _controlCard(
                icon: Icons.power_rounded,
                color: Colors.lightGreenAccent,
                title: 'Plug / Socket',
                value: s.plug,
                enabled: s.connected,
                onChanged: s.setPlug,
              ),
              const SizedBox(height: 12),
              _limitCard(s),
              const SizedBox(height: 12),
              _pollCard(s),
              const SizedBox(height: 12),
              _logCard(s),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBar(dynamic s) {
    final connected = s.connected as bool;
    final color = connected ? Colors.greenAccent : Colors.redAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'Connected' : 'Disconnected',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    s.device?.name ?? s.device?.address ?? '-',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            if (!connected)
              FilledButton(
                onPressed:
                    s.device == null ? null : () => s.connect(s.device!),
                child: Text(s.connecting ? 'Connecting...' : 'Reconnect'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _alarmBanner() {
    return AnimatedBuilder(
      animation: _flash,
      builder: (_, _) {
        final c = Color.lerp(
          Colors.red.shade900,
          Colors.red.shade400,
          _flash.value,
        )!;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(.5 * _flash.value),
                blurRadius: 24,
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 36, color: Colors.white),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'ALARM! Temperature limit exceeded or security event detected.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sensorRow(dynamic s) {
    final temp = s.temperature as double?;
    final door = s.doorOpen as bool?;
    final overLimit =
        temp != null && s.limit != null && temp > (s.limit as int);

    return Row(
      children: [
        Expanded(
          child: _infoCard(
            icon: Icons.thermostat_rounded,
            color: overLimit ? Colors.redAccent : Colors.orangeAccent,
            label: 'Temperature',
            value: temp == null ? '--' : '${temp.toStringAsFixed(1)} °C',
            sub: s.limit == null ? null : 'Limit ${s.limit} °C',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            icon: door == true
                ? Icons.meeting_room_rounded
                : Icons.door_front_door_rounded,
            color: door == true ? Colors.redAccent : Colors.lightBlueAccent,
            label: 'Door',
            value: door == null ? '--' : (door ? 'OPEN' : 'CLOSED'),
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? sub,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (sub != null)
              Text(sub, style: const TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _controlCard({
    required IconData icon,
    required Color color,
    required String title,
    required bool value,
    required bool enabled,
    required Future<void> Function(bool) onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: value ? color.withOpacity(.2) : Colors.white10,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: value ? color : Colors.white38),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value ? 'ON' : 'OFF',
                    style: TextStyle(color: value ? color : Colors.white38),
                  ),
                ],
              ),
            ),
            // The switch reflects the state confirmed by the microcontroller (ACK / STATUS).
            Switch(
              value: value,
              onChanged: enabled ? (v) => onChanged(v) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitCard(dynamic s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, color: Colors.purpleAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Temperature limit',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_limit.round()} °C',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              value: _limit,
              min: 20,
              max: 60,
              divisions: 40,
              label: '${_limit.round()} °C',
              onChanged: (v) => setState(() => _limit = v),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed:
                    s.connected ? () => s.setLimit(_limit.round()) : null,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send limit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pollCard(dynamic s) {
    final last = s.lastUpdate as DateTime?;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.sync_rounded),
        title: const Text('Auto-refresh status (every 3 s)'),
        subtitle: Text(
          last == null
              ? 'No data received yet'
              : 'Last update: ${last.toIso8601String().substring(11, 19)}',
        ),
        value: s.autoPoll,
        onChanged: s.setAutoPoll,
      ),
    );
  }

  Widget _logCard(dynamic s) {
    final lines = (s.log as List<String>).take(8).toList();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.terminal_rounded),
        title: const Text('Serial monitor'),
        shape: const Border(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lines.isEmpty ? 'No traffic yet' : lines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}