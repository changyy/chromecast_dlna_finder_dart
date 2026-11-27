// Regression tests for "Bad state: mDNS client must be started before calling
// lookup." (Crashlytics, LAN Finder / AnyDLNA, 2026-11): lookups issued by the
// periodic PTR query or by the SRV → A → TXT chain after the shared client was
// stopped threw a StateError that nothing awaited, so it crashed the app.
import 'dart:async';
import 'dart:io';

import 'package:chromecast_dlna_finder/src/discovery/device.dart';
import 'package:chromecast_dlna_finder/src/discovery/mdns_scanner.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:test/test.dart';

/// A fake client that behaves like MDnsClient: lookup throws a StateError
/// synchronously once the client is stopped. Answers are served with a small
/// delay so the scan can be stopped in the middle of the resolve chain.
class FakeMDnsClient extends MDnsClient {
  FakeMDnsClient({
    this.answerDelay = const Duration(milliseconds: 20),
    this.sendErrno,
  }) : super();

  final Duration answerDelay;

  /// When set, lookup throws a SocketException with this errno synchronously,
  /// like RawDatagramSocket.send does without a network (101) or without
  /// multicast permission (1).
  int? sendErrno;
  int sendFailures = 0;
  bool started = false;
  int lookupsAfterStop = 0;
  int lookups = 0;

  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {
    started = true;
  }

  @override
  void stop() {
    started = false;
  }

  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (!started) {
      lookupsAfterStop++;
      throw StateError('mDNS client must be started before calling lookup.');
    }
    lookups++;
    if (sendErrno != null) {
      sendFailures++;
      throw SocketException(
        'Send failed',
        osError: OSError('Network is unreachable', sendErrno!),
        address: InternetAddress.anyIPv4,
        port: 5353,
      );
    }
    final controller = StreamController<T>();
    Future<void>.delayed(answerDelay, () {
      final ResourceRecord? record = switch (query.resourceRecordType) {
        ResourceRecordType.serverPointer => PtrResourceRecord(
          query.fullyQualifiedName,
          0,
          domainName: 'Living Room._googlecast._tcp.local',
        ),
        ResourceRecordType.service => SrvResourceRecord(
          query.fullyQualifiedName,
          0,
          target: 'cc.local',
          port: 8009,
          priority: 0,
          weight: 0,
        ),
        ResourceRecordType.addressIPv4 => IPAddressResourceRecord(
          query.fullyQualifiedName,
          0,
          address: InternetAddress('192.168.1.50'),
        ),
        ResourceRecordType.text => TxtResourceRecord(
          query.fullyQualifiedName,
          0,
          text: 'id=abc123\nfn=Living Room\nmd=Chromecast',
        ),
        _ => null,
      };
      if (record is T) controller.add(record);
      controller.close();
    });
    return controller.stream;
  }
}

DiscoveredDevice _factory({
  required String ip,
  required int port,
  required String serviceName,
  required Map<String, String> txtMap,
  List<String>? mdnsTypes,
}) => DiscoveredDevice.fromChromecast(
  ip: ip,
  port: port,
  serviceName: serviceName,
  txtMap: txtMap,
);

/// Runs [body] and returns every error that escaped to the zone (what the
/// app's runZonedGuarded / PlatformDispatcher.onError reported to Crashlytics).
Future<List<Object>> _uncaughtErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    await body();
    done.complete();
  }, (e, _) => errors.add(e));
  await done.future;
  return errors;
}

