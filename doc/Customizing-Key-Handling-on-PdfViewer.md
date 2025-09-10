Because [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) handles certain keys to allow users to scroll/zoom PDF view by keyboards, it may sometimes interfere with other widget's key handling, such as [TextField](https://api.flutter.dev/flutter/material/TextField-class.html)'s text input.

To customize the key handling behavior, you can use [PdfViewerParams.onKey](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onKey.html) and [PdfViewerParams.keyHandlerParams](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/keyHandlerParams.html).

## Default implementation

By default, [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) handles the following keys: 

Key | Description
------------|----------------------
[pageUp](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/pageUp-constant.html) | Scroll up
[pageDown](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/pageDown-constant.html) | Scroll up
[home](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/home-constant.html) | Go to first page
[end](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/end-constant.html) | go to last page
[equal](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/equal-constant.html) | Combination with `⌘`/`Ctrl` to zoom up (**currently not I18N-ed**)
[minus](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/equal-constant.html) | Combination with `⌘`/`Ctrl` to zoom down
[arrowUp](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/arrowUp-constant.html) | Scroll upward
[arrowDown](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/arrowDown-constant.html) | Scroll downward
[arrowLeft](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/arrowLeft-constant.html) | Scroll to left
[arrowRight](https://api.flutter.dev/flutter/services/LogicalKeyboardKey/arrowRight-constant.html) | Scroll to right

And, the other keys are **not handled** and handled by other widgets.

## Overriding the default implementation

The following fragment illustrates how to use [PdfViewerParams.onKey](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewerParams/onKey.html):

```dart
onKey: (params, key, isRealKeyPress) {
  if (key == LogicalKeyboardKey.space) {
    // handling the key inside the function
    handleSpace();
    return true;
  }
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
    // returning false to disable the default logic
    return false;
  }
  // returning null to let the default logic to handle the keys
  return null;
},
```

