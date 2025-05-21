// Real-time device discovery with event notification example
// This example demonstrates how to listen for device discovery events and display them in real-time
import 'dart:async';
import 'dart:io';
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:chromecast_dlna_finder/src/util/logger.dart'; // Add this line to import AppLogLevel

// ANSI color codes (for colorized terminal output)
class AnsiColor {
  static const String reset = '\x1B[0m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
  static const String bold = '\x1B[1m';
}

Future<void> main() async {
  print(
    '\n${AnsiColor.bold}${AnsiColor.cyan}=== Chromecast & DLNA Device Discovery (Event-Driven) ===${AnsiColor.reset}\n',
  );

  // Initialize finder
  final finder = ChromecastDlnaFinder();

  // Device counters
  int chromecastCount = 0;
  int dlnaRendererCount = 0;
  int dlnaServerCount = 0;

  // Set lower log level to see more details
  await finder.configureLogger(minLevel: AppLogLevel.error);

  // Listen for device discovery events (this is how to use the new event system)
  final subscription = finder.deviceEvents?.listen((event) {
    if (event is SearchStartedEvent) {
      // Search started event
      print(
        '${AnsiColor.yellow}▶ Starting search for ${_formatDeviceType(event.deviceType)}...${AnsiColor.reset}',
      );
    } else if (event is DeviceFoundEvent) {
      // Device found event - this is the key part, triggered for each discovered device
      final device = event.device;

      // Update counters based on device type
      if (device.isChromecast) {
        chromecastCount++;
      } else if (device.isDlnaRenderer) {
        dlnaRendererCount++;
      } else if (device.isDlnaMediaServer) {
        dlnaServerCount++;
      }

      // Use different colors for different device types
      String deviceColor;
      if (device.isChromecast) {
        deviceColor = AnsiColor.cyan;
      } else if (device.isDlnaRenderer) {
        deviceColor = AnsiColor.green;
      } else if (device.isDlnaMediaServer) {
        deviceColor = AnsiColor.magenta;
      } else {
        deviceColor = AnsiColor.white;
      }

      // Display device discovery information
      print('\n$deviceColor╔═══════════════════════════════════════════════');
      print(
        '$deviceColor║ ${AnsiColor.bold}Device Found!${AnsiColor.reset}$deviceColor ${device.name}',
      );
      print('$deviceColor║ IP: ${device.ip}');
      print('$deviceColor║ Type: ${_getDeviceTypeString(device)}');
      if (device.model != null) {
        print('$deviceColor║ Model: ${device.model}');
      }
      if (device.location != null) {
        print('$deviceColor║ Location: ${device.location}');
      }
      print(
        '$deviceColor╚═══════════════════════════════════════════════${AnsiColor.reset}',
      );

      // Show current progress
      print(
        '${AnsiColor.bold}Current Discovery: Chromecast: $chromecastCount, DLNA Renderers: $dlnaRendererCount, DLNA Servers: $dlnaServerCount${AnsiColor.reset}',
      );
    } else if (event is SearchCompleteEvent) {
      // Search complete event
      print(
        '\n${AnsiColor.green}✓ ${_formatDeviceType(event.deviceType)} search completed, found ${event.deviceCount} devices${AnsiColor.reset}',
      );
    } else if (event is SearchErrorEvent) {
      // Search error event
      print(
        '\n${AnsiColor.red}✗ ${_formatDeviceType(event.deviceType)} search failed: ${event.error}${AnsiColor.reset}',
      );
    }
  });

  // Show waiting animation using a timer for periodic updates
  final loadingChars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  int loadingIndex = 0;
  final loadingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
    stdout.write(
      '\r${AnsiColor.cyan}${loadingChars[loadingIndex]} Searching for network devices...${AnsiColor.reset}',
    );
    loadingIndex = (loadingIndex + 1) % loadingChars.length;
  });

  try {
    // Start device discovery
    print(
      '${AnsiColor.yellow}Starting network device discovery, please wait...${AnsiColor.reset}\n',
    );
    final devices = await finder.findDevices(timeout: Duration(seconds: 10));

    // Stop loading animation
    loadingTimer.cancel();
    // Clear loading prompt
    stdout.write('\r                                            \r');

    // Display final statistics
    print(
      '\n${AnsiColor.bold}${AnsiColor.green}=== Search Completed! ===${AnsiColor.reset}',
    );
    print(
      '${AnsiColor.cyan}Chromecast Devices: ${devices['chromecast']?.length ?? 0}${AnsiColor.reset}',
    );
    print(
      '${AnsiColor.green}DLNA Renderers: ${devices['dlna_renderer']?.length ?? 0}${AnsiColor.reset}',
    );
    print(
      '${AnsiColor.magenta}DLNA Media Servers: ${devices['dlna_media_server']?.length ?? 0}${AnsiColor.reset}',
    );

    // Show summary of all available devices
    if ((devices['chromecast']?.length ?? 0) > 0) {
      print(
        '\n${AnsiColor.bold}${AnsiColor.cyan}Chromecast Devices:${AnsiColor.reset}',
      );
      for (final device in devices['chromecast'] ?? []) {
        print(
          '${AnsiColor.cyan}- ${device.name} (${device.ip})${device.model != null ? ' [${device.model}]' : ''}${AnsiColor.reset}',
        );
      }
    }

    if ((devices['dlna_renderer']?.length ?? 0) > 0) {
      print(
        '\n${AnsiColor.bold}${AnsiColor.green}DLNA Renderers:${AnsiColor.reset}',
      );
      for (final device in devices['dlna_renderer'] ?? []) {
        print(
          '${AnsiColor.green}- ${device.name} (${device.ip})${device.model != null ? ' [${device.model}]' : ''}${AnsiColor.reset}',
        );
      }
    }

    if ((devices['dlna_media_server']?.length ?? 0) > 0) {
      print(
        '\n${AnsiColor.bold}${AnsiColor.magenta}DLNA Media Servers:${AnsiColor.reset}',
      );
      for (final device in devices['dlna_media_server'] ?? []) {
        print(
          '${AnsiColor.magenta}- ${device.name} (${device.ip})${device.model != null ? ' [${device.model}]' : ''}${AnsiColor.reset}',
        );
      }
    }

    // Tip for users on how to use these devices
    if ((devices['chromecast']?.length ?? 0) > 0 ||
        (devices['dlna_renderer']?.length ?? 0) > 0) {
      print(
        '\n${AnsiColor.yellow}💡 Tip: You can use these playback devices to stream music, videos, or other media content${AnsiColor.reset}',
      );
    }
  } finally {
    // Clean up resources
    loadingTimer.cancel();
    await subscription?.cancel();
    await finder.dispose();
    print(
      '\n${AnsiColor.yellow}Resources cleaned up and search terminated${AnsiColor.reset}',
    );
  }
}

// Convert device type to readable text
String _getDeviceTypeString(DiscoveredDevice device) {
  if (device.isChromecastDongle) return 'Chromecast';
  if (device.isChromecastAudio) return 'Chromecast Audio';
  if (device.isDlnaRenderer) return 'DLNA Renderer';
  if (device.isDlnaMediaServer) return 'DLNA Media Server';
  return 'Unknown Device';
}

// Format device type name
String _formatDeviceType(String type) {
  switch (type) {
    case 'chromecast':
      return 'Chromecast devices';
    case 'dlna':
      return 'DLNA devices';
    case 'all':
      return 'all devices';
    default:
      return type;
  }
}
