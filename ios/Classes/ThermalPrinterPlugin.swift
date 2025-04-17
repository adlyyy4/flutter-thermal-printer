import Flutter
import UIKit
import CoreBluetooth

public class ThermalPrinterPlugin: NSObject, FlutterPlugin, CBCentralManagerDelegate, CBPeripheralDelegate {
  private var centralManager: CBCentralManager!
  private var peripheral: CBPeripheral?
  private var writeCharacteristic: CBCharacteristic?
  private var pendingResult: FlutterResult?
  private var methodChannel: FlutterMethodChannel?
  
  // Dictionary to store discovered devices
  private var discoveredDevices: [String: CBPeripheral] = [:]
  
  // Flag to track connection status
  private var isConnected = false
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "thermal_printer_plugin", binaryMessenger: registrar.messenger())
    let instance = ThermalPrinterPlugin()
    instance.methodChannel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    // Initialize the central manager
    instance.centralManager = CBCentralManager(delegate: instance, queue: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getBondedDevices":
      getBondedDevices(result: result)
    case "connect":
      if let args = call.arguments as? [String: Any],
         let address = args["address"] as? String {
        connect(address: address, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Bluetooth address is required", details: nil))
      }
    case "disconnect":
      disconnect(result: result)
    case "isConnected":
      result(isConnected)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  // MARK: - Bluetooth Methods
  
  private func getBondedDevices(result: @escaping FlutterResult) {
    // iOS doesn't have a concept of "bonded" devices like Android
    // Instead, we'll scan for available devices
    
    // Clear previous discoveries
    discoveredDevices.removeAll()
    
    // Check if Bluetooth is powered on
    if centralManager.state != .poweredOn {
      result(FlutterError(code: "BLUETOOTH_UNAVAILABLE", message: "Bluetooth is not available or turned on", details: nil))
      return
    }
    
    // Set a timer to stop scanning after 5 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
      guard let self = self else { return }
      
      self.centralManager.stopScan()
      
      // Convert discovered devices to a list of maps
      var devicesList: [[String: Any]] = []
      for (uuid, peripheral) in self.discoveredDevices {
        devicesList.append([
          "name": peripheral.name ?? "Unknown Device",
          "address": uuid
        ])
      }
      
      result(devicesList)
    }
    
    // Start scanning for peripherals
    centralManager.scanForPeripherals(withServices: nil, options: nil)
  }
  
  private func connect(address: String, result: @escaping FlutterResult) {
    // Check if Bluetooth is powered on
    if centralManager.state != .poweredOn {
      result(FlutterError(code: "BLUETOOTH_UNAVAILABLE", message: "Bluetooth is not available or turned on", details: nil))
      return
    }
    
    // Disconnect from any existing connection
    if let peripheral = self.peripheral, peripheral.state != .disconnected {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // Find the peripheral with the given address
    guard let peripheral = discoveredDevices[address] else {
      // If the device is not in our discovered list, we need to scan for it
      pendingResult = result
      
      // Set a timer to stop scanning after 10 seconds
      DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
        guard let self = self, self.pendingResult != nil else { return }
        
        self.centralManager.stopScan()
        self.pendingResult?(FlutterError(code: "DEVICE_NOT_FOUND", message: "Could not find device with address \(address)", details: nil))
        self.pendingResult = nil
      }
      
      // Start scanning for the specific device
      centralManager.scanForPeripherals(withServices: nil, options: nil)
      return
    }
    
    // Connect to the peripheral
    self.peripheral = peripheral
    self.pendingResult = result
    centralManager.connect(peripheral, options: nil)
  }
  
  private func disconnect(result: @escaping FlutterResult) {
    if let peripheral = self.peripheral, peripheral.state != .disconnected {
      centralManager.cancelPeripheralConnection(peripheral)
      result(true)
    } else {
      result(false)
    }
  }
  
  // MARK: - CBCentralManagerDelegate
  
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn {
      // Bluetooth is not available
      if let pendingResult = self.pendingResult {
        pendingResult(FlutterError(code: "BLUETOOTH_UNAVAILABLE", message: "Bluetooth is not available or turned on", details: nil))
        self.pendingResult = nil
      }
    }
  }
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Store the discovered peripheral
    let uuid = peripheral.identifier.uuidString
    discoveredDevices[uuid] = peripheral
  }
  
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    // Successfully connected to the peripheral
    peripheral.delegate = self
    peripheral.discoverServices(nil)
    
    // Update connection status
    isConnected = true
    
    // If this connection was initiated by a connect call, return success
    if let pendingResult = self.pendingResult {
      pendingResult(true)
      self.pendingResult = nil
    }
  }
  
  public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    // Failed to connect to the peripheral
    isConnected = false
    
    if let pendingResult = self.pendingResult {
      pendingResult(FlutterError(code: "CONNECTION_FAILED", message: "Failed to connect to the printer: \(error?.localizedDescription ?? "Unknown error")", details: nil))
      self.pendingResult = nil
    }
  }
  
  public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    // Disconnected from the peripheral
    isConnected = false
    
    // Notify the Flutter side if needed
    if let methodChannel = self.methodChannel {
      methodChannel.invokeMethod("onDisconnected", arguments: nil)
    }
  }
  
  // MARK: - CBPeripheralDelegate
  
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      print("Error discovering services: \(error!.localizedDescription)")
      return
    }
    
    // Discover characteristics for each service
    if let services = peripheral.services {
      for service in services {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }
  
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard error == nil else {
      print("Error discovering characteristics: \(error!.localizedDescription)")
      return
    }
    
    // Look for a characteristic with write property
    if let characteristics = service.characteristics {
      for characteristic in characteristics {
        if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
          writeCharacteristic = characteristic
          break
        }
      }
    }
  }
}
