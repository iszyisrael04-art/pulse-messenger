#define NOMINMAX
#include <windows.h>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Media.Editing.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Media.Transcoding.h>
static std::atomic<double> progress_value{0};
static std::atomic<bool> busy{false}, cancelled{false};
extern "C" __declspec(dllexport) double pulse_editor_progress() {return progress_value.load();}
extern "C" __declspec(dllexport) void pulse_editor_cancel() {cancelled=true;}
extern "C" __declspec(dllexport) int pulse_editor_export(const wchar_t* input,const wchar_t* output,int64_t start_ms,int64_t end_ms,int mute) {
  if(busy.exchange(true)) return -2;
  progress_value=0;cancelled=false;bool apartment=false;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);apartment=true;
    using namespace winrt::Windows::Storage;
    using namespace winrt::Windows::Media::Editing;
    using namespace winrt::Windows::Media::MediaProperties;
    auto source=StorageFile::GetFileFromPathAsync(input).get();
    auto clip=MediaClip::CreateFromFileAsync(source).get();
    auto duration=clip.OriginalDuration().count()/10000;
    if(start_ms<0||end_ms<=start_ms||end_ms>duration+100) throw winrt::hresult_invalid_argument();
    end_ms=(end_ms>duration)?duration:end_ms;
    clip.TrimTimeFromStart(winrt::Windows::Foundation::TimeSpan{start_ms*10000});
    clip.TrimTimeFromEnd(winrt::Windows::Foundation::TimeSpan{(duration-end_ms)*10000});
    clip.Volume(mute?0.0:1.0);
    std::filesystem::path path(output);
    auto folder=StorageFolder::GetFolderFromPathAsync(path.parent_path().wstring()).get();
    auto destination=folder.CreateFileAsync(path.filename().wstring(),CreationCollisionOption::FailIfExists).get();
    MediaComposition composition;composition.Clips().Append(clip);
    auto job=composition.RenderToFileAsync(destination,MediaTrimmingPreference::Precise,MediaEncodingProfile::CreateMp4(VideoEncodingQuality::Auto));
    job.Progress([](auto const& operation,double value) {progress_value=value/100.0;if(cancelled.load())operation.Cancel();});
    auto result=job.get();
    if(result!=winrt::Windows::Media::Transcoding::TranscodeFailureReason::None) throw winrt::hresult_error(E_FAIL);
    progress_value=1;busy=false;winrt::uninit_apartment();return 0;
  } catch(...) {
    std::error_code ignored;std::filesystem::remove(output,ignored);busy=false;if(apartment)winrt::uninit_apartment();return cancelled?-3:-1;
  }
}

// Burn the Pulse badge into the exported file, alternating corners every 5s.
extern "C" __declspec(dllexport) int pulse_editor_watermark(const wchar_t* input,const wchar_t* output,const wchar_t* logo) {
  if(busy.exchange(true)) return -2;
  progress_value=0;cancelled=false;bool apartment=false;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);apartment=true;
    using namespace winrt::Windows::Storage;
    using namespace winrt::Windows::Media::Editing;
    using namespace winrt::Windows::Media::MediaProperties;
    using winrt::Windows::Foundation::TimeSpan;
    using winrt::Windows::Foundation::Rect;
    auto source=StorageFile::GetFileFromPathAsync(input).get();
    auto clip=MediaClip::CreateFromFileAsync(source).get();
    const auto duration=clip.OriginalDuration().count();
    const auto props=clip.GetVideoEncodingProperties();
    const float width=static_cast<float>(props.Width()), height=static_cast<float>(props.Height());
    if(duration<=0||width<=0||height<=0) throw winrt::hresult_invalid_argument();
    auto image=StorageFile::GetFileFromPathAsync(logo).get();
    std::filesystem::path path(output);
    auto folder=StorageFolder::GetFolderFromPathAsync(path.parent_path().wstring()).get();
    auto destination=folder.CreateFileAsync(path.filename().wstring(),CreationCollisionOption::FailIfExists).get();
    MediaComposition composition;composition.Clips().Append(clip);
    MediaOverlayLayer layer;
    const float shorter=width<height?width:height;
    const float badge_width=shorter*.30f, badge_height=badge_width*.30f;
    const float margin=shorter*.04f;
    const int64_t interval=50000000; // WinRT time is in 100ns units.
    for(int64_t start=0,segment=0;start<duration;start+=interval,++segment) {
      if(cancelled.load()) throw winrt::hresult_canceled();
      const int64_t remaining=duration-start;
      auto badge=MediaClip::CreateFromImageFileAsync(image,TimeSpan{remaining<interval?remaining:interval}).get();
      const bool left=segment%2==0;
      Rect position{left?margin:width-badge_width-margin,left?margin:height-badge_height-margin,badge_width,badge_height};
      MediaOverlay overlay(badge,position,.88);
      overlay.Delay(TimeSpan{start});overlay.AudioEnabled(false);
      layer.Overlays().Append(overlay);
    }
    composition.OverlayLayers().Append(layer);
    auto job=composition.RenderToFileAsync(destination,MediaTrimmingPreference::Precise,MediaEncodingProfile::CreateMp4(VideoEncodingQuality::Auto));
    job.Progress([](auto const& operation,double value) {progress_value=value/100.0;if(cancelled.load())operation.Cancel();});
    const auto result=job.get();
    if(result!=winrt::Windows::Media::Transcoding::TranscodeFailureReason::None) throw winrt::hresult_error(E_FAIL);
    progress_value=1;busy=false;winrt::uninit_apartment();return 0;
  } catch(...) {
    std::error_code ignored;std::filesystem::remove(output,ignored);busy=false;if(apartment)winrt::uninit_apartment();return cancelled?-3:-1;
  }
}
