import re
import sys

def report(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return

    blocks = content.split('end_of_record')
    for block in blocks:
        if 'SF:' in block:
            sf_match = re.search(r'SF:(.+)', block)
            lh_match = re.search(r'LH:(\d+)', block)
            lf_match = re.search(r'LF:(\d+)', block)
            if sf_match and lh_match and lf_match:
                sf = sf_match.group(1)
                lh = int(lh_match.group(1))
                lf = int(lf_match.group(1))
                if lf > 0 and 'lib/utils/' in sf:
                    print(f'{sf}: {lh}/{lf} ({(lh/lf)*100:.2f}%)')

report('coverage/lcov.info')
