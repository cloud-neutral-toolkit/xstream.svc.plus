// lib/templates/xray_config_template.dart

const String defaultXrayJsonTemplate = r'''
{
  "log": {
    "loglevel": "info"
  },
  "dns": {
    "servers": [],
    "queryStrategy": "UseIPv4",
    "disableFallbackIfMatch": true
  },
  "inbounds": <INBOUNDS_CONFIG>,
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
      "protocol": "dns"
    }
  ],
  "routing": {
    "rules": []
  }
}
''';
