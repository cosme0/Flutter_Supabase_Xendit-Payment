import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hosts the Xendit checkout page inside the app.
///
/// The screen only shows the Xendit page - it never decides on its own that
/// a payment was successful. When the customer taps "Done" the app returns
/// to the store and asks the **server** for the verified order status.
class XenditWebViewScreen extends StatefulWidget {
  const XenditWebViewScreen({
    super.key,
    required this.invoiceUrl,
    this.orderId,
  });

  /// The checkout url that was returned by the `create-invoice` edge
  /// function.
  final String invoiceUrl;

  /// The order the checkout belongs to (used for logging only).
  final String? orderId;

  @override
  State<XenditWebViewScreen> createState() => _XenditWebViewScreenState();
}

class _XenditWebViewScreenState extends State<XenditWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
      return;
    }

    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    'The checkout page could not be loaded (${error.description}).';
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Only https pages are allowed inside the checkout.
            if (!request.url.startsWith('https://')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.invoiceUrl));

    _controller = controller;
  }

  Future<void> _openInBrowser() async {
    final Uri uri = Uri.parse(widget.invoiceUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No browser is available on this device.'),
        ),
      );
    }
  }

  Future<void> _retry() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _controller?.loadRequest(Uri.parse(widget.invoiceUrl));
  }

  Future<void> _confirmCancel() async {
    final bool? shouldLeave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Cancel checkout?'),
        content: const Text(
          'The payment was not completed yet. The order stays pending until '
          'the invoice expires.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep paying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _confirmCancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Xendit Checkout'),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildHint(),
      ),
    );
  }

  Widget _buildBody() {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.open_in_browser_rounded, size: 64),
              const SizedBox(height: 16),
              const Text(
                'The checkout page opens in your browser.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete the payment and come back to the store, then tap '
                '"Done" to verify the order.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open checkout'),
              ),
            ],
          ),
        ),
      );
    }

    final WebViewController? controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reload'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        WebViewWidget(controller: controller),
        if (_isLoading)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading the secure checkout...'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHint() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const SafeArea(
        top: false,
        child: Text(
          'Complete the payment in the Xendit page, then tap "Done". The order '
          'is only marked as PAID after the server confirms the payment.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
