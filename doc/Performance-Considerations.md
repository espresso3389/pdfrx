# Performance Considerations

After `pdfrx` is first initialized, memory from Pdfium will not be cleaned up until the application terminates. Please see [#430](https://github.com/espresso3389/pdfrx/issues/430) and [#184](https://github.com/espresso3389/pdfrx/issues/184) for more info.
