// lib/templates/xray_config_template.dart

const String defaultXrayJsonTemplate = r'''
{
  "log": {
    "loglevel": "info"
  },
  "dns": {
    "servers": [
      {
        "address": "<DNS1>",
        "queryStrategy": "UseIPv4"
      },
      {
        "address": "<DNS2>",
        "queryStrategy": "UseIPv4"
      },
      {
        "address": "1.1.1.1",
        "queryStrategy": "UseIPv4"
      },
      {
        "address": "8.8.8.8",
        "queryStrategy": "UseIPv4"
      }
    ],
    "queryStrategy": "UseIPv4",
    "disableFallbackIfMatch": true
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 1081,
      "protocol": "http",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    },
    {
      "name": "xray0",
      "MTU": 1500,
      "UserLevel": 0
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "<SERVER_DOMAIN>",
            "port": <PORT>,
            "users": [
              {
                "id": "<UUID>",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "<SERVER_DOMAIN>",
          "allowInsecure": false,
          "fingerprint": "chrome"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    },
    {
      "tag": "dns",
      "protocol": "dns",
      "proxySettings": {
        "tag": "proxy"
      }
    }
  ],
  "routing": {
    "rules": []
  }
}
''';
