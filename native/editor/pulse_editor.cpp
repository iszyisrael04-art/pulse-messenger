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
