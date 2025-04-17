import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'thermal_printer_plugin_method_channel.dart';

abstract class ThermalPrinterPluginPlatform extends PlatformInterface {
  /// Constructs a ThermalPrinterPluginPlatform.
  ThermalPrinterPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static ThermalPrinterPluginPlatform _instance = MethodChannelThermalPrinterPlugin();

  /// The default instance of [ThermalPrinterPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelThermalPrinterPlugin].
  static ThermalPrinterPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ThermalPrinterPluginPlatform] when
  /// they register themselves.
  static set instance(ThermalPrinterPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Gets a list of paired Bluetooth devices
  Future<List<Map<String, dynamic>>> getBondedDevices() {
    throw UnimplementedError('getBondedDevices() has not been implemented.');
  }

  /// Connects to a Bluetooth device with the given address
  Future<bool> connect(String address) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects from the currently connected Bluetooth device
  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Checks if the device is connected to a printer
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }
}
