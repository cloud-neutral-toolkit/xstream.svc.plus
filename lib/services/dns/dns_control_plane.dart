enum ResolverTransport {
  plain,
  doh,
  fake,
}

class ResolverServerPolicy {
  final String address;
  final String tag;
  final ResolverTransport transport;
  final List<String> domains;
  final bool skipFallback;

  const ResolverServerPolicy({
    required this.address,
    required this.tag,
    required this.transport,
    this.domains = const <String>[],
    this.skipFallback = false,
  });

  Map<String, dynamic> toXrayDnsServer() {
    final server = <String, dynamic>{
      'address': address,
      'tag': tag,
      'queryStrategy': 'UseIPv4',
    };
    if (domains.isNotEmpty) {
      server['domains'] = domains;
    }
    if (skipFallback) {
      server['skipFallback'] = true;
    }
    return server;
  }
}

class FakeDnsPolicy {
  final bool enabled;
  final List<String> domains;
  final List<Map<String, dynamic>> pools;
  final String warning;

  const FakeDnsPolicy({
    required this.enabled,
    this.domains = const <String>[],
    this.pools = const <Map<String, dynamic>>[],
    this.warning = '',
  });
}

class DomainSets {
  final List<String> direct;
  final List<String> proxy;
  final List<String> fake;
  final List<String> directIpCidrs;

  const DomainSets({
    required this.direct,
    required this.proxy,
    required this.fake,
    required this.directIpCidrs,
  });
}

class DnsPolicy {
  final List<ResolverServerPolicy> directResolvers;
  final List<ResolverServerPolicy> proxyResolvers;
  final FakeDnsPolicy fakeDns;

  const DnsPolicy({
    required this.directResolvers,
    required this.proxyResolvers,
    required this.fakeDns,
  });

  List<Map<String, dynamic>> buildDnsServers() {
    final servers = <Map<String, dynamic>>[];
    if (fakeDns.enabled && fakeDns.domains.isNotEmpty) {
      servers.add(
        const ResolverServerPolicy(
          address: 'fakedns',
          tag: 'dns-fake',
          transport: ResolverTransport.fake,
          skipFallback: true,
        ).toXrayDnsServer()
          ..['domains'] = fakeDns.domains,
      );
    }
    servers
        .addAll(directResolvers.map((resolver) => resolver.toXrayDnsServer()));
    servers
        .addAll(proxyResolvers.map((resolver) => resolver.toXrayDnsServer()));
    return servers;
  }

  Map<String, dynamic> toXrayDnsConfig() {
    return <String, dynamic>{
      'servers': buildDnsServers(),
      'queryStrategy': 'UseIPv4',
      'disableFallbackIfMatch': true,
    };
  }
}

class RoutePolicy {
  final DomainSets domainSets;
  final List<String> tunnelDnsServers4;
  final List<String> tunnelDnsServers6;
  final bool captureSystemDnsToBuiltInDns;

  const RoutePolicy({
    required this.domainSets,
    required this.tunnelDnsServers4,
    required this.tunnelDnsServers6,
    required this.captureSystemDnsToBuiltInDns,
  });

  List<String> tunDnsCidrs() {
    return <String>[
      ...tunnelDnsServers4.map((value) => '$value/32'),
      ...tunnelDnsServers6.map((value) => '$value/128'),
    ];
  }

  List<Map<String, dynamic>> buildSecureDnsRules({
    required bool enableTunnelMode,
    required String tunInboundTag,
    required List<String> directResolverInboundTags,
    required List<String> proxyResolverInboundTags,
    required bool fakeDnsEnabled,
  }) {
    return <Map<String, dynamic>>[
      if (enableTunnelMode && captureSystemDnsToBuiltInDns)
        <String, dynamic>{
          'type': 'field',
          'inboundTag': <String>[tunInboundTag],
          'network': 'tcp,udp',
          'port': '53',
          'ip': tunDnsCidrs(),
          'outboundTag': 'dns',
        },
      if (domainSets.direct.isNotEmpty)
        <String, dynamic>{
          'type': 'field',
          'domain': domainSets.direct,
          'outboundTag': 'direct',
        },
      if (domainSets.directIpCidrs.isNotEmpty)
        <String, dynamic>{
          'type': 'field',
          'ip': domainSets.directIpCidrs,
          'outboundTag': 'direct',
        },
      if (fakeDnsEnabled && domainSets.fake.isNotEmpty)
        <String, dynamic>{
          'type': 'field',
          'domain': domainSets.fake,
          'outboundTag': 'proxy',
        },
      <String, dynamic>{
        'type': 'field',
        'inboundTag': directResolverInboundTags,
        'outboundTag': 'direct',
      },
      <String, dynamic>{
        'type': 'field',
        'inboundTag': proxyResolverInboundTags,
        'outboundTag': 'proxy',
      },
    ];
  }
}

class DnsControlPlane {
  final DnsPolicy dnsPolicy;
  final RoutePolicy routePolicy;

  const DnsControlPlane({
    required this.dnsPolicy,
    required this.routePolicy,
  });

  List<ResolverServerPolicy> get directResolvers => dnsPolicy.directResolvers;

  List<ResolverServerPolicy> get proxyResolvers => dnsPolicy.proxyResolvers;

  FakeDnsPolicy get fakeDns => dnsPolicy.fakeDns;

  DomainSets get domainSets => routePolicy.domainSets;

  List<String> get tunnelDnsServers4 => routePolicy.tunnelDnsServers4;

  List<String> get tunnelDnsServers6 => routePolicy.tunnelDnsServers6;

  List<Map<String, dynamic>> buildDnsServers() {
    return dnsPolicy.buildDnsServers();
  }

  List<String> tunDnsCidrs() {
    return routePolicy.tunDnsCidrs();
  }

  List<String> sniffingDestOverride() {
    final overrides = <String>['http', 'tls', 'quic'];
    if (fakeDns.enabled && fakeDns.domains.isNotEmpty) {
      overrides.add('fakedns');
    }
    return overrides;
  }
}
