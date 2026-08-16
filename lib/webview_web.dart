import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

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
  return const HtmlElementView(viewType: 'browser-iframe');
}
