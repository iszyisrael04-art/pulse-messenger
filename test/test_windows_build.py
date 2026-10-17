import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'scripts/build_windows.py'
spec = importlib.util.spec_from_file_location('pulse_windows_build', path)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class WindowsBuildDiagnosticsTest(unittest.TestCase):
    def test_original_failure_is_not_hidden_by_successful_diagnostics(self):
        with tempfile.TemporaryDirectory(prefix='pulse build ') as folder:
            root = Path(folder)
            generated = root / 'build/windows/x64/cmake_install.cmake'
            generated.parent.mkdir(parents=True)
            generated.write_text('# fixture')
            with patch.object(builder.shutil, 'which', side_effect=['flutter.bat', 'cmake.exe']), patch.object(builder, 'run_logged', side_effect=[1, 0]) as run:
                self.assertEqual(builder.build(root), 1)
                self.assertEqual(run.call_count, 2)
                self.assertEqual(run.call_args.args[0], ['cmake.exe', '--install', str(generated.parent), '--config', 'Release', '--verbose'])

    def test_success_does_not_rerun_install(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(builder.shutil, 'which', return_value='flutter.bat'), patch.object(builder, 'run_logged', return_value=0) as run:
                self.assertEqual(builder.build(Path(folder)), 0)
                self.assertEqual(run.call_count, 1)
                self.assertIn('--verbose', run.call_args.args[0])

    def test_cp1252_console_preserves_unicode_file_and_native_exit_code(self):
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                log = root / 'unicode.log'
                raw = io.BytesIO()
                console = io.TextIOWrapper(raw, encoding='cp1252', errors='strict')
                def execute(command, **kwargs):
                    kwargs['stdout'].write('√ Built Pulse.exe 💚\n')
                    class Result:
                        returncode = exit_code
                    return Result()
                with patch.object(builder.subprocess, 'run', side_effect=execute), patch.object(builder.sys, 'stdout', console):
                    code = builder.run_logged(['fixture'], log, root)
                self.assertEqual(code, exit_code)
                self.assertIn(b'\\u221a', raw.getvalue())
                self.assertEqual(log.read_text(encoding='utf-8'), '√ Built Pulse.exe 💚\n')
                console.close()

    def test_log_preserves_underlying_error_and_exit_code(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            log = root / 'windows-build.log'
            def execute(command, **kwargs):
                kwargs['stdout'].write('CMake Error: fixture file could not be copied\n')
                class Result:
                    returncode = 5
                return Result()
            with patch.object(builder.subprocess, 'run', side_effect=execute):
                self.assertEqual(builder.run_logged(['fixture'], log, root), 5)
            self.assertIn('CMake Error:', log.read_text())


if __name__ == '__main__':
    unittest.main()
