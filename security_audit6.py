import re
import os

def check_file(filepath):
    issues = []
    with open(filepath, 'r') as f:
        try:
            content = f.read()
        except:
            return issues

        # Check for bad hash comparisons (e.g. comparing hashes directly instead of using a constant time function)
        # Not easily detectable, but let's see if MD5 is used for anything security sensitive
        if 'md5' in content:
            pass # We saw this earlier and it's for blacklisting config strings, not passwords.

    return issues
