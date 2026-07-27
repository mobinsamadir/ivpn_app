import sys

def parse_lcov(file_path):
    files = {}
    current_file = None
    with open(file_path, 'r') as f:
        for line in f:
            if line.startswith('SF:'):
                current_file = line.strip()[3:]
                files[current_file] = {'LF': 0, 'LH': 0}
            elif line.startswith('LF:'):
                files[current_file]['LF'] = int(line.strip()[3:])
            elif line.startswith('LH:'):
                files[current_file]['LH'] = int(line.strip()[3:])

    total_lf = 0
    total_lh = 0
    for file, cov in files.items():
        if 'lib/' in file:
            total_lf += cov['LF']
            total_lh += cov['LH']

    print(f"Total Coverage: {(total_lh / total_lf) * 100:.2f}%")

parse_lcov('coverage/lcov.info')
