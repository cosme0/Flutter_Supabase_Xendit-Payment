import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class XenditWebViewScreen extends StatefulWidget {
  final String invoiceUrl;

  const XenditWebViewScreen({
    super.key,
    required this.invoiceUrl,
  });

  @override
  State<XenditWebViewScreen> createState() => _XenditWebViewScreenState();
}

class _XenditWebViewScreenState extends State<XenditWebViewScreen> {
  WebViewController? _controller;
  bool _isLoadingPage = true;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // If testing on Chrome Web, open Xendit in a new tab so it doesn't crash
      _launchInBrowser();
    } else {
      // If running on Android APK / iOS, use the embedded in-app WebView
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => setState(() => _isLoadingPage = true),
            onPageFinished: (_) => setState(() => _isLoadingPage = false),
          ),
        )
        ..loadRequest(Uri.parse(widget.invoiceUrl));
    }
  }

  Future<void> _launchInBrowser() async {
    final Uri uri = Uri.parse(widget.invoiceUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) {
      setState(() => _isLoadingPage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xendit Checkout'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
      body: kIsWeb
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.open_in_browser, size: 64, color: Colors.indigo),
                    const SizedBox(height: 16),
                    const Text(
                      'Xendit Checkout opened in a new browser tab.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'After simulating your payment on Xendit, click "Done" in the top right corner to verify your order.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _launchInBrowser,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-open Xendit Tab'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_controller != null) WebViewWidget(controller: _controller!),
                if (_isLoadingPage)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}