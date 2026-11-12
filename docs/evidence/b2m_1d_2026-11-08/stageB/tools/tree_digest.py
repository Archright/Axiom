#!/usr/bin/env python3
"""Canonical tree digest: sha256 per regular file (symlinks skipped+counted),
listing lines "<sha256>  <relpath> <bytes>\n" sorted by relpath, then sha256 of listing."""
import hashlib, json, os, sys

def tree_digest(root):
    files, symlinks, other = [], 0, 0
    total_bytes = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                symlinks += 1
                continue
            st = os.stat(p)
            if not os.path.isfile(p):
                other += 1
                continue
            h = hashlib.sha256()
            with open(p, 'rb') as f:
                for chunk in iter(lambda: f.read(1 << 20), b''):
                    h.update(chunk)
            files.append((rel, st.st_size, h.hexdigest()))
            total_bytes += st.st_size
    files.sort()
    listing = ''.join(f"{sha}  {rel} {size}\n" for rel, size, sha in files)
    return {
        "root": os.path.abspath(root),
        "file_count": len(files),
        "total_bytes": total_bytes,
        "symlink_count": symlinks,
        "other_count": other,
        "tree_digest_sha256": hashlib.sha256(listing.encode()).hexdigest(),
    }

if __name__ == '__main__':
    out_path = sys.argv[1]
    out = {}
    for root in sys.argv[2:]:
        out[root] = tree_digest(root)
        print(root, out[root]['file_count'], out[root]['total_bytes'], out[root]['tree_digest_sha256'][:16], flush=True)
    json.dump(out, open(out_path, 'w'), indent=1, ensure_ascii=False)
    print('written', out_path)
