"""Exercise DLL bundling with Flutter's generator-expression install prefix."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class BundleInstallationTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('cmake'), 'CMake is needed for bundle regression')
    def test_explicit_destination_expands_flutter_bundle_prefix(self):
        with tempfile.TemporaryDirectory(prefix='pulse install ') as folder:
            root = Path(folder)
            (root / 'app.cpp').write_text('int main() { return 0; }')
            (root / 'editor.cpp').write_text('''
#ifdef _WIN32
__declspec(dllexport)
#endif
int fixture() { return 1; }
''')
            (root / 'CMakeLists.txt').write_text('''
cmake_minimum_required(VERSION 3.14)
project(PulseInstallFixture LANGUAGES CXX)
add_executable(Pulse app.cpp)
add_library(pulse_editor SHARED editor.cpp)
add_dependencies(Pulse pulse_editor)
set_target_properties(Pulse pulse_editor PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>")
# This deliberately reproduces Flutter's unusual prefix, not a normal prefix.
set(CMAKE_INSTALL_PREFIX "$<TARGET_FILE_DIR:Pulse>" CACHE PATH "fixture" FORCE)
install(FILES "$<TARGET_FILE:pulse_editor>"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
''')
            output = root / 'build'
            for command in [
                ['cmake', '-S', str(root), '-B', str(output), '-DCMAKE_BUILD_TYPE=Release'],
                ['cmake', '--build', str(output), '--config', 'Release'],
                ['cmake', '--install', str(output), '--config', 'Release', '--component', 'Runtime'],
            ]:
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            bundle = output / 'runner/Release'
            self.assertTrue(any(p.name.endswith(('.dll', '.so', '.dylib')) for p in bundle.iterdir()))
            self.assertFalse(any('$<' in str(p.relative_to(root)) for p in root.rglob('*')))


if __name__ == '__main__':
    unittest.main()
