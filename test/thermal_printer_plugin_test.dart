import 'package:flutter_test/flutter_test.dart';
import 'package:thermal_printer_plugin/thermal_printer_plugin.dart';
import 'package:thermal_printer_plugin/thermal_printer_plugin_platform_interface.dart';
import 'package:thermal_printer_plugin/thermal_printer_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockThermalPrinterPluginPlatform
    with MockPlatformInterfaceMixin
    implements ThermalPrinterPluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<List<Map<String, dynamic>>> getBondedDevices() {
    return Future.value([
      {'name': 'Mock Printer', 'address': '00:11:22:33:44:55'},
    ]);
  }

  @override
  Future<bool> connect(String address) {
    return Future.value(true);
  }

  @override
  Future<bool> disconnect() {
    return Future.value(true);
  }

  @override
  Future<bool> isConnected() {
    return Future.value(true);
  }
}

void main() {
  final ThermalPrinterPluginPlatform initialPlatform = ThermalPrinterPluginPlatform.instance;

  test('$MethodChannelThermalPrinterPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelThermalPrinterPlugin>());
  });

  test('getPlatformVersion', () async {
    ThermalPrinterPlugin thermalPrinterPlugin = ThermalPrinterPlugin();
    MockThermalPrinterPluginPlatform fakePlatform = MockThermalPrinterPluginPlatform();
    ThermalPrinterPluginPlatform.instance = fakePlatform;

    expect(await thermalPrinterPlugin.getPlatformVersion(), '42');
  });
}
