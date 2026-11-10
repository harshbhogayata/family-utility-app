import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/qr/qr_generator.dart';
import '../../engines/records/wifi_devices.dart';
import '../../engines/share/share_engine.dart';

/// Feature 097 — router passwords as a Wi-Fi QR, and the devices in the
/// house with serial numbers and purchase dates.
class WifiDevicesScreen extends StatefulWidget {
  const WifiDevicesScreen({super.key, this.book, this.share, this.save, this.today});

  final WifiDevicesBook? book;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;
  final DateTime Function()? today;

  @override
  State<WifiDevicesScreen> createState() => _WifiDevicesScreenState();
}

class _WifiDevicesScreenState extends State<WifiDevicesScreen> {
  WifiDevicesBook get _b => widget.book ?? WifiDevicesBook.instance;
  final Set<String> _shown = <String>{};

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _shareText(String text) async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(text);
      return;
    }
    await ShareEngine.instance.shareText(text);
  }

  static Future<String?> _saveToDocuments(String text, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_b.toText(), 'Wi-Fi and devices.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where (passwords left out)');
  }

  static DateTime? parseDay(String s) {
    final RegExpMatch? m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$').firstMatch(s);
    if (m == null) {
      return null;
    }
    final int d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    final DateTime out = DateTime(y, mo, d);
    return out.month == mo && out.day == d ? out : null;
  }

  Future<void> _addNetwork() async {
    final TextEditingController ssid = TextEditingController();
    final TextEditingController pass = TextEditingController();
    final TextEditingController where = TextEditingController();
    WifiAuth auth = WifiAuth.wpa;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a Wi-Fi network'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(key: const Key('wifi-ssid'), controller: ssid, decoration: const InputDecoration(labelText: 'Network name')),
                DropdownButtonFormField<WifiAuth>(
                  key: const Key('wifi-auth'),
                  initialValue: auth,
                  decoration: const InputDecoration(labelText: 'Security'),
                  items: <DropdownMenuItem<WifiAuth>>[
                    for (final WifiAuth a in WifiAuth.values) DropdownMenuItem<WifiAuth>(value: a, child: Text(WifiDevicesBook.authLabel(a))),
                  ],
                  onChanged: (WifiAuth? v) => set(() => auth = v ?? auth),
                ),
                if (auth != WifiAuth.open)
                  TextField(key: const Key('wifi-password'), controller: pass, decoration: const InputDecoration(labelText: 'Password')),
                TextField(key: const Key('wifi-where'), controller: where, decoration: const InputDecoration(labelText: 'Where (optional)', hintText: 'Home, Guest')),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('wifi-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final WifiNetwork? n = await _b.saveNetwork(ssid: ssid.text, password: pass.text, auth: auth, where: where.text);
    _snack(n == null ? 'Type the network name and password' : 'Added ${n.ssid}');
  }

  Future<void> _addDevice() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController model = TextEditingController();
    final TextEditingController serial = TextEditingController();
    final TextEditingController bought = TextEditingController();
    String? net;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a device'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(key: const Key('device-name'), controller: name, decoration: const InputDecoration(labelText: 'Device', hintText: 'Living room TV')),
                TextField(key: const Key('device-model'), controller: model, decoration: const InputDecoration(labelText: 'Make and model (optional)')),
                TextField(key: const Key('device-serial'), controller: serial, decoration: const InputDecoration(labelText: 'Serial number (optional)')),
                TextField(
                  key: const Key('device-bought'),
                  controller: bought,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Bought on (optional)', hintText: '05/12/2026'),
                ),
                if (_b.networks.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    key: const Key('device-network'),
                    initialValue: net,
                    decoration: const InputDecoration(labelText: 'Connected to'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('Not on Wi-Fi')),
                      for (final WifiNetwork n in _b.networks) DropdownMenuItem<String?>(value: n.id, child: Text(n.ssid)),
                    ],
                    onChanged: (String? v) => set(() => net = v),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('device-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? on = bought.text.trim().isEmpty ? null : parseDay(bought.text);
    final HomeDevice? d = bought.text.trim().isNotEmpty && on == null
        ? null
        : await _b.saveDevice(
            name: name.text,
            model: model.text,
            serial: serial.text,
            bought: on,
            networkId: net,
            today: (widget.today ?? DateTime.now)(),
          );
    _snack(d == null ? 'Type the device name, and the date like 05/12/2026' : 'Added ${d.name}');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wi-Fi and devices'),
          bottom: const TabBar(tabs: <Widget>[Tab(key: Key('tab-wifi'), text: 'Wi-Fi'), Tab(key: Key('tab-devices'), text: 'Devices')]),
        ),
        floatingActionButton: Builder(
          builder: (BuildContext context) => FloatingActionButton.extended(
            key: const Key('wifi-devices-add'),
            onPressed: () => unawaited(DefaultTabController.of(context).index == 0 ? _addNetwork() : _addDevice()),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
        bottomNavigationBar: ResultBar(
          onShare: () => unawaited(_shareText(_b.toText())),
          onSave: () => unawaited(_save()),
          onUndo: () => unawaited(_b.undo().then((bool ok) => _snack(ok ? 'Undone' : 'Nothing to undo'))),
        ),
        body: ListenableBuilder(
          listenable: _b,
          builder: (BuildContext context, Widget? _) => TabBarView(children: <Widget>[_networks(context), _devices(context)]),
        ),
      ),
    );
  }

  Widget _networks(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    if (_b.networks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No networks yet. Add your router name and password to show guests a QR code to join.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        for (final WifiNetwork n in _b.networks)
          Card(
            key: Key('wifi-${n.id}'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${n.ssid}${n.where.isEmpty ? '' : ' · ${n.where}'}', style: text.titleMedium),
                  Text(
                    _shown.contains(n.id) || n.auth == WifiAuth.open
                        ? '${WifiDevicesBook.authLabel(n.auth)}${n.password.isEmpty ? '' : ' · ${n.password}'}'
                        : '${WifiDevicesBook.authLabel(n.auth)} · ••••••••',
                    key: Key('wifi-pass-${n.id}'),
                    style: text.bodyMedium,
                  ),
                  if (_b.devicesOn(n.id).isNotEmpty)
                    Text('Connected: ${_b.devicesOn(n.id).map((HomeDevice d) => d.name).join(', ')}', style: text.bodySmall),
                  if (_shown.contains(n.id))
                    Center(
                      child: Semantics(
                        label: 'QR code to join ${n.ssid}',
                        image: true,
                        excludeSemantics: true,
                        child: Container(
                          key: Key('wifi-qr-${n.id}'),
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(data: n.qrData, size: 220),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      TextButton.icon(
                        key: Key('wifi-show-${n.id}'),
                        style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                        onPressed: () => setState(() {
                          if (!_shown.remove(n.id)) {
                            _shown.add(n.id);
                          }
                        }),
                        icon: Icon(_shown.contains(n.id) ? Icons.visibility_off_outlined : Icons.qr_code_2),
                        label: Text(_shown.contains(n.id) ? 'Hide' : 'Show QR and password'),
                      ),
                      TextButton.icon(
                        key: Key('wifi-delete-${n.id}'),
                        style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                        onPressed: () => unawaited(_b.removeNetwork(n.id)),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _devices(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<HomeDevice> list = _b.devices;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No devices yet. Add the TV, router, AC or laptop with its serial number and purchase date.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        for (final HomeDevice d in list)
          Card(
            key: Key('device-${d.id}'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(d.name, style: text.titleMedium),
                  if (d.model.isNotEmpty) Text(d.model, style: text.bodySmall),
                  if (d.serial.isNotEmpty) SelectableText('S/N ${d.serial}', style: text.bodyMedium),
                  if (d.bought != null) Text('Bought ${WifiDevicesBook.dayLabel(d.bought!)}', style: text.bodySmall),
                  if (_b.network(d.networkId) != null) Text('On ${_b.network(d.networkId)!.ssid}', style: text.bodySmall),
                  TextButton.icon(
                    key: Key('device-delete-${d.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_b.removeDevice(d.id)),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
