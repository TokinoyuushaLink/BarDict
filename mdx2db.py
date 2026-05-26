# /// script
# requires-python = ">=3.9"
# dependencies = ["mdict-utils"]
# ///
"""
MDX → SQLite 转换工具（供 BarDict 使用）

用法:
  uv run mdx2db.py 词典.mdx            # 自动输出到 ~/Library/Application Support/BarDict/
  uv run mdx2db.py 词典.mdx 输出.sqlite

依赖由 uv 自动安装，无需手动建虚拟环境。
"""

import re
import sqlite3
import struct
import sys
import pathlib


# ── LZO 兼容补丁 ──────────────────────────────────────────────────────────────
# mdict_utils 自带纯 Python LZO 实现，但仅在 C 扩展不可用时会留空 (lzo = None)。
# 此处手动注入：剥除 5 字节 python-lzo 格式头，再调用纯 Python 解压器。
def _patch_lzo():
    import mdict_utils.base.readmdict as _rdm
    if _rdm.lzo is not None:
        return  # C 扩展可用，无需补丁
    try:
        import mdict_utils.base.lzo as _lzo_py

        class _LzoAdapter:
            @staticmethod
            def decompress(data: bytes) -> bytes:
                # data = b'\xf0' + 4-byte-uncompressed-size + lzo1x-compressed
                decompressed_size = struct.unpack('>I', data[1:5])[0]
                return _lzo_py.decompress(data[5:], initSize=decompressed_size)

        _rdm.lzo = _LzoAdapter
    except Exception:
        pass  # 无法补丁时由 mdict_utils 本身报错，给出原始信息


_patch_lzo()

from mdict_utils.base.readmdict import MDX  # noqa: E402


# ── 主逻辑 ────────────────────────────────────────────────────────────────────

CSS_LINK_RE = re.compile(r'<link[^>]+rel=["\']stylesheet["\'][^>]*/?\>', re.IGNORECASE)


def convert(mdx_path: pathlib.Path, db_path: pathlib.Path) -> None:
    # 检测同名 CSS 文件
    css_path = mdx_path.with_suffix('.css')
    css_content: str | None = None
    if css_path.exists():
        css_content = css_path.read_text(encoding='utf-8', errors='ignore')
        print(f"  发现附属 CSS: {css_path.name}")

    print(f"正在读取: {mdx_path.name} …")
    try:
        mdx = MDX(str(mdx_path))
    except RuntimeError as e:
        msg = str(e)
        if 'LZO' in msg:
            sys.exit(
                '❌ LZO 解压失败。\n'
                '   该词典使用 MDict 1.x LZO 压缩。纯 Python 回退也无法处理，\n'
                '   请安装 C 扩展: pip install python-lzo，再重试。'
            )
        sys.exit(f'❌ 打开词典失败: {e}')

    # 建库
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute('DROP TABLE IF EXISTS entries')
    cur.execute('DROP TABLE IF EXISTS meta')
    cur.execute('CREATE TABLE entries (word TEXT, html TEXT)')
    cur.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)')

    if css_content:
        cur.execute('INSERT INTO meta VALUES (?, ?)', ('css', css_content))

    count = 0
    batch: list[tuple[str, str]] = []
    print('正在转换词条…')

    for key, val in mdx.items():
        word = key.decode('utf-8', 'ignore') if isinstance(key, bytes) else key
        html = val.decode('utf-8', 'ignore') if isinstance(val, bytes) else val
        word = word.strip()
        if not word:
            continue
        html = CSS_LINK_RE.sub('', html)
        batch.append((word, html))
        count += 1
        if len(batch) >= 2000:
            cur.executemany('INSERT INTO entries VALUES (?, ?)', batch)
            batch.clear()
            print(f'\r  已处理 {count} 条…', end='', flush=True)

    if batch:
        cur.executemany('INSERT INTO entries VALUES (?, ?)', batch)

    cur.execute('CREATE INDEX idx_word ON entries(word COLLATE NOCASE)')
    conn.commit()
    conn.close()
    print(f'\r✅ 完成，共 {count} 条 → {db_path}')


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        sys.exit(0)

    mdx_path = pathlib.Path(sys.argv[1])
    if not mdx_path.exists():
        sys.exit(f'❌ 文件不存在: {mdx_path}')
    if mdx_path.suffix.lower() != '.mdx':
        sys.exit(f'❌ 需要 .mdx 文件，收到: {mdx_path.suffix}')

    if len(sys.argv) >= 3:
        db_path = pathlib.Path(sys.argv[2])
    else:
        support = pathlib.Path.home() / 'Library' / 'Application Support' / 'BarDict'
        db_path = support / f'{mdx_path.stem}.sqlite'

    convert(mdx_path, db_path)


if __name__ == '__main__':
    main()