import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thermal_printer_plugin_platform_interface.dart';

/// An implementation of [ThermalPrinterPluginPlatform] that uses method channels.
class MethodChannelThermalPrinterPlugin extends ThermalPrinterPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('thermal_printer_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<List<Map<String, dynamic>>> getBondedDevices() async {
    final devices = await methodChannel.invokeMethod<List<dynamic>>('getBondedDevices');
    return devices?.map((device) => Map<String, dynamic>.from(device)).toList() ?? [];
  }

  @override
  Future<bool> connect(String address) async {
    final result = await methodChannel.invokeMethod<bool>('connect', {'address': address});
    return result ?? false;
  }

  @override
  Future<bool> disconnect() async {
    final result = await methodChannel.invokeMethod<bool>('disconnect');
    return result ?? false;
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }
}
