import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:thermal_printer_plugin/thermal_printer_plugin.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ThermalPrinterDemo());
  }
}

class ThermalPrinterDemo extends StatefulWidget {
  const ThermalPrinterDemo({super.key});

  @override
  State<ThermalPrinterDemo> createState() => _ThermalPrinterDemoState();
}

class _ThermalPrinterDemoState extends State<ThermalPrinterDemo> {
  String _platformVersion = 'Unknown';
  final _thermalPrinterPlugin = ThermalPrinterPlugin();

  // Bluetooth related variables
  List<Map<String, dynamic>> _devices = [];
  bool _isConnected = false;
  String _connectedDeviceName = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _thermalPrinterPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });

    // Check if already connected to a printer
    _checkConnectionStatus();
  }

  // Get paired Bluetooth devices
  Future<void> _getBondedDevices() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final devices = await _thermalPrinterPlugin.getBondedDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Error getting devices', e.message ?? 'Unknown error');
    }
  }

  // Connect to a printer
  Future<void> _connect(String address, String name) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _thermalPrinterPlugin.connect(address);
      setState(() {
        _isLoading = false;
        _isConnected = result;
        if (result) {
          _connectedDeviceName = name;
        }
      });

      if (result) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected to $name')));
      } else {
        _showErrorDialog('Connection Failed', 'Failed to connect to $name');
      }
    } on PlatformException catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Connection Error', e.message ?? 'Unknown error');
    }
  }

  // Disconnect from printer
  Future<void> _disconnect() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _thermalPrinterPlugin.disconnect();
      setState(() {
        _isLoading = false;
        if (result) {
          _isConnected = false;
          _connectedDeviceName = '';
        }
      });

      if (result) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Disconnected from printer')));
      }
    } on PlatformException catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Disconnect Error', e.message ?? 'Unknown error');
    }
  }

  // Check connection status
  Future<void> _checkConnectionStatus() async {
    try {
      final result = await _thermalPrinterPlugin.isConnected();
      setState(() {
        _isConnected = result;
      });
    } on PlatformException {
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thermal Printer Plugin')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Running on: $_platformVersion'),
                    const SizedBox(height: 20),

                    // Connection status
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connection Status',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  _isConnected
                                      ? Icons.bluetooth_connected
                                      : Icons.bluetooth_disabled,
                                  color: _isConnected ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isConnected
                                      ? 'Connected to $_connectedDeviceName'
                                      : 'Not connected',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_isConnected)
                              ElevatedButton(
                                onPressed: _disconnect,
                                child: const Text('Disconnect'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Device list
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bluetooth Devices',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _getBondedDevices,
                              child: const Text('Scan for Devices'),
                            ),
                            const SizedBox(height: 16),
                            if (_devices.isEmpty)
                              const Text('No devices found')
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _devices.length,
                                itemBuilder: (context, index) {
                                  final device = _devices[index];
                                  final name = device['name'] as String;
                                  final address = device['address'] as String;

                                  return ListTile(
                                    title: Text(name),
                                    subtitle: Text(address),
                                    trailing: ElevatedButton(
                                      onPressed: () => _connect(address, name),
                                      child: const Text('Connect'),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
