import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'unlockPrompt': 'Enter password to unlock',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'password': 'Password',
      'vpn': 'Tunnel Mode',
      'proxyOnly': 'Proxy Mode',
      'home': 'Home',
      'proxy': 'Proxy',
      'settings': 'Settings',
      'logs': 'Logs',
      'help': 'Help',
      'about': 'About',
      'addConfig': 'Add Config',
      'addNodeManualInput': 'Manual Input',
      'addNodeSubscriptionLink': 'Subscription Link',
      'addNodeScanQr': 'Scan QR Code',
      'addNodePickImage': 'Select Image',
      'addNodePickFile': 'Select File',
      'addNodeReadClipboard': 'Read Clipboard',
      'openSettingsImportHint':
          'Open Settings > Xray Management > Import Config',
      'clipboardNoVless': 'Clipboard does not contain a vless:// link',
      'autoImportInProgress': 'Parsing and importing...',
      'scanResultHint': 'Paste QR result (vless://...)',
      'startAcceleration': 'Start Acceleration',
      'stopAcceleration': 'Stop Acceleration',
      'highlightNode': 'Highlight Node',
      'homeStatusDuration': 'Duration',
      'homeStatusLatency': 'Latency',
      'homeStatusLocation': 'Location',
      'secondsSuffix': 's',
      'hoverHintSelected': 'Selected',
      'hoverHintClickToStart':
          'click the bottom-right button to start acceleration',
      'homeStatusUpload': 'Upload',
      'homeStatusDownload': 'Download',
      'homeStatusMemory': 'Memory',
      'homeStatusCpu': 'CPU',
      'homeStatusConnections': 'Connections',
      'homeStatusGood': 'Good',
      'homeStatusFair': 'Fair',
      'homeStatusHigh': 'High',
      'selectedNode': 'Selected Node',
      'nodeList': 'Node List',
      'addNode': 'Add Node',
      'addNodeHint': 'Tap the ＋ button in the\ntop-right corner to add a node',
      'recommendedNode': 'Recommended',
      'speed': 'Speed',
      'latency': 'Latency',
      'sniffing': 'Sniffing',
      'sniffingHint': 'Auto-detect traffic protocol',
      'fallbackProxy': 'Fallback to Proxy',
      'fallbackProxyHint': 'Route unmatched traffic via proxy',
      'fallbackDomain': 'Fallback to Domain',
      'fallbackDomainHint': 'Resolve unmatched traffic via domain',
      'ipv6ToDomain': 'IPv6 to Domain',
      'ipv6ToDomainHint': 'Redirect IPv6 requests to domain resolution',
      'socksPort': 'SOCKS Port',
      'httpPort': 'HTTP Port',
      'systemProxy': 'System Proxy',
      'proxySettings': 'Proxy Settings',
      'serviceRunning': '⚠️ Service already running',
      'noNodes': 'No nodes, please add.',
      'generateSave': 'Generate & Save',
      'addNodeConfig': 'Add Node Config',
      'vlessUri': 'VLESS URI (Optional)',
      'parseVlessUri': 'Parse Link',
      'vlessUriEmpty': 'Please paste a VLESS URI first',
      'vlessUriInvalid': 'Invalid VLESS URI',
      'vlessUriParsed': 'Parsed',
      'requiredFieldsMissing': 'Please fill in all required fields',
      'sudoMissing': 'Unable to read password',
      'bundleIdMissing': 'Bundle ID is not ready',
      'nodeName': 'Node Name (e.g., US-Node)',
      'serverDomain': 'Server Domain',
      'port': 'Port',
      'uuid': 'UUID',
      'openManual': 'Open Manual',
      'logExported': '📤 Logs exported to console',
      'clearLogs': '🧹 Clear logs',
      'exportLogs': '📤 Export logs',
      'settingsCenter': '⚙️ Settings',
      'xrayMgmt': 'Xray Management',
      'configMgmt': 'Config Management',
      'genDefaultNodes': 'Generate Default Nodes',
      'resetAll': 'Reset All Configs',
      'permissionGuide': 'Permissions Guide',
      'permissionGuideIntro':
          'Follow the steps below in Privacy & Security to grant permissions:',
      'permissionGuideSteps':
          '1. Allow the app to read and write its Application Support directory\n2. Allow System VPN (NetworkExtension / Packet Tunnel)\n3. When macOS shows the authorization prompt for Xstream, choose Allow\n4. Confirm LaunchAgent can start in the current user session\n5. Confirm the app can query system network settings',
      'openPrivacy': 'Open Privacy & Security',
      'permissionFinished': 'All permissions completed',
      'permissionGuideFailureTitle': 'System VPN authorization needed',
      'permissionGuideFailureIntro':
          'The Secure Tunnel could not start because macOS has not granted the required authorization yet. Complete the checks below, approve the System VPN request for Xstream, then retry.',
      'permissionGuideLastError': 'Last start error',
      'permissionCheckAppSupport': 'Config Directory Read/Write',
      'permissionCheckPacketTunnel': 'System VPN Packet Tunnel Permission',
      'permissionCheckLaunchAgent': 'LaunchAgent Bootstrap Context',
      'permissionCheckNetworkQuery': 'System Network Query Capability',
      'permissionStatusPass': 'PASS',
      'permissionStatusFail': 'FAIL',
      'permissionGuideAllPassed': 'All required permissions are available.',
      'permissionGuideNeedsFix':
          'Some checks failed. Complete system permissions and retry.',
      'permissionRecheck': 'Recheck',
      'permissionBootstrapHint':
          'If you see "Bootstrap failed: 5", run app in a normal desktop user session and verify LaunchAgent permissions.',
      'permissionGuideTunnelDeniedHint':
          'If the last error contains "permission denied", open Privacy & Security and approve the System VPN request for Xstream.',
      'syncConfig': 'Sync Config',
      'deleteConfig': 'Delete Config',
      'saveConfig': 'Save Config',
      'importConfig': 'Import Config',
      'exportConfig': 'Export Config',
      'advancedConfig': 'Advanced',
      'xhttpAdvancedTitle': 'XHTTP Transport',
      'xhttpAdvancedHint':
          'Applies to xhttp nodes. Default mode is auto and default ALPN is h3 + h2 + http/1.1.',
      'xhttpModeLabel': 'Mode',
      'xhttpModeStreamUp': 'stream-up',
      'xhttpModeAuto': 'auto',
      'xhttpAlpnLabel': 'TLS ALPN',
      'xhttpAlpnH3': 'HTTP/3 (h3)',
      'xhttpAlpnH2': 'HTTP/2 (h2)',
      'xhttpAlpnHttp11': 'HTTP/1.1',
      'xhttpResetDraft': 'Reset',
      'xhttpSaveApply': 'Save / Apply',
      'xhttpSavedApplied': 'XHTTP advanced config saved and applied',
      'tunSettings': 'TUN Settings',
      'dnsOverHttps': 'DNS over HTTPS',
      'dnsOverHttpsHint':
          'Controls the Proxy Resolver transport for Xray Secure DNS. On macOS and iOS, Packet Tunnel DNS queries also enter the local Secure DNS path and then follow Direct Resolver or Proxy Resolver policy.',
      'tunStatus': 'TUN Status',
      'tunStatusConnected': 'Connected',
      'tunStatusConnecting': 'Connecting',
      'tunStatusDisconnected': 'Disconnected',
      'tunStatusDisconnecting': 'Disconnecting',
      'tunStatusInvalid': 'Invalid',
      'tunStatusReasserting': 'Reasserting',
      'tunStatusNotConfigured': 'Not configured',
      'tunStatusUnsupported': 'Unsupported',
      'tunStatusUnknown': 'Unknown',
      'dnsConfig': 'DNS Settings',
      'directDnsConfig': 'Direct Resolver',
      'proxyDnsConfig': 'Proxy Resolver',
      'primaryDns': 'Primary DNS',
      'secondaryDns': 'Secondary DNS',
      'dnsDialogHintDoh':
          'Enter HTTPS endpoints such as https://1.1.1.1/dns-query.',
      'dnsDialogHintPlain':
          'Enter DNS server addresses such as 1.1.1.1 or dns.google.',
      'dnsDialogHintDirect':
          'Enter direct DNS server addresses for the Direct Resolver policy and for system DNS override on platforms that do not yet use the local Secure DNS endpoint.',
      'globalProxy': 'Global Proxy',
      'experimentalFeatures': 'Experimental Features',
      'tunnelProxyMode': 'Tunnel Mode',
      'modeSwitch': 'Switch Connection Mode',
      'vpnDesc': 'tunxxx interface',
      'proxyDesc': 'socks5://127.0.0.1:1080  http://127.0.0.1:1081',
      'unlockFirst': 'Please unlock to init',
      'upgradeDaily': 'Upgrade DailyBuild',
      'viewCollected': 'View collected data',
      'checkUpdate': 'Check Update',
      'collectedData': 'Collected Data',
      'close': 'Close',
      'upToDate': 'Already up to date',
      'language': 'Language',
      'desktopSync': 'Desktop Sync',
      'accountLogin': 'Account Login',
      'serverAddress': 'Server Address',
      'username': 'Username',
      'accountOrEmail': 'Email or Username',
      'login': 'Login',
      'verifyMfa': 'Verify MFA',
      'logout': 'Logout',
      'mfaCode': 'MFA Code',
      'mfaCodeMissing': 'Please input MFA code',
      'mfaRequiredHint': 'Enter the 6-digit code from your authenticator app',
      'syncNow': 'Sync Now',
      'lastSyncTime': 'Last Sync',
      'never': 'Never',
      'configVersion': 'Config Version',
      'subscriptionMetadata': 'Subscription',
      'syncInProgress': 'Syncing...',
      'syncStatusNoPrivilege': 'No desktop sync privilege',
      'syncNotLoggedIn': 'Login required',
      'loginMissingFields': 'Please fill in all login fields',
      'logoutSuccess': 'Logged out',
      'runtimeMcpServer': 'Runtime MCP Server',
      'runtimeMcpStatusRunning': 'Running',
      'runtimeMcpStatusStopped': 'Stopped',
      'runtimeMcpStatusUnavailable': 'Unavailable (runtime launcher not found)',
      'runtimeMcpStatusLoading': 'Applying...',
      'runtimeMcpStarted': 'Runtime MCP Server started',
      'runtimeMcpStopped': 'Runtime MCP Server stopped',
      'runtimeMcpToggleFailed': 'Runtime MCP Server toggle failed',
      'helpSupportTitle': 'Self-Service Support',
      'helpSupportIntro':
          'Use this page to separate Packet Tunnel startup problems from DNS, TLS, site challenge, node transport, and runtime config issues.',
      'helpOpenRunbook': 'Open Troubleshooting Runbook',
      'helpQuickCheckTitle': 'Quick Checks',
      'helpQuickCheckItem1':
          'If Tunnel Mode and Proxy Mode both fail, check node validity and runtime logs first.',
      'helpQuickCheckItem2':
          'If Proxy Mode works but Tunnel Mode fails, prioritize Tunnel data-plane differences instead of Packet Tunnel startup.',
      'helpQuickCheckItem3':
          'If DNS resolves and TLS handshake succeeds, the issue is usually not basic host connectivity.',
      'helpQuickCheckItem4':
          'If the target returns a challenge page, investigate site-side filtering, current exit reputation, and node transport stability.',
      'helpModeDiffTitle': 'Tunnel vs Proxy',
      'helpModeDiffIntro':
          'Tunnel Mode sends system traffic through Packet Tunnel. Proxy Mode sends browser traffic through local SOCKS/HTTP proxy ports.',
      'helpModeDiffItem1':
          'Tunnel Mode may preserve site-facing behavior such as QUIC / HTTP3, system DNS, and challenge-sensitive flows.',
      'helpModeDiffItem2':
          'Proxy Mode often falls back to TCP proxy behavior, so some sites can work there first.',
      'helpModeDiffItem3':
          'If a site works only in Proxy Mode, compare the same URL through both paths before changing core configuration.',
      'helpDnsTlsTitle': 'DNS / TLS / Config',
      'helpDnsTlsIntro':
          'Check these items before assuming the node or Secure Tunnel is broken.',
      'helpDnsTlsItem1':
          'Review DNS settings in Settings and confirm Tunnel DNS values match the expected host-side policy.',
      'helpDnsTlsItem2':
          'Inspect runtime config.json to confirm outbound transport, DNS servers, and routing rules are correct.',
      'helpDnsTlsItem3':
          'Inspect xray-runtime.log for challenge responses, INTERNAL_ERROR, unexpected EOF, and transport failures.',
      'helpPathsTitle': 'Local Paths',
      'helpNodesPathLabel': 'Saved node list',
      'helpRuntimeConfigLabel': 'Current runtime config',
      'helpRuntimeLogLabel': 'Current runtime log',
      'helpOpenConfigDir': 'Open Config Directory',
      'helpOpenLogsDir': 'Open Logs Directory',
      'helpLoading': 'Loading...',
      'helpCommandsTitle': 'Reference Commands',
      'helpCommandsIntro':
          'Run these commands in Terminal to compare system path, local proxy path, DNS, TLS, and runtime files.',
      'helpCommandsBlock':
          r'''BASE="$HOME/Library/Application Support/plus.svc.xstream"

cat "$BASE/vpn_nodes.json"
cat "$BASE/configs/config.json"
tail -n 200 "$BASE/logs/xray-runtime.log"

dig +short grok.com
echo | openssl s_client -connect grok.com:443 -servername grok.com -brief

curl -I --max-time 15 https://grok.com
curl -I --proxy socks5h://127.0.0.1:1080 --max-time 15 https://grok.com''',
    },
    'zh': {
      'unlockPrompt': '输入密码解锁',
      'cancel': '取消',
      'confirm': '确认',
      'password': '密码',
      'vpn': '隧道模式',
      'proxyOnly': '代理模式',
      'home': '首页',
      'proxy': '节点',
      'settings': '设置',
      'logs': '日志',
      'help': '帮助',
      'about': '关于',
      'addConfig': '添加配置文件',
      'addNodeManualInput': '手动输入',
      'addNodeSubscriptionLink': '订阅链接',
      'addNodeScanQr': '扫描二维码',
      'addNodePickImage': '选择图片',
      'addNodePickFile': '选择文件',
      'addNodeReadClipboard': '读取剪贴板',
      'openSettingsImportHint': '请在 设置 > Xray 管理 中使用导入配置',
      'clipboardNoVless': '剪贴板中没有 vless:// 链接',
      'autoImportInProgress': '正在解析并导入...',
      'scanResultHint': '粘贴扫码结果（vless://...）',
      'startAcceleration': '启动加速',
      'stopAcceleration': '停止加速',
      'highlightNode': '高亮该节点',
      'homeStatusDuration': '持续时间',
      'homeStatusLatency': '延迟',
      'homeStatusLocation': '位置',
      'secondsSuffix': '秒',
      'hoverHintSelected': '已选中',
      'hoverHintClickToStart': '点击右下角按钮启动加速',
      'homeStatusUpload': '上传',
      'homeStatusDownload': '下载',
      'homeStatusMemory': '内存',
      'homeStatusCpu': 'CPU',
      'homeStatusConnections': '连接数',
      'homeStatusGood': '良好',
      'homeStatusFair': '一般',
      'homeStatusHigh': '偏高',
      'selectedNode': '已选节点',
      'nodeList': '节点列表',
      'addNode': '添加节点',
      'addNodeHint': '点击右上角 ＋ 按钮\n添加加速节点',
      'recommendedNode': '推荐节点',
      'speed': '速度',
      'latency': '延迟',
      'sniffing': '嗅探',
      'sniffingHint': '自动检测流量协议',
      'fallbackProxy': '回退到代理',
      'fallbackProxyHint': '将未匹配的流量通过代理转发',
      'fallbackDomain': '回退到域名',
      'fallbackDomainHint': '将未匹配的流量通过域名解析',
      'ipv6ToDomain': 'IPv6 转域名',
      'ipv6ToDomainHint': '将 IPv6 请求重定向到域名解析',
      'socksPort': 'SOCKS 端口',
      'httpPort': 'HTTP 端口',
      'systemProxy': '系统代理',
      'proxySettings': '代理设置',
      'serviceRunning': '⚠️ 服务已在运行',
      'noNodes': '暂无加速节点，请先添加。',
      'generateSave': '生成配置并保存',
      'addNodeConfig': '添加加速节点配置',
      'vlessUri': 'VLESS 链接（可选）',
      'parseVlessUri': '解析链接',
      'vlessUriEmpty': '请先粘贴 VLESS 链接',
      'vlessUriInvalid': 'VLESS 链接无效',
      'vlessUriParsed': '解析成功',
      'requiredFieldsMissing': '请填写所有必填项',
      'sudoMissing': '无法读取密码',
      'bundleIdMissing': 'Bundle ID 尚未初始化',
      'nodeName': '节点名（如 US-Node）',
      'serverDomain': '服务器域名',
      'port': '端口号',
      'uuid': 'UUID',
      'openManual': '打开使用文档',
      'logExported': '📤 日志已导出至控制台',
      'clearLogs': '🧹 清空日志',
      'exportLogs': '📤 导出日志',
      'settingsCenter': '⚙️ 设置中心',
      'xrayMgmt': 'Xray 管理',
      'configMgmt': '配置管理',
      'genDefaultNodes': '生成默认节点',
      'resetAll': '重置所有配置',
      'permissionGuide': '系统权限向导',
      'permissionGuideIntro': '请在“隐私与安全性”中完成以下步骤：',
      'permissionGuideSteps':
          '1. 允许应用读写 Application Support 配置目录\n2. 允许系统级 VPN（NetworkExtension / Packet Tunnel）权限\n3. 当 macOS 弹出 Xstream 授权提示时，选择允许\n4. 确认 LaunchAgent 能在当前用户会话中启动\n5. 确认应用可以查询系统网络设置',
      'openPrivacy': '打开隐私与安全性',
      'permissionFinished': '权限检查已完成',
      'permissionGuideFailureTitle': '需要完成系统 VPN 授权',
      'permissionGuideFailureIntro':
          'Secure Tunnel 启动失败，macOS 尚未完成所需授权。请先完成下面的检查项，并在系统弹窗中允许 Xstream 后重试。',
      'permissionGuideLastError': '最近启动错误',
      'permissionCheckAppSupport': '配置目录读写',
      'permissionCheckPacketTunnel': '系统 VPN Packet Tunnel 权限',
      'permissionCheckLaunchAgent': 'LaunchAgent 启动上下文',
      'permissionCheckNetworkQuery': '系统网络查询能力',
      'permissionStatusPass': '通过',
      'permissionStatusFail': '未通过',
      'permissionGuideAllPassed': '所有必要权限均已就绪。',
      'permissionGuideNeedsFix': '部分检查未通过，请完成系统权限后重试。',
      'permissionRecheck': '重新检查',
      'permissionBootstrapHint':
          '若出现“Bootstrap failed: 5”，请在普通桌面用户会话运行应用并确认 LaunchAgent 权限。',
      'permissionGuideTunnelDeniedHint':
          '若最近错误包含“permission denied”，请打开“隐私与安全性”，完成 Xstream 的系统 VPN 授权后再重试。',
      'syncConfig': '同步配置',
      'deleteConfig': '删除配置',
      'saveConfig': '保存配置',
      'importConfig': '导入配置',
      'exportConfig': '导出配置',
      'advancedConfig': '高级配置',
      'xhttpAdvancedTitle': 'XHTTP 传输参数',
      'xhttpAdvancedHint':
          '仅对 xhttp 节点生效。默认 mode=auto，默认 ALPN=h3 + h2 + http/1.1。',
      'xhttpModeLabel': 'Mode',
      'xhttpModeStreamUp': 'stream-up',
      'xhttpModeAuto': 'auto',
      'xhttpAlpnLabel': 'TLS ALPN',
      'xhttpAlpnH3': 'HTTP/3 (h3)',
      'xhttpAlpnH2': 'HTTP/2 (h2)',
      'xhttpAlpnHttp11': 'HTTP/1.1',
      'xhttpResetDraft': '重置',
      'xhttpSaveApply': '保存/应用',
      'xhttpSavedApplied': 'XHTTP 高级配置已保存并应用',
      'tunSettings': 'TUN 设置',
      'dnsOverHttps': 'DNS over HTTPS',
      'dnsOverHttpsHint':
          '控制代理 DNS 的传输方式，用于 Xray Secure DNS。在 macOS 和 iOS 上，Packet Tunnel 内的系统 DNS 查询也会进入本地 Secure DNS 路径，再按直连 DNS 或代理 DNS 策略处理。',
      'tunStatus': 'TUN 状态',
      'tunStatusConnected': '已连接',
      'tunStatusConnecting': '连接中',
      'tunStatusDisconnected': '已断开',
      'tunStatusDisconnecting': '断开中',
      'tunStatusInvalid': '无效配置',
      'tunStatusReasserting': '重试中',
      'tunStatusNotConfigured': '未配置',
      'tunStatusUnsupported': '不支持',
      'tunStatusUnknown': '未知',
      'dnsConfig': 'DNS 配置',
      'directDnsConfig': '直连 DNS',
      'proxyDnsConfig': '代理 DNS',
      'primaryDns': '主 DNS',
      'secondaryDns': '备用 DNS',
      'dnsDialogHintDoh': '请输入 HTTPS 端点，例如 https://1.1.1.1/dns-query。',
      'dnsDialogHintPlain': '请输入 DNS 服务器地址，例如 1.1.1.1 或 dns.google。',
      'dnsDialogHintDirect':
          '请输入直连 DNS 服务器地址，用于 Direct Resolver 策略，并继续作为尚未接入本地 Secure DNS 端点平台上的系统 DNS 来源。',
      'globalProxy': '全局代理',
      'experimentalFeatures': '实验特性',
      'tunnelProxyMode': '隧道模式',
      'modeSwitch': '切换连接模式',
      'vpnDesc': 'tunxxx网卡',
      'proxyDesc': 'socks5://127.0.0.1:1080  http://127.0.0.1:1081',
      'unlockFirst': '请先解锁以执行初始化操作',
      'upgradeDaily': '升级 DailyBuild',
      'viewCollected': '查看收集内容',
      'checkUpdate': '检查更新',
      'collectedData': '收集内容',
      'close': '关闭',
      'upToDate': '已是最新版本',
      'language': '语言',
      'desktopSync': '桌面同步',
      'accountLogin': '账号登录',
      'serverAddress': '服务地址',
      'username': '账号',
      'accountOrEmail': '邮箱或账号',
      'login': '登录',
      'verifyMfa': '验证 MFA',
      'logout': '退出登录',
      'mfaCode': 'MFA 验证码',
      'mfaCodeMissing': '请输入 MFA 验证码',
      'mfaRequiredHint': '请输入认证器中的 6 位验证码',
      'syncNow': '立即同步',
      'lastSyncTime': '最近同步',
      'never': '从未',
      'configVersion': '配置版本',
      'subscriptionMetadata': '订阅信息',
      'syncInProgress': '正在同步...',
      'syncStatusNoPrivilege': '账号无桌面同步权限',
      'syncNotLoggedIn': '请先登录',
      'loginMissingFields': '请填写完整的登录信息',
      'logoutSuccess': '已退出登录',
      'runtimeMcpServer': '运行态 MCP Server',
      'runtimeMcpStatusRunning': '运行中',
      'runtimeMcpStatusStopped': '已停止',
      'runtimeMcpStatusUnavailable': '不可用（未找到运行态启动器）',
      'runtimeMcpStatusLoading': '处理中...',
      'runtimeMcpStarted': '运行态 MCP Server 已启动',
      'runtimeMcpStopped': '运行态 MCP Server 已停止',
      'runtimeMcpToggleFailed': '运行态 MCP Server 切换失败',
      'helpSupportTitle': '自助排查支持',
      'helpSupportIntro':
          '本页用于区分 Packet Tunnel 启动问题与 DNS、TLS、站点 challenge、节点传输层、运行时配置等问题。',
      'helpOpenRunbook': '打开排查手册',
      'helpQuickCheckTitle': '快速判断',
      'helpQuickCheckItem1': '如果 Tunnel Mode 和 Proxy Mode 都失败，先检查节点本身与运行日志。',
      'helpQuickCheckItem2':
          '如果 Proxy Mode 正常而 Tunnel Mode 失败，优先怀疑 Tunnel 数据面差异，而不是 Packet Tunnel 启动失败。',
      'helpQuickCheckItem3': '如果 DNS 可解析、TLS 可握手，通常不是基础主机连通性问题。',
      'helpQuickCheckItem4': '如果目标站点返回 challenge 页面，应优先检查站点侧策略、当前出口信誉和节点传输稳定性。',
      'helpModeDiffTitle': 'Tunnel 与 Proxy 差异',
      'helpModeDiffIntro':
          'Tunnel Mode 通过 Packet Tunnel 接管系统流量，Proxy Mode 则通过本地 SOCKS/HTTP 代理端口转发浏览器流量。',
      'helpModeDiffItem1':
          'Tunnel Mode 更可能保留 QUIC / HTTP3、系统 DNS 和对 challenge 更敏感的访问行为。',
      'helpModeDiffItem2':
          'Proxy Mode 往往退回到基于 TCP 的代理语义，因此有些站点会先在 Proxy Mode 可用。',
      'helpModeDiffItem3':
          '如果站点只在 Proxy Mode 可用，先对比同一 URL 的两条访问路径，再决定是否调整核心配置。',
      'helpDnsTlsTitle': 'DNS / TLS / 配置文件',
      'helpDnsTlsIntro': '在判断节点或 Secure Tunnel 故障前，请先检查以下项目。',
      'helpDnsTlsItem1': '在设置页确认 DNS 配置和 Tunnel DNS 配置符合当前主机侧策略。',
      'helpDnsTlsItem2':
          '检查运行时 config.json，确认 outbound 传输、DNS 服务器与 routing 规则是否正确。',
      'helpDnsTlsItem3':
          '检查 xray-runtime.log，重点关注 challenge、INTERNAL_ERROR、unexpected EOF 与传输失败。',
      'helpPathsTitle': '本地路径',
      'helpNodesPathLabel': '已保存节点列表',
      'helpRuntimeConfigLabel': '当前运行时配置',
      'helpRuntimeLogLabel': '当前运行时日志',
      'helpOpenConfigDir': '打开配置目录',
      'helpOpenLogsDir': '打开日志目录',
      'helpLoading': '加载中...',
      'helpCommandsTitle': '参考命令',
      'helpCommandsIntro': '可在终端执行这些命令，对比系统路径、本地代理路径、DNS、TLS 与运行时文件。',
      'helpCommandsBlock':
          r'''BASE="$HOME/Library/Application Support/plus.svc.xstream"

cat "$BASE/vpn_nodes.json"
cat "$BASE/configs/config.json"
tail -n 200 "$BASE/logs/xray-runtime.log"

dig +short grok.com
echo | openssl s_client -connect grok.com:443 -servername grok.com -brief

curl -I --max-time 15 https://grok.com
curl -I --proxy socks5h://127.0.0.1:1080 --max-time 15 https://grok.com''',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']![key] ??
        key;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

extension LocalizationExtension on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations)!;
}
