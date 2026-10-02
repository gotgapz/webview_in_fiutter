import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

final _interactionEnabled = ValueNotifier<bool>(true);

void setWebViewInteractionEnabled(bool enabled) {
  _interactionEnabled.value = enabled;
}

void registerWebView() {
  ui_web.platformViewRegistry.registerViewFactory(
    'browser-iframe',
    (int viewId) {
      return html.IFrameElement()
        ..src = 'https://example.com'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    },
  );
}

Widget getWebViewBody(dynamic controller) {
  return const _BrowserFrame();
}

class _BrowserFrame extends StatefulWidget {
  const _BrowserFrame();

  @override
  State<_BrowserFrame> createState() => _BrowserFrameState();
}

class _BrowserFrameState extends State<_BrowserFrame> {
  html.IFrameElement? frame;

  @override
  void initState() {
    super.initState();
    _interactionEnabled.addListener(updateInteraction);
  }

  void updateInteraction() {
    // IgnorePointer alone cannot stop events inside a browser iframe.
    frame?.style.pointerEvents = _interactionEnabled.value ? 'auto' : 'none';
    if (!_interactionEnabled.value) frame?.blur();
  }

  @override
  void dispose() {
    _interactionEnabled.removeListener(updateInteraction);
    frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
    viewType: 'browser-iframe',
    onPlatformViewCreated: (id) {
      if (!mounted) return;
      frame = ui_web.platformViewRegistry.getViewById(id) as html.IFrameElement;
      updateInteraction();
    },
  );
}
