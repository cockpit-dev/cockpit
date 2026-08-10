import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import 'cockpit_windows_window_target.dart';

typedef CockpitWindowsScreenCaptureWriter =
    Future<void> Function({
      required CockpitWindowsWindowTarget target,
      required File outputFile,
      required Duration timeout,
    });

final class CockpitWindowsScreenCaptureException implements Exception {
  const CockpitWindowsScreenCaptureException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Future<void> cockpitWriteWindowsScreenCapture({
  required CockpitWindowsWindowTarget target,
  required File outputFile,
  required Duration timeout,
}) async {
  if (!Platform.isWindows) {
    throw const CockpitWindowsScreenCaptureException(
      'windowsHostRequired',
      'Windows screen capture requires a Windows host.',
    );
  }
  final stopwatch = Stopwatch()..start();
  Duration remaining() {
    final value = timeout - stopwatch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('Windows screen capture deadline expired.');
    }
    return value;
  }

  remaining();
  final bgra = _CockpitWindowsScreenCaptureApi.instance.capture(
    left: target.left,
    top: target.top,
    width: target.width,
    height: target.height,
  );
  remaining();
  final png = cockpitEncodeWindowsBgraPng(
    width: target.width,
    height: target.height,
    bytes: bgra,
  );
  final writeTimeout = remaining();
  try {
    await outputFile.writeAsBytes(png, flush: true).timeout(writeTimeout);
  } on TimeoutException {
    rethrow;
  } on FileSystemException catch (error) {
    throw CockpitWindowsScreenCaptureException(
      'windowsCaptureWriteFailed',
      'Windows could not write the screenshot: ${error.message}',
    );
  }
  remaining();
}

Uint8List cockpitEncodeWindowsBgraPng({
  required int width,
  required int height,
  required Uint8List bytes,
}) {
  final byteLength = _windowsCaptureByteLength(width, height);
  if (bytes.length != byteLength) {
    throw const CockpitWindowsScreenCaptureException(
      'invalidWindowsCapturePixels',
      'Windows screen capture returned an invalid pixel buffer.',
    );
  }
  final opaqueBgra = Uint8List.fromList(bytes);
  for (var offset = 3; offset < opaqueBgra.length; offset += 4) {
    opaqueBgra[offset] = 0xff;
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: opaqueBgra.buffer,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(
    img.encodePng(image, level: 1, filter: img.PngFilter.sub),
  );
}

int _windowsCaptureByteLength(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw const CockpitWindowsScreenCaptureException(
      'invalidWindowsCaptureBounds',
      'Windows screen capture requires positive bounds.',
    );
  }
  final pixelCount = width * height;
  if (pixelCount > _maximumWindowsCapturePixels) {
    throw CockpitWindowsScreenCaptureException(
      'windowsCaptureBoundsTooLarge',
      'Windows screen capture bounds exceed '
          '$_maximumWindowsCapturePixels pixels.',
    );
  }
  return pixelCount * 4;
}

final class _CockpitWindowsScreenCaptureApi {
  _CockpitWindowsScreenCaptureApi._()
    : _user32 = DynamicLibrary.open('user32.dll'),
      _gdi32 = DynamicLibrary.open('gdi32.dll') {
    _getDc = _user32.lookupFunction<_GetDcNative, _GetDcDart>('GetDC');
    _releaseDc = _user32.lookupFunction<_ReleaseDcNative, _ReleaseDcDart>(
      'ReleaseDC',
    );
    _createCompatibleDc = _gdi32
        .lookupFunction<_CreateCompatibleDcNative, _CreateCompatibleDcDart>(
          'CreateCompatibleDC',
        );
    _deleteDc = _gdi32.lookupFunction<_DeleteDcNative, _DeleteDcDart>(
      'DeleteDC',
    );
    _createCompatibleBitmap = _gdi32
        .lookupFunction<
          _CreateCompatibleBitmapNative,
          _CreateCompatibleBitmapDart
        >('CreateCompatibleBitmap');
    _selectObject = _gdi32
        .lookupFunction<_SelectObjectNative, _SelectObjectDart>('SelectObject');
    _deleteObject = _gdi32
        .lookupFunction<_DeleteObjectNative, _DeleteObjectDart>('DeleteObject');
    _bitBlt = _gdi32.lookupFunction<_BitBltNative, _BitBltDart>('BitBlt');
    _getDibits = _gdi32.lookupFunction<_GetDibitsNative, _GetDibitsDart>(
      'GetDIBits',
    );
  }

