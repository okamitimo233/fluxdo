import 'package:flutter/material.dart';

import '../../../services/network/proxy/proxy_settings_service.dart';
import '../../../services/network/proxy/shadowsocks_uri_parser.dart';
import '../../../services/network/vpn_auto_toggle_service.dart';
import '../../../services/toast_service.dart';

class HttpProxyCard extends StatelessWidget {
  const HttpProxyCard({
    super.key,
    required this.proxySettings,
    required this.dohEnabled,
    this.isSuppressedByVpn = false,
  });

  final ProxySettings proxySettings;
  final bool dohEnabled;
  final bool isSuppressedByVpn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proxyService = ProxySettingsService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        proxyService.isTesting,
        proxyService.testResultNotifier,
      ]),
      builder: (context, _) {
        final isTesting = proxyService.isTesting.value;
        final testResult = proxyService.testResultNotifier.value;

        return Card(
          clipBehavior: Clip.antiAlias,
          color: proxySettings.enabled
              ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: proxySettings.enabled
                ? BorderSide(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
                  )
                : BorderSide.none,
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('上游代理'),
                subtitle: Text(
                  isSuppressedByVpn
                      ? '已被 VPN 自动关闭，VPN 断开后将自动恢复'
                      : proxySettings.enabled
                          ? '已启用 ${proxySettings.protocol.displayName} 上游代理，由本地网关统一转发'
                          : '为本地网关配置远端 HTTP / SOCKS5 / Shadowsocks 代理',
                ),
                secondary: Icon(
                  proxySettings.enabled ? Icons.vpn_key : Icons.vpn_key_outlined,
                  color: proxySettings.enabled
                      ? theme.colorScheme.tertiary
                      : null,
                ),
                value: proxySettings.enabled,
                onChanged: (value) async {
                  if (value && !proxySettings.hasServer) {
                    final saved = await _showProxyConfigDialog(
                      context,
                      proxySettings,
                    );
                    if (!saved) {
                      return;
                    }
                  }

                  await proxyService.setEnabled(value);
                  // 用户在 VPN 活跃时手动开启，清除压制标记
                  if (value && isSuppressedByVpn) {
                    VpnAutoToggleService.instance.clearProxySuppression();
                  }
                  if (!value) {
                    return;
                  }

                  final previous = proxyService.testResultNotifier.value;
                  final shouldRetest = previous == null ||
                      !previous.success ||
                      DateTime.now().difference(previous.testedAt) >
                          const Duration(seconds: 30);
                  if (shouldRetest) {
                    await _runProxyTest(showToast: true);
                  }
                },
              ),
              if (proxySettings.hasServer || proxySettings.enabled) ...[
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('上游代理服务器'),
                  subtitle: Text(
                    proxySettings.host.isNotEmpty
                        ? _buildProxySummary(proxySettings)
                        : '未配置',
                  ),
                  trailing: const Icon(Icons.edit, size: 20),
                  onTap: () => _showProxyConfigDialog(context, proxySettings),
                ),
                if (!proxySettings.isShadowsocks &&
                    proxySettings.username != null &&
                    proxySettings.username!.isNotEmpty) ...[
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('认证'),
                    subtitle: Text('用户名: ${proxySettings.username}'),
                    dense: true,
                  ),
                ],
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
                ListTile(
                  leading: Icon(
                    _resolveTestIcon(isTesting, testResult),
                    color: _resolveTestColor(theme, isTesting, testResult),
                  ),
                  title: const Text('测试代理可用性'),
                  subtitle: Text(
                    _buildTestSubtitle(
                      isTesting: isTesting,
                      testResult: testResult,
                      protocol: proxySettings.protocol,
                    ),
                  ),
                  trailing: isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _runProxyTest(showToast: true),
                          child: const Text('测试'),
                        ),
                  onTap: isTesting ? null : () => _runProxyTest(showToast: true),
                ),
                if (proxySettings.enabled && dohEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前会通过本地 DoH 网关转发到上游代理；关闭 DoH 时会切换为纯代理转发',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (!proxySettings.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '开启后会保留代理模式开关，由本地网关统一接管 Dio、WebView 和 Shadowsocks 出口',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<ProxyTestResult> _runProxyTest({required bool showToast}) async {
    final proxyService = ProxySettingsService.instance;
    final result = await proxyService.testCurrentAvailability();
    if (showToast) {
      if (result.success) {
        final latency =
            result.latency == null ? '' : ' · ${result.latency!.inMilliseconds}ms';
        ToastService.showSuccess('${result.detail}$latency');
      } else {
        ToastService.showError(result.detail);
      }
    }
    return result;
  }

  Future<bool> _showProxyConfigDialog(
    BuildContext context,
    ProxySettings proxySettings,
  ) async {
    final proxyService = ProxySettingsService.instance;
    final hostController = TextEditingController(text: proxySettings.host);
    final portController = TextEditingController(
      text: proxySettings.port > 0 ? proxySettings.port.toString() : '',
    );
    final usernameController =
        TextEditingController(text: proxySettings.username ?? '');
    final passwordController =
        TextEditingController(text: proxySettings.password ?? '');

    var selectedProtocol = proxySettings.protocol;
    var requireAuth = !proxySettings.isShadowsocks &&
        ((proxySettings.username?.isNotEmpty ?? false) ||
            (proxySettings.password?.isNotEmpty ?? false));
    var selectedCipher = proxySettings.cipher.isNotEmpty
        ? proxySettings.cipher
        : ProxySettingsService.supportedShadowsocksCiphers[1];

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final isShadowsocks =
                selectedProtocol == UpstreamProxyProtocol.shadowsocks;
            final isShadowsocks2022 =
                ProxySettingsService.isShadowsocks2022Cipher(selectedCipher);
            return AlertDialog(
              title: const Text('配置上游代理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<UpstreamProxyProtocol>(
                      value: selectedProtocol,
                      decoration: const InputDecoration(labelText: '协议'),
                      items: UpstreamProxyProtocol.values
                          .map(
                            (item) => DropdownMenuItem<UpstreamProxyProtocol>(
                              value: item,
                              child: Text(item.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          selectedProtocol = value;
                          if (selectedProtocol ==
                              UpstreamProxyProtocol.shadowsocks) {
                            requireAuth = false;
                            if (selectedCipher.isEmpty) {
                              selectedCipher = ProxySettingsService
                                  .supportedShadowsocksCiphers[1];
                            }
                          }
                        });
                      },
                    ),
                    if (isShadowsocks) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final imported = await _showImportShadowsocksDialog(
                              dialogContext,
                            );
                            if (imported == null) {
                              return;
                            }
                            setState(() {
                              hostController.text = imported.host;
                              portController.text = imported.port.toString();
                              passwordController.text = imported.password;
                              selectedCipher = imported.cipher;
                            });
                            ToastService.showSuccess(
                              imported.remarks?.isNotEmpty == true
                                  ? '已导入节点：${imported.remarks}'
                                  : 'Shadowsocks 链接导入成功',
                            );
                          },
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('导入 ss:// 链接'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: '例如：192.168.1.1 或 proxy.example.com',
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portController,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '例如：8080 或 1080',
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    if (isShadowsocks) ...[
                      DropdownButtonFormField<String>(
                        value: selectedCipher,
                        decoration: const InputDecoration(labelText: '加密算法'),
                        items: ProxySettingsService.supportedShadowsocksCiphers
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            selectedCipher = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText:
                              isShadowsocks2022 ? '密钥（Base64 PSK）' : '密码',
                          hintText: isShadowsocks2022
                              ? '请输入 Base64 编码后的 32 字节预共享密钥'
                              : null,
                        ),
                        obscureText: true,
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Checkbox(
                            value: requireAuth,
                            onChanged: (value) {
                              setState(() {
                                requireAuth = value ?? false;
                              });
                            },
                          ),
                          const Text('需要认证'),
                        ],
                      ),
                      if (requireAuth) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: usernameController,
                          decoration: const InputDecoration(labelText: '用户名'),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordController,
                          decoration: const InputDecoration(labelText: '密码'),
                          obscureText: true,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final host = hostController.text.trim();
                    final portText = portController.text.trim();
                    if (host.isEmpty || portText.isEmpty) {
                      ToastService.showInfo('请填写服务器地址和端口');
                      return;
                    }
                    final port = int.tryParse(portText);
                    if (port == null || port <= 0 || port > 65535) {
                      ToastService.showError('端口无效');
                      return;
                    }
                    if (isShadowsocks) {
                      final normalizedCipher =
                          ProxySettingsService.normalizeShadowsocksCipher(
                        selectedCipher,
                      );
                      if (normalizedCipher.isEmpty) {
                        ToastService.showError('请选择受支持的 Shadowsocks 加密算法');
                        return;
                      }
                      final secretError =
                          ProxySettingsService.validateShadowsocksSecret(
                        cipher: normalizedCipher,
                        secret: passwordController.text.trim(),
                      );
                      if (secretError != null) {
                        ToastService.showError(secretError);
                        return;
                      }
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final isShadowsocks =
          selectedProtocol == UpstreamProxyProtocol.shadowsocks;
      await proxyService.setServer(
        protocol: selectedProtocol,
        host: hostController.text.trim(),
        port: int.tryParse(portController.text.trim()) ?? 0,
        username: isShadowsocks
            ? null
            : (requireAuth ? usernameController.text.trim() : null),
        password: isShadowsocks
            ? passwordController.text.trim()
            : (requireAuth ? passwordController.text.trim() : null),
        cipher: isShadowsocks ? selectedCipher : null,
      );
      await _runProxyTest(showToast: true);
    }

    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    return result == true;
  }

  Future<ShadowsocksUriConfig?> _showImportShadowsocksDialog(
    BuildContext context,
  ) async {
    final linkController = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('导入 ss:// 链接'),
          content: TextField(
            controller: linkController,
            decoration: const InputDecoration(
              labelText: 'Shadowsocks 链接',
              hintText: 'ss://...',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, linkController.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    linkController.dispose();

    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      return ShadowsocksUriParser.parse(value);
    } on FormatException catch (error) {
      ToastService.showError(error.message.toString());
      return null;
    } catch (error) {
      ToastService.showError(error.toString());
      return null;
    }
  }

  String _buildProxySummary(ProxySettings settings) {
    if (settings.isShadowsocks) {
      final cipher = settings.cipher.trim().isEmpty ? '未设置算法' : settings.cipher;
      return '${settings.protocol.displayName} · ${settings.host}:${settings.port} · $cipher';
    }
    return '${settings.protocol.displayName} · ${settings.host}:${settings.port}';
  }

  IconData _resolveTestIcon(bool isTesting, ProxyTestResult? testResult) {
    if (isTesting) {
      return Icons.network_check;
    }
    if (testResult == null) {
      return Icons.checklist_rtl_outlined;
    }
    return testResult.success ? Icons.check_circle_outline : Icons.error_outline;
  }

  Color? _resolveTestColor(
    ThemeData theme,
    bool isTesting,
    ProxyTestResult? testResult,
  ) {
    if (isTesting || testResult == null) {
      return theme.colorScheme.primary;
    }
    return testResult.success ? theme.colorScheme.primary : theme.colorScheme.error;
  }

  String _buildTestSubtitle({
    required bool isTesting,
    required ProxyTestResult? testResult,
    required UpstreamProxyProtocol protocol,
  }) {
    if (isTesting) {
      return protocol == UpstreamProxyProtocol.shadowsocks
          ? '正在校验 Shadowsocks 配置是否可由本地网关接管'
          : '正在验证是否能通过当前代理访问 linux.do';
    }
    if (testResult == null) {
      return protocol == UpstreamProxyProtocol.shadowsocks
          ? '保存后会校验 Shadowsocks 配置，并建议返回首页做实际访问验证'
          : '保存后会自动测试，也可以手动重新测试';
    }

    final latency = testResult.latency == null
        ? ''
        : ' · ${testResult.latency!.inMilliseconds}ms';
    return '${testResult.detail}$latency · ${_formatTime(testResult.testedAt)}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
