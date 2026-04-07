#!/usr/bin/env python3
import sys
import re

lines = sys.stdin.readlines()
if len(lines) >= 90:
    # line index 89 (0-based)
    line = lines[89]
    # Insert a single quote before underscore after "${pkg}"?
    # We'll replace the pattern: "${pkg}"_ with "${pkg}"'_
    # Use regex: (\"\\$\\{pkg\\}\")_
    # Actually the line contains '"${pkg}"_'
    # We'll do simple replacement: '"${pkg}"_' -> '"${pkg}"'_'
    # But there may be spaces. Let's just replace the substring.
    # Find position of '"${pkg}"_' (assuming pkg variable name is pkg)
    # We'll use a more generic approach: find the sequence: " ${pkg} " _? Not.
    # Let's just replace the line with our corrected line from earlier.
    # However we need to keep indentation.
    # Extract indentation spaces.
    indent = line[:len(line) - len(line.lstrip())]
    # Construct new line with same indentation.
    # The corrected line we know works:
    # pkg_links="$(echo "$page_content" | grep -o 'href="/projects/openwrt-passwall-build/files/[^"]*'"${pkg}"'_[^"]*\.ipk[^"]*"' | sed 's|^href="||;s|"$||' | head -n1)"
    # But we need to keep the variable name (pkg) same.
    # We'll just replace the grep pattern part.
    # Let's use regex to replace the grep pattern segment.
    # Simpler: we can just insert a single quote after "${pkg}" and before underscore.
    # Find '"${pkg}"_' pattern.
    pattern = r'(\"\$\{pkg\}\")_'
    new_line = re.sub(pattern, r"\1'_", line)
    if new_line != line:
        lines[89] = new_line
        sys.stdout.write(''.join(lines))
    else:
        # fallback: use our corrected line
        # but we need to preserve indentation.
        # We'll just output the whole fixed script we already have? Not.
        sys.stdout.write(''.join(lines))
else:
    sys.stdout.write(''.join(lines))