  static final _CockpitWindowsScreenCaptureApi instance =
      _CockpitWindowsScreenCaptureApi._();

  final DynamicLibrary _user32;
  final DynamicLibrary _gdi32;
  late final _GetDcDart _getDc;
  late final _ReleaseDcDart _releaseDc;
  late final _CreateCompatibleDcDart _createCompatibleDc;
  late final _DeleteDcDart _deleteDc;
  late final _CreateCompatibleBitmapDart _createCompatibleBitmap;
  late final _SelectObjectDart _selectObject;
  late final _DeleteObjectDart _deleteObject;
  late final _BitBltDart _bitBlt;
  late final _GetDibitsDart _getDibits;

  Uint8List capture({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final byteLength = _windowsCaptureByteLength(width, height);
    final screenDc = _getDc(0);
    if (screenDc == 0) {
      throw const CockpitWindowsScreenCaptureException(
        'windowsScreenDcUnavailable',
        'Windows could not access the system screen.',
      );
    }
    final memoryDc = _createCompatibleDc(screenDc);
    if (memoryDc == 0) {
      _releaseDc(0, screenDc);
      throw const CockpitWindowsScreenCaptureException(
        'windowsMemoryDcUnavailable',
        'Windows could not create a screenshot device context.',
      );
    }
    return _captureFromDeviceContexts(
      screenDc: screenDc,
      memoryDc: memoryDc,
      left: left,
      top: top,
      width: width,
      height: height,
      byteLength: byteLength,
    );
  }

  Uint8List _captureFromDeviceContexts({
    required int screenDc,
    required int memoryDc,
    required int left,
    required int top,
    required int width,
    required int height,
    required int byteLength,
  }) {
    var bitmap = 0;
    var previousObject = 0;
    try {
      bitmap = _createCompatibleBitmap(screenDc, width, height);
      if (bitmap == 0) {
        throw const CockpitWindowsScreenCaptureException(
          'windowsCaptureBitmapUnavailable',
          'Windows could not create a screenshot bitmap.',
        );
      }
      previousObject = _selectObject(memoryDc, bitmap);
      if (previousObject == 0 || previousObject == _gdiError) {
        previousObject = 0;
        throw const CockpitWindowsScreenCaptureException(
          'windowsCaptureBitmapSelectionFailed',
          'Windows could not select the screenshot bitmap.',
        );
      }
      if (_bitBlt(
            memoryDc,
            0,
            0,
            width,
            height,
            screenDc,
            left,
            top,
            _sourceCopy | _captureLayeredWindows,
          ) ==
          0) {
        throw const CockpitWindowsScreenCaptureException(
          'windowsScreenCopyFailed',
          'Windows could not copy the requested screen bounds.',
        );
      }
      _selectObject(memoryDc, previousObject);
      previousObject = 0;
      return _readBitmapPixels(
        memoryDc: memoryDc,
        bitmap: bitmap,
        width: width,
        height: height,
        byteLength: byteLength,
      );
    } finally {
      if (previousObject != 0) {
        _selectObject(memoryDc, previousObject);
      }
      if (bitmap != 0) {
        _deleteObject(bitmap);
      }
      _deleteDc(memoryDc);
      _releaseDc(0, screenDc);
    }
  }

  Uint8List _readBitmapPixels({
    required int memoryDc,
    required int bitmap,
    required int width,
    required int height,
    required int byteLength,
  }) {
    final info = calloc<_WindowsBitmapInfo>();
    final pixels = calloc<Uint8>(byteLength);
    try {
      info.ref.header
        ..size = sizeOf<_WindowsBitmapInfoHeader>()
        ..width = width
        ..height = -height
        ..planes = 1
        ..bitCount = 32
        ..compression = _bitmapCompressionRgb
        ..sizeImage = byteLength;
      final lines = _getDibits(
        memoryDc,
        bitmap,
        0,
        height,
        pixels.cast<Void>(),
        info,
        _dibRgbColors,
      );
      if (lines != height) {
        throw CockpitWindowsScreenCaptureException(
          'windowsCapturePixelReadFailed',
          'Windows returned $lines of $height screenshot rows.',
        );
      }
      return Uint8List.fromList(pixels.asTypedList(byteLength));
    } finally {
      calloc.free(pixels);
      calloc.free(info);
    }
  }
}

const int _maximumWindowsCapturePixels = 64 * 1024 * 1024;
const int _gdiError = -1;
const int _sourceCopy = 0x00cc0020;
const int _captureLayeredWindows = 0x40000000;
const int _bitmapCompressionRgb = 0;
const int _dibRgbColors = 0;

final class _WindowsBitmapInfoHeader extends Struct {
  @Uint32()
  external int size;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Uint16()
  external int planes;

