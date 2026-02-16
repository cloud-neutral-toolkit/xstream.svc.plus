import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/app/darwin_host_api.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/Messages.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
class TunnelRouteV4 {
  TunnelRouteV4({
    required this.destinationAddress,
    required this.subnetMask,
  });

  String destinationAddress;
  String subnetMask;
}

class TunnelRouteV6 {
  TunnelRouteV6({
    required this.destinationAddress,
    required this.networkPrefixLength,
  });

  String destinationAddress;
  int networkPrefixLength;
}

class TunnelProfile {
  TunnelProfile({
    required this.mtu,
    required this.tun46Setting,
    required this.defaultNicSupport6,
    required this.dnsServers4,
    required this.dnsServers6,
    required this.ipv4Addresses,
    required this.ipv4SubnetMasks,
    required this.ipv4IncludedRoutes,
    required this.ipv4ExcludedRoutes,
    required this.ipv6Addresses,
    required this.ipv6NetworkPrefixLengths,
    required this.ipv6IncludedRoutes,
    required this.ipv6ExcludedRoutes,
    required this.configPath,
  });

  int mtu;
  int tun46Setting;
  bool defaultNicSupport6;
  List<String> dnsServers4;
  List<String> dnsServers6;
  List<String> ipv4Addresses;
  List<String> ipv4SubnetMasks;
  List<TunnelRouteV4> ipv4IncludedRoutes;
  List<TunnelRouteV4> ipv4ExcludedRoutes;
  List<String> ipv6Addresses;
  List<int> ipv6NetworkPrefixLengths;
  List<TunnelRouteV6> ipv6IncludedRoutes;
  List<TunnelRouteV6> ipv6ExcludedRoutes;
  String configPath;
}

class TunnelStatus {
  TunnelStatus({
    required this.state,
    required this.lastError,
    required this.utunInterfaces,
    required this.startedAt,
  });

  String state;
  String? lastError;
  List<String> utunInterfaces;
  int? startedAt;
}

@HostApi()
abstract class DarwinHostApi {
  String appGroupPath();

  @async
  void startXApiServer(Uint8List config);

  @async
  void redirectStdErr(String path);

  Uint8List generateTls();

  void setupShutdownNotification();

  String savePacketTunnelProfile(TunnelProfile profile);

  @async
  void startPacketTunnel();

  @async
  void stopPacketTunnel();

  TunnelStatus getPacketTunnelStatus();
}

@FlutterApi()
abstract class DarwinFlutterApi {
  void onSystemWillShutdown();

  void onSystemWillRestart();

  void onSystemWillSleep();

  void onPacketTunnelStateChanged(TunnelStatus status);

  void onPacketTunnelError(String code, String message);
}
