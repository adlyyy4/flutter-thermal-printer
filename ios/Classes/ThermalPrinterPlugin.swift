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
    
    // If already scanning, stop previous scan
    if centralManager.isScanning {
      centralManager.stopScan()
    }
    
    // Store the result callback to use when scan completes
    pendingResult = result
    
    // Set a timer to stop scanning after 5 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
      guard let self = self else { return }
      
      // Only stop scanning if we're still scanning for devices
      if self.centralManager.isScanning {
        self.centralManager.stopScan()
      }
      
      // Only process results if this is still the active getBondedDevices call
      if self.pendingResult != nil {
        // Convert discovered devices to a list of maps
        var devicesList: [[String: Any]] = []
        for (uuid, peripheral) in self.discoveredDevices {
          // Only include devices with names (or provide a placeholder)
          let deviceName = peripheral.name ?? "Unknown Device"
          devicesList.append([
            "name": deviceName,
            "address": uuid
          ])
        }
        
        // Return the list of devices
        self.pendingResult?(devicesList)
        self.pendingResult = nil
      }
    }
    
    // Start scanning for peripherals with more options for better discovery
    let scanOptions: [String: Any] = [
      CBCentralManagerScanOptionAllowDuplicatesKey: false
    ]
    centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
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
        guard let self = self else { return }
        
        self.centralManager.stopScan()
        
        // Only call the result if it hasn't been called yet
        if self.pendingResult != nil {
          self.pendingResult?(FlutterError(code: "DEVICE_NOT_FOUND", message: "Could not find device with address \(address)", details: nil))
          self.pendingResult = nil
        }
      }
      
      // Start scanning for the specific device
      centralManager.scanForPeripherals(withServices: nil, options: nil)
      return
    }
    
    // Connect to the peripheral
    self.peripheral = peripheral
    self.pendingResult = result
    
    // Set a connection timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
      guard let self = self else { return }
      
      // Check if we're still trying to connect to this peripheral
      if self.pendingResult != nil && self.peripheral?.identifier == peripheral.identifier {
        // If we're still waiting after 15 seconds, assume connection failed
        if peripheral.state != .connected {
          // Cancel the connection attempt
          self.centralManager.cancelPeripheralConnection(peripheral)
          
          // Get the current Bluetooth state
          let btState: String
          switch self.centralManager.state {
          case .poweredOn: btState = "powered on"
          case .poweredOff: btState = "powered off"
          case .resetting: btState = "resetting"
          case .unauthorized: btState = "unauthorized"
          case .unsupported: btState = "unsupported"
          case .unknown: btState = "unknown"
          @unknown default: btState = "unknown state"
          }
          
          // Create a detailed error message
          let deviceName = peripheral.name ?? "Unknown device"
          let errorMessage = "Connection to device timed out after 15 seconds. Bluetooth is \(btState). "
            + "Device: \(deviceName), ID: \(peripheral.identifier.uuidString). "
            + "Please ensure the printer is turned on, in range, and in pairing mode."
          
          // Return the error to Flutter
          self.pendingResult?(FlutterError(code: "CONNECTION_TIMEOUT", message: errorMessage, details: nil))
          self.pendingResult = nil
        }
      }
    }
    
    // Start the connection attempt
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
      
      // If we were scanning, stop scanning
      if central.isScanning {
        central.stopScan()
      }
    } else {
      // Bluetooth is now powered on - if we were in the middle of a getBondedDevices call, restart scanning
      if let methodChannel = self.methodChannel, central.isScanning == false {
        methodChannel.invokeMethod("onBluetoothStateChanged", arguments: ["state": "on"])
      }
    }
  }
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Store the discovered peripheral
    let uuid = peripheral.identifier.uuidString
    discoveredDevices[uuid] = peripheral
    
    // If we're scanning for a specific device to connect to, check if this is the one
    if let pendingResult = self.pendingResult, let targetPeripheral = self.peripheral, targetPeripheral.identifier == peripheral.identifier {
      // We found the device we're looking for, stop scanning
      central.stopScan()
      
      // Connect to it
      central.connect(peripheral, options: nil)
    }
  }
  
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    // Successfully connected to the peripheral
    print("Successfully connected to peripheral: \(peripheral.name ?? "Unknown") (\(peripheral.identifier))")
    
    peripheral.delegate = self
    
    // Log the connection state
    print("Discovering services for peripheral: \(peripheral.name ?? "Unknown")")
    
    // Discover services with a specific service UUID if known, or nil for all services
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
      // Get detailed error information
      var errorCode = "CONNECTION_FAILED"
      var errorMessage = "Failed to connect to the printer"
      
      if let error = error as NSError? {
        // Extract CoreBluetooth specific error information
        switch error.domain {
        case CBErrorDomain:
          switch CBError.Code(rawValue: error.code) {
          case .unknown:
            errorCode = "BT_UNKNOWN_ERROR"
            errorMessage = "Unknown Bluetooth error occurred"
          case .invalidParameters:
            errorCode = "BT_INVALID_PARAMETERS"
            errorMessage = "Invalid parameters were provided for the connection"
          case .invalidHandle:
            errorCode = "BT_INVALID_HANDLE"
            errorMessage = "The device handle is invalid"
          case .notConnected:
            errorCode = "BT_NOT_CONNECTED"
            errorMessage = "The device is not connected"
          case .outOfSpace:
            errorCode = "BT_OUT_OF_SPACE"
            errorMessage = "The Bluetooth subsystem is out of memory"
          case .operationCancelled:
            errorCode = "BT_OPERATION_CANCELLED"
            errorMessage = "The connection operation was cancelled"
          case .connectionTimeout:
            errorCode = "BT_CONNECTION_TIMEOUT"
            errorMessage = "The connection timed out"
          case .peripheralDisconnected:
            errorCode = "BT_PERIPHERAL_DISCONNECTED"
            errorMessage = "The peripheral disconnected during the connection process"
          case .uuidNotAllowed:
            errorCode = "BT_UUID_NOT_ALLOWED"
            errorMessage = "The app is not allowed to use the specified UUID"
          case .alreadyAdvertising:
            errorCode = "BT_ALREADY_ADVERTISING"
            errorMessage = "The peripheral is already advertising"
          // Some newer CoreBluetooth error codes are not available in older iOS versions
          // We'll handle the basic error codes that are available in most iOS versions
          default:
            errorCode = "BT_ERROR_\(error.code)"
            errorMessage = "Bluetooth error: \(error.localizedDescription)"
          }
        default:
          errorCode = "SYSTEM_ERROR"
          errorMessage = "System error: \(error.localizedDescription)"
        }
      }
      
      // Add more context to the error message
      let deviceName = peripheral.name ?? "Unknown device"
      let detailedMessage = "\(errorMessage) (Device: \(deviceName), ID: \(peripheral.identifier.uuidString))"
      
      pendingResult(FlutterError(code: errorCode, message: detailedMessage, details: nil))
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
      
      // If we have a pending result, return the error
      if let pendingResult = self.pendingResult {
        pendingResult(FlutterError(code: "SERVICE_DISCOVERY_FAILED", 
                                  message: "Failed to discover services: \(error!.localizedDescription)", 
                                  details: nil))
        self.pendingResult = nil
      }
      return
    }
    
    // Log discovered services for debugging
    if let services = peripheral.services {
      print("Discovered \(services.count) services:")
      for service in services {
        print("Service: \(service.uuid)")
        peripheral.discoverCharacteristics(nil, for: service)
      }
    } else {
      print("No services found on device \(peripheral.name ?? "Unknown")")
      
      // If we have a pending result and no services were found, return an error
      if let pendingResult = self.pendingResult {
        pendingResult(FlutterError(code: "NO_SERVICES_FOUND", 
                                  message: "No Bluetooth services found on the device. This may not be a compatible printer.", 
                                  details: nil))
        self.pendingResult = nil
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