  @Uint16()
  external int bitCount;

  @Uint32()
  external int compression;

  @Uint32()
  external int sizeImage;

  @Int32()
  external int xPixelsPerMeter;

  @Int32()
  external int yPixelsPerMeter;

  @Uint32()
  external int colorsUsed;

  @Uint32()
  external int colorsImportant;
}

final class _WindowsBitmapInfo extends Struct {
  external _WindowsBitmapInfoHeader header;

  @Array(1)
  external Array<Uint32> colors;
}

typedef _GetDcNative = IntPtr Function(IntPtr window);
typedef _GetDcDart = int Function(int window);
typedef _ReleaseDcNative = Int32 Function(IntPtr window, IntPtr deviceContext);
typedef _ReleaseDcDart = int Function(int window, int deviceContext);
typedef _CreateCompatibleDcNative = IntPtr Function(IntPtr deviceContext);
typedef _CreateCompatibleDcDart = int Function(int deviceContext);
typedef _DeleteDcNative = Int32 Function(IntPtr deviceContext);
typedef _DeleteDcDart = int Function(int deviceContext);
typedef _CreateCompatibleBitmapNative =
    IntPtr Function(IntPtr deviceContext, Int32 width, Int32 height);
typedef _CreateCompatibleBitmapDart =
    int Function(int deviceContext, int width, int height);
typedef _SelectObjectNative =
    IntPtr Function(IntPtr deviceContext, IntPtr object);
typedef _SelectObjectDart = int Function(int deviceContext, int object);
typedef _DeleteObjectNative = Int32 Function(IntPtr object);
typedef _DeleteObjectDart = int Function(int object);
typedef _BitBltNative =
    Int32 Function(
      IntPtr destination,
      Int32 destinationX,
      Int32 destinationY,
      Int32 width,
      Int32 height,
      IntPtr source,
      Int32 sourceX,
      Int32 sourceY,
      Uint32 rasterOperation,
    );
typedef _BitBltDart =
    int Function(
      int destination,
      int destinationX,
      int destinationY,
      int width,
      int height,
      int source,
      int sourceX,
      int sourceY,
      int rasterOperation,
    );
typedef _GetDibitsNative =
    Int32 Function(
      IntPtr deviceContext,
      IntPtr bitmap,
      Uint32 startScan,
      Uint32 scanLines,
      Pointer<Void> pixels,
      Pointer<_WindowsBitmapInfo> info,
      Uint32 usage,
    );
typedef _GetDibitsDart =
    int Function(
      int deviceContext,
      int bitmap,
      int startScan,
      int scanLines,
      Pointer<Void> pixels,
      Pointer<_WindowsBitmapInfo> info,
      int usage,
    );
