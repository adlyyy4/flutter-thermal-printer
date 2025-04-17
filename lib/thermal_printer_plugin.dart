import 'thermal_printer_plugin_platform_interface.dart';

class ThermalPrinterPlugin {
  Future<String?> getPlatformVersion() {
    return ThermalPrinterPluginPlatform.instance.getPlatformVersion();
  }

  /// Gets a list of paired Bluetooth devices
  Future<List<Map<String, dynamic>>> getBondedDevices() {
    return ThermalPrinterPluginPlatform.instance.getBondedDevices();
  }

  /// Connects to a Bluetooth device with the given address
  Future<bool> connect(String address) {
    return ThermalPrinterPluginPlatform.instance.connect(address);
  }

  /// Disconnects from the currently connected Bluetooth device
  Future<bool> disconnect() {
    return ThermalPrinterPluginPlatform.instance.disconnect();
  }

  /// Checks if the device is connected to a printer
  Future<bool> isConnected() {
    return ThermalPrinterPluginPlatform.instance.isConnected();
  }
}
