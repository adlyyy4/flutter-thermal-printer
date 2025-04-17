package com.example.thermal_printer_plugin
import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

/** ThermalPrinterPlugin */
class ThermalPrinterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activityBinding: ActivityPluginBinding? = null
  
  // Bluetooth related variables
  private var bluetoothAdapter: BluetoothAdapter? = null
  private var bluetoothSocket: BluetoothSocket? = null
  private var outputStream: OutputStream? = null
  
  // UUID for Serial Port Profile (SPP)
  private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
  
  // Tag for logging
  private val TAG = "ThermalPrinterPlugin"

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "thermal_printer_plugin")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    
    // Initialize Bluetooth adapter
    if (Build.VERSION.SDK_INT >= 18) { // JELLY_BEAN_MR2 = 18
      val bluetoothManager = context.getSystemService("bluetooth") as? BluetoothManager
      bluetoothAdapter = bluetoothManager?.adapter
    } else {
      @Suppress("DEPRECATION")
      bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "getBondedDevices" -> {
        getBondedDevices(result)
      }
      "connect" -> {
        val address = call.argument<String>("address")
        if (address != null) {
          connect(address, result)
        } else {
          result.error("INVALID_ARGUMENT", "Bluetooth address is required", null)
        }
      }
      "disconnect" -> {
        disconnect(result)
      }
      "isConnected" -> {
        isConnected(result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
  
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivity() {
    activityBinding = null
    // Ensure we disconnect from any printer when detached
    try {
      bluetoothSocket?.close()
      outputStream?.close()
    } catch (e: IOException) {
      Log.e(TAG, "Error closing Bluetooth connection: ${e.message}")
    } finally {
      bluetoothSocket = null
      outputStream = null
    }
  }
  
  private fun getBondedDevices(result: Result) {
    if (bluetoothAdapter == null) {
      result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth is not available on this device", null)
      return
    }
    
    if (Build.VERSION.SDK_INT >= 31 && // S = 31
        ActivityCompat.checkSelfPermission(context, "android.permission.BLUETOOTH_CONNECT") != PackageManager.PERMISSION_GRANTED) {
      result.error("PERMISSION_DENIED", "Bluetooth CONNECT permission not granted", null)
      return
    }
    
    try {
      val pairedDevices = bluetoothAdapter?.bondedDevices
      val devicesList = mutableListOf<Map<String, Any>>()
      
      pairedDevices?.forEach { device ->
        val deviceMap = mapOf(
          "name" to (device.name ?: "Unknown Device"),
          "address" to device.address
        )
        devicesList.add(deviceMap)
      }
      
      result.success(devicesList)
    } catch (e: Exception) {
      result.error("ERROR", "Error getting bonded devices: ${e.message}", null)
    }
  }
  
  private fun connect(address: String, result: Result) {
    Log.d(TAG, "Attempting to connect to device with address: $address")
    
    if (bluetoothAdapter == null) {
      Log.e(TAG, "Bluetooth adapter is null")
      result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth is not available on this device", null)
      return
    }
    
    // Check for Bluetooth permissions for Android 12+
    if (Build.VERSION.SDK_INT >= 31 && // S = 31
        ActivityCompat.checkSelfPermission(context, "android.permission.BLUETOOTH_CONNECT") != PackageManager.PERMISSION_GRANTED) {
      Log.e(TAG, "BLUETOOTH_CONNECT permission not granted")
      result.error("PERMISSION_DENIED", "Bluetooth CONNECT permission not granted", null)
      return
    }
    
    // Close any existing connection
    try {
      Log.d(TAG, "Closing any existing connections")
      bluetoothSocket?.close()
      outputStream?.close()
    } catch (e: IOException) {
      Log.e(TAG, "Error closing previous connection: ${e.message}")
    }
    
    // Get the BluetoothDevice
    val device: BluetoothDevice? = try {
      bluetoothAdapter?.getRemoteDevice(address)
    } catch (e: IllegalArgumentException) {
      Log.e(TAG, "Invalid Bluetooth address format: $address")
      result.error("INVALID_ADDRESS", "Invalid Bluetooth address format: $address", null)
      return
    }
    
    if (device == null) {
      Log.e(TAG, "Could not find device with address $address")
      result.error("DEVICE_NOT_FOUND", "Could not find device with address $address", null)
      return
    }
    
    // Check if device is paired
    if (Build.VERSION.SDK_INT >= 31 && // S = 31
        ActivityCompat.checkSelfPermission(context, "android.permission.BLUETOOTH_CONNECT") != PackageManager.PERMISSION_GRANTED) {
      Log.e(TAG, "BLUETOOTH_CONNECT permission not granted when checking bond state")
      result.error("PERMISSION_DENIED", "Bluetooth CONNECT permission not granted", null)
      return
    }
    
    try {
      if (device.bondState != BluetoothDevice.BOND_BONDED) {
        Log.e(TAG, "Device is not paired/bonded")
        result.error("DEVICE_NOT_PAIRED", "Device is not paired with this device", null)
        return
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error checking bond state: ${e.message}")
    }
    
    // Connect in a background thread to avoid ANR
    Thread {
      try {
        Log.d(TAG, "Creating RFCOMM socket")
        val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        
        Log.d(TAG, "Attempting socket connection...")
        
        // Set a timeout using a separate thread
        val timeoutThread = Thread(Runnable {
          Thread.sleep(10000) // 10 second timeout
          if (socket.isConnected) {
            return@Runnable
          }
          try {
            socket.close()
          } catch (e: IOException) {
            Log.e(TAG, "Error closing socket during timeout: ${e.message}")
          }
        })
        timeoutThread.start()
        
        socket.connect()
        
        // If we get here, connection succeeded
        val stream = socket.outputStream
        Log.d(TAG, "Connection successful, output stream established")
        
        // Save references to class variables
        bluetoothSocket = socket
        outputStream = stream
        
        // Return success on the main thread
        activityBinding?.activity?.runOnUiThread {
          result.success(true)
        }
      } catch (e: IOException) {
        Log.e(TAG, "Error connecting to device: ${e.message}")
        
        // Try fallback method for some devices
        try {
          Log.d(TAG, "Trying fallback connection method...")
          
          // First try different UUID
          val alternativeUUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
          val altSocket = device.createRfcommSocketToServiceRecord(alternativeUUID)
          
          // Set up timeout thread
          val timeoutThread = Thread(Runnable {
            Thread.sleep(10000) // 10 second timeout
            if (altSocket.isConnected) {
              return@Runnable
            }
            try {
              altSocket.close()
            } catch (e: IOException) {
              Log.e(TAG, "Error closing socket during timeout: ${e.message}")
            }
          })
          timeoutThread.start()
          
          altSocket.connect()
          
          val altStream = altSocket.outputStream
          Log.d(TAG, "Alternative connection successful")
          
          bluetoothSocket = altSocket
          outputStream = altStream
          
          activityBinding?.activity?.runOnUiThread {
            result.success(true)
          }
          
        } catch (e2: Exception) {
          Log.e(TAG, "Alternative connection failed: ${e2.message}")
          
          // Try reflection as a last resort
          try {
            Log.d(TAG, "Trying reflection method...")
            
            val createRfcommSocket = device.javaClass.getMethod(
              "createRfcommSocket", Integer.TYPE
            )
            
            val fallbackSocket = createRfcommSocket.invoke(device, 1) as BluetoothSocket
            
            // Set up timeout thread
            val timeoutThread = Thread(Runnable {
              Thread.sleep(10000) // 10 second timeout
              if (fallbackSocket.isConnected) {
                return@Runnable
              }
              try {
                fallbackSocket.close()
              } catch (e: IOException) {
                Log.e(TAG, "Error closing socket during timeout: ${e.message}")
              }
            })
            timeoutThread.start()
            
            fallbackSocket.connect()
            
            val fallbackStream = fallbackSocket.outputStream
            Log.d(TAG, "Reflection connection successful")
            
            bluetoothSocket = fallbackSocket
            outputStream = fallbackStream
            
            activityBinding?.activity?.runOnUiThread {
              result.success(true)
            }
            
          } catch (e3: Exception) {
            Log.e(TAG, "All connection methods failed: ${e3.message}")
            activityBinding?.activity?.runOnUiThread {
              result.error("CONNECTION_FAILED", 
                "Failed to connect to the printer: ${e3.message}\n" +
                "Please ensure:\n" +
                "1. The printer is powered on\n" +
                "2. The printer is paired with your device\n" +
                "3. You have the correct Bluetooth address", null)
            }
          }
        }
      }
    }.start()
  }
  
  private fun disconnect(result: Result) {
    try {
      bluetoothSocket?.close()
      outputStream?.close()
      bluetoothSocket = null
      outputStream = null
      result.success(true)
    } catch (e: IOException) {
      Log.e(TAG, "Error disconnecting: ${e.message}")
      result.error("DISCONNECT_FAILED", "Failed to disconnect: ${e.message}", null)
    }
  }
  
  private fun isConnected(result: Result) {
    result.success(bluetoothSocket?.isConnected == true)
  }
}
