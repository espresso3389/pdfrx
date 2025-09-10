To support password protected PDF files, use [passwordProvider](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPasswordProvider.html) to supply passwords interactively:

```dart
PdfViewer.asset(
  'assets/test.pdf',
  // Most easiest way to return some password
  passwordProvider: _showPasswordDialog,

  ...
),

...

Future<String?> _showPasswordDialog() async {
  final textController = TextEditingController();
  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Enter password'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
```

When [PdfViewer](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfViewer-class.html) tries to open a password protected document, it calls the function passed to `passwordProvider` (except the first attempt; see [below](#firstattemptbyemptypassword)) repeatedly to get a new password until the document is successfully opened. And if the function returns null, the viewer will give up the password trials and the function is no longer called.

### `firstAttemptByEmptyPassword`

By default, the first password attempt uses empty password. This is because encrypted PDF files frequently use empty password for viewing purpose. It's _normally_ useful but if you want to use authoring password, it can be disabled by setting `firstAttemptByEmptyPassword` to false.