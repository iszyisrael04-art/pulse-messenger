#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.FaceAnalysis.h>

// Called on a Dart worker isolate; no processing runs on Flutter's UI thread.
extern "C" __declspec(dllexport) int pulse_gift_face(const wchar_t* path, double* out) {
  bool apartment = false;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded); apartment = true;
    using namespace winrt::Windows::Storage;
    using namespace winrt::Windows::Graphics::Imaging;
    using namespace winrt::Windows::Media::FaceAnalysis;
    if (!FaceDetector::IsSupported() ||
        !FaceDetector::IsBitmapPixelFormatSupported(BitmapPixelFormat::Gray8)) {
      winrt::uninit_apartment(); return 0;
    }
    auto file = StorageFile::GetFileFromPathAsync(path).get();
    auto stream = file.OpenAsync(FileAccessMode::Read).get();
    auto decoder = BitmapDecoder::CreateAsync(stream).get();
    auto image = decoder.GetSoftwareBitmapAsync(BitmapPixelFormat::Gray8, BitmapAlphaMode::Ignore).get();
    auto detector = FaceDetector::CreateAsync().get();
    auto faces = detector.DetectFacesAsync(image).get();
    uint64_t largest = 0;
    for (auto face : faces) {
      auto b = face.FaceBox(); auto area = uint64_t(b.Width) * b.Height;
      if (area > largest) {
        largest = area;
        out[0] = double(b.X) / image.PixelWidth();
        out[1] = double(b.Y) / image.PixelHeight();
        out[2] = double(b.Width) / image.PixelWidth();
        out[3] = double(b.Height) / image.PixelHeight();
        out[4] = 0; // WinRT supplies position, not roll. Do not invent head tilt.
      }
    }
    image.Close(); stream.Close();
    winrt::uninit_apartment(); return largest ? 1 : 0;
  } catch (...) {
    if (apartment) winrt::uninit_apartment();
    return -1;
  }
}
