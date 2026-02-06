import os
import json
import shutil
from datetime import datetime
from pathlib import Path

class ProjectAnalyzer:
    def __init__(self, project_root="."):
        self.project_root = Path(project_root)
        self.log_file = f"analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        self.stats = {
            'total_files': 0,
            'total_dirs': 0,
            'duplicate_files': [],
            'temp_files': [],
            'large_files': [],
            'build_artifacts': [],
            'flutter_specific': [],
            'config_files': []
        }
    
    def log(self, message, level="INFO"):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry.encode('utf-8', errors='replace').decode('utf-8'))
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(log_entry + '\n')

    def analyze(self):
        self.log("Starting project structure analysis")
        
        for root, dirs, files in os.walk(self.project_root):
            # Exclude build directories to focus on source code
            dirs[:] = [d for d in dirs if d not in ['.git', 'node_modules', 'build', '.dart_tool', '.pub_cache', 'windows\\build', 'windows\\runner\\build']]
            
            for file in files:
                file_path = Path(root) / file
                relative_path = file_path.relative_to(self.project_root)
                
                self.stats['total_files'] += 1
                
                # Identify config files
                if self._is_config_file(file):
                    self.stats['config_files'].append(str(relative_path))
                    self.log(f"Config file: {relative_path}", "INFO")

                # Identify temp files
                if self._is_temp_file(file):
                    self.stats['temp_files'].append(str(relative_path))
                    self.log(f"Temporary file: {relative_path}", "WARNING")

                # Identify build artifacts
                if self._is_build_artifact(file, relative_path):
                    self.stats['build_artifacts'].append(str(relative_path))
                    self.log(f"Build artifact: {relative_path}", "WARNING")
                
                # Identify large files (> 500KB)
                size = file_path.stat().st_size / 1024  # KB
                if size > 500:  # More than 500KB
                    self.stats['large_files'].append({
                        'path': str(relative_path),
                        'size_kb': round(size, 2)
                    })
        
        # Count directories
        for root, dirs, files in os.walk(self.project_root):
            dirs[:] = [d for d in dirs if d not in ['.git', 'node_modules', 'build', '.dart_tool', '.pub_cache', 'windows\\build', 'windows\\runner\\build']]
            self.stats['total_dirs'] += len(dirs)
        
        self._generate_report()
    
    
    def _is_config_file(self, filename):
        config_extensions = ['.json', '.yaml', '.yml', '.txt', '.env', '.cfg', '.ini', '.properties']
        config_patterns = ['config', 'setting', 'pubspec', 'analysis']
        
        if any(filename.endswith(ext) for ext in config_extensions):
            return True
        if any(pattern in filename.lower() for pattern in config_patterns):
            return True
        return False
    
    def _is_temp_file(self, filename):
        temp_extensions = ['.log', '.tmp', '.temp', '.cache', '.crswap', '.lock']
        temp_patterns = ['debug_', 'test_', 'build_', 'analysis_', 'temp_']
        
        if any(filename.endswith(ext) for ext in temp_extensions):
            return True
        if any(pattern in filename.lower() for pattern in temp_patterns):
            return True
        return False
    
    def _is_build_artifact(self, filename, relative_path):
        build_patterns = ['.apk', '.aab', '.ipa', '.app', '.exe', '.dll', '.so', '.dylib', '.aar']
        build_paths = ['build/', 'dist/', 'out/', 'target/', 'windows/runner/Debug/', 'windows/runner/Release/']
        
        if any(filename.endswith(ext) for ext in build_patterns):
            return True
        if any(str(relative_path).startswith(p) for p in build_paths):
            return True
        return False
    
    def _generate_report(self):
        self.log("\n📊 Complete Analysis Report")
        self.log(f"Total files: {self.stats['total_files']}")
        self.log(f"Total directories: {self.stats['total_dirs']}")
        self.log(f"Flutter-specific files: {len(self.stats['flutter_specific'])}")
        self.log(f"Config files: {len(self.stats['config_files'])}")
        self.log(f"Temporary files: {len(self.stats['temp_files'])}")
        self.log(f"Build artifacts: {len(self.stats['build_artifacts'])}")
        self.log(f"Large files (>500KB): {len(self.stats['large_files'])}")
        
        # Save detailed report
        report_path = 'project_analysis_report.json'
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(self.stats, f, indent=2, ensure_ascii=False)
        
        self.log(f"✅ Report saved to {report_path}")

# Run the analyzer
if __name__ == "__main__":
    analyzer = ProjectAnalyzer()
    analyzer.analyze()