void main() {
  test('finds a device with a healthy client', () async {
    final client = FakeMDnsClient();
    final found = <DiscoveredDevice>[];
    final errors = await _uncaughtErrors(() async {
      final devices = await scanMdnsDevices(
        serviceType: '_googlecast._tcp',
        mdnsType: '_googlecast._tcp',
        deviceFactory: _factory,
        onDeviceFound: found.add,
        sharedClient: client,
        stopClientOnFinish: false,
        scanDuration: const Duration(milliseconds: 300),
        sendQueryMessageInterval: const Duration(milliseconds: 100),
      );
      expect(devices, hasLength(1));
      expect(devices.single.ip, '192.168.1.50');
    });
    expect(errors, isEmpty);
    expect(found, hasLength(1));
  });

  test('shared client stopped mid-scan (dispose) does not throw', () async {
    final client = FakeMDnsClient();
    final errors = await _uncaughtErrors(() async {
      final scan = scanMdnsDevices(
        serviceType: '_googlecast._tcp',
        mdnsType: '_googlecast._tcp',
        deviceFactory: _factory,
        sharedClient: client,
        stopClientOnFinish: false,
        scanDuration: const Duration(milliseconds: 400),
        sendQueryMessageInterval: const Duration(milliseconds: 30),
      );
      // Stopped by the app (e.g. a page closing) while the PTR → SRV → A → TXT chain and the periodic query run.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      client.stop();
      await scan;
      // Let late timers / answers fire after the scan returned.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(errors, isEmpty, reason: 'StateError escaped: $errors');
    expect(
      client.lookupsAfterStop,
      lessThanOrEqualTo(1),
      reason: 'the scan must stop querying once the client is stopped',
    );
  });

  test('no callback and no lookup after the scan returned', () async {
    final client = FakeMDnsClient(
      answerDelay: const Duration(milliseconds: 60),
    );
    final found = <DiscoveredDevice>[];
    var returned = false;
    var foundAfterReturn = 0;
    final errors = await _uncaughtErrors(() async {
      await scanMdnsDevices(
        serviceType: '_googlecast._tcp',
        mdnsType: '_googlecast._tcp',
        deviceFactory: _factory,
        onDeviceFound: (d) {
          if (returned) foundAfterReturn++;
          found.add(d);
        },
        sharedClient: client,
        stopClientOnFinish: false,
        // Ends while the resolve chain (3 × 60 ms) is still in flight.
        scanDuration: const Duration(milliseconds: 100),
        sendQueryMessageInterval: const Duration(milliseconds: 40),
      );
      returned = true;
      final lookupsAtReturn = client.lookups;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        client.lookups,
        lookupsAtReturn,
        reason: 'no new lookups after the scan returned',
      );
      client.stop();
    });
    expect(errors, isEmpty);
    expect(foundAfterReturn, 0);
  });

  test('a stopped shared client is started again by the next scan', () async {
    final client = FakeMDnsClient();
    await scanMdnsDevices(
      serviceType: '_googlecast._tcp',
      mdnsType: '_googlecast._tcp',
      deviceFactory: _factory,
      sharedClient: client,
      stopClientOnFinish: false,
      scanDuration: const Duration(milliseconds: 150),
    );
    stopMdnsClient(client);
    expect(client.started, isFalse);
    final devices = await scanMdnsDevices(
      serviceType: '_googlecast._tcp',
      mdnsType: '_googlecast._tcp',
      deviceFactory: _factory,
      sharedClient: client,
      stopClientOnFinish: false,
      scanDuration: const Duration(milliseconds: 300),
    );
    expect(client.started, isTrue);
    expect(devices, hasLength(1));
    expect(client.lookupsAfterStop, 0);
  });

  // Crashlytics, DLNA for Chromecast 1.20261126.1160506 (Xiaomi, Android 12):
  // "SocketException: Send failed (OS Error: Network is unreachable,
  // errno = 101)" from MDnsClient.lookup — Wi-Fi dropped during a scan and the
  // periodic PTR query threw from a timer callback.
  test('send failure (no network) does not throw and the scan ends', () async {
    final client = FakeMDnsClient(sendErrno: 101);
    List<DiscoveredDevice>? devices;
    final errors = await _uncaughtErrors(() async {
      devices = await scanMdnsDevices(
        serviceType: '_googlecast._tcp',
        mdnsType: '_googlecast._tcp',
        deviceFactory: _factory,
        sharedClient: client,
        stopClientOnFinish: false,
        scanDuration: const Duration(milliseconds: 250),
        sendQueryMessageInterval: const Duration(milliseconds: 50),
      );
    });
    expect(errors, isEmpty, reason: 'SocketException escaped: $errors');
    expect(devices, isEmpty);
    expect(client.sendFailures, greaterThan(1), reason: 'keeps retrying');
  });

  test('network comes back mid-scan: later queries find the device', () async {
    final client = FakeMDnsClient(sendErrno: 101);
    final errors = await _uncaughtErrors(() async {
      final scan = scanMdnsDevices(
        serviceType: '_googlecast._tcp',
        mdnsType: '_googlecast._tcp',
        deviceFactory: _factory,
        sharedClient: client,
        stopClientOnFinish: false,
        scanDuration: const Duration(milliseconds: 400),
        sendQueryMessageInterval: const Duration(milliseconds: 50),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      client.sendErrno = null;
      expect(await scan, hasLength(1));
    });
    expect(errors, isEmpty);
  });

  test('multicast permission denied (errno 1) still fails the scan', () async {
    final client = FakeMDnsClient(sendErrno: 1);
    Object? thrown;
    final errors = await _uncaughtErrors(() async {
      try {
        await scanMdnsDevices(
          serviceType: '_googlecast._tcp',
          mdnsType: '_googlecast._tcp',
          deviceFactory: _factory,
          sharedClient: client,
          stopClientOnFinish: false,
          scanDuration: const Duration(milliseconds: 250),
          sendQueryMessageInterval: const Duration(milliseconds: 50),
        );
      } catch (e) {
        thrown = e;
      }
    });
    expect(errors, isEmpty);
    expect(thrown.toString(), contains('mDNS permission denied'));
    expect(client.sendFailures, 1, reason: 'stops at the first denial');
  });
